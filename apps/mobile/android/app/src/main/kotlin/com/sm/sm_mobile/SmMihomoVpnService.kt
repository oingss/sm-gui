package com.sm.sm_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.mihomocore.EventCallback
import io.nekohasekai.mihomocore.Mihomocore
import java.io.File
import java.net.InetSocketAddress
import java.util.concurrent.Executors

/// mihomo 前台 VpnService：内核经 gomobile 桥（libmihomo.aar，源码在
/// apps/mobile/core）进程内运行。TUN fd 由本服务建立后交给桥
/// （sing_tun FileDescriptor 模式），protect/按应用分流经回调实现。
class SmMihomoVpnService : VpnService() {
    companion object {
        private const val TAG = "SmMihomoVpn"
        const val ACTION_START = "com.sm.sm_mobile.mihomo.START"
        const val ACTION_STOP = "com.sm.sm_mobile.mihomo.STOP"
        const val EXTRA_CONFIG_PATH = "config_path"
        const val EXTRA_STACK = "stack"

        // TUN 地址段/DNS 劫持与 sing-box 配置保持一致（两内核不会同时运行）
        private const val TUN_ADDRESS = "172.19.0.1/30,fdfe:dcba:9876::1/126"
        private const val TUN_DNS = "172.19.0.2,fdfe:dcba:9876::2"

        @Volatile
        var isRunning = false
            private set
    }

    private var tunFd: ParcelFileDescriptor? = null
    private var starting = false
    private val serviceThread = Executors.newSingleThreadExecutor()

    private inner class Bridge : EventCallback {
        override fun onLog(level: String?, message: String?) {
            VpnEvents.log("[mihomo][${level ?: "info"}] ${message ?: ""}")
        }

        override fun protect(fd: Int): Boolean {
            // 回调发生在 Go 线程，protect 需要切到主线程（VpnService 线程约束）
            var result = false
            val latch = java.util.concurrent.CountDownLatch(1)
            mainExecutor.execute {
                try {
                    result = this@SmMihomoVpnService.protect(fd)
                } finally {
                    latch.countDown()
                }
            }
            latch.await(3, java.util.concurrent.TimeUnit.SECONDS)
            return result
        }

        override fun resolveProcess(
            protocol: Int,
            source: String?,
            target: String?,
            uid: Int,
        ): String {
            var realUid = uid
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                source != null && target != null
            ) {
                val src = parseSockAddr(source)
                val dst = parseSockAddr(target)
                if (src != null && dst != null) {
                    val owner = runCatching {
                        SmApplication.connectivity.getConnectionOwnerUid(protocol, src, dst)
                    }.getOrDefault(android.os.Process.INVALID_UID)
                    if (owner != android.os.Process.INVALID_UID) realUid = owner
                }
            }
            if (realUid < 0 || realUid == android.os.Process.INVALID_UID) return ""
            return SmApplication.packageManager.getPackagesForUid(realUid)?.firstOrNull() ?: ""
        }
    }

    private val bridge = Bridge()

    override fun onCreate() {
        super.onCreate()
        runCatching {
            val home = File(filesDir, "mihomo")
            home.mkdirs()
            Mihomocore.setup(home.path)
        }.onFailure { Log.e(TAG, "setup failed", it) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpn()
            else -> startVpn(
                intent?.getStringExtra(EXTRA_CONFIG_PATH),
                intent?.getStringExtra(EXTRA_STACK) ?: "mixed",
            )
        }
        return START_STICKY
    }

    override fun onRevoke() {
        stopVpn()
    }

    override fun onDestroy() {
        serviceThread.shutdown()
        super.onDestroy()
    }

    private fun startVpn(configPath: String?, stack: String) {
        if (isRunning || starting) {
            VpnEvents.status("started")
            return
        }
        goForeground()
        VpnEvents.status("starting")
        if (configPath == null) {
            VpnEvents.error("缺少配置文件路径")
            shutdownService()
            return
        }
        starting = true
        serviceThread.execute {
            try {
                val config = File(configPath).readText()
                Mihomocore.startService(config, bridge)

                // 建立 VPN 接口，把 fd 交给 mihomo 桥
                val builder = Builder()
                    .setSession("SM GUI (mihomo)")
                    .setMtu(9000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
                for (a in TUN_ADDRESS.split(",")) {
                    val parts = a.trim().split("/")
                    builder.addAddress(parts[0], parts[1].toInt())
                }
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
                for (d in TUN_DNS.split(",")) builder.addDnsServer(d.trim())
                val pfd = builder.establish()
                    ?: error("android: the application is not prepared or is revoked")
                tunFd = pfd
                Mihomocore.startTun(pfd.fd, stack, TUN_ADDRESS, TUN_DNS, bridge)

                isRunning = true
                VpnEvents.status("started")
            } catch (e: Exception) {
                Log.e(TAG, "start failed", e)
                VpnEvents.error(e.message ?: e.toString())
                VpnEvents.log("[mihomo] 启动失败: ${e.message}")
                runCatching { Mihomocore.stopTun() }
                runCatching { Mihomocore.stopService() }
                tunFd = null
                shutdownService()
                VpnEvents.status("stopped")
            } finally {
                starting = false
            }
        }
    }

    private fun stopVpn() {
        if (!isRunning && tunFd == null) {
            VpnEvents.status("stopped")
            shutdownService()
            return
        }
        VpnEvents.status("stopping")
        serviceThread.execute {
            try {
                runCatching { Mihomocore.stopTun() }
                runCatching { Mihomocore.stopService() }
            } finally {
                isRunning = false
                tunFd = null
                shutdownService()
                VpnEvents.status("stopped")
            }
        }
    }

    private fun shutdownService() {
        tunFd = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun goForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel("vpn", "VPN 连接", NotificationManager.IMPORTANCE_LOW),
        )
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(this, "vpn")
            .setContentTitle("SM GUI")
            .setContentText("VPN 运行中 (mihomo)")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(1, notification)
        }
    }

    private fun parseSockAddr(s: String): InetSocketAddress? = runCatching {
        if (s.startsWith("[")) {
            val end = s.indexOf(']')
            val host = s.substring(1, end)
            val port = s.substring(end + 2).toInt()
            InetSocketAddress(host, port)
        } else {
            val i = s.lastIndexOf(':')
            InetSocketAddress(s.substring(0, i), s.substring(i + 1).toInt())
        }
    }.getOrNull()
}
