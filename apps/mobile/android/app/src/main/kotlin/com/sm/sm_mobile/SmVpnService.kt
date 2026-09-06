package com.sm.sm_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.IpPrefix
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.io.File
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.util.concurrent.Executors
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

/// 前台 VpnService：进程内直接宿主 libbox（sing-box 核心）。
/// 架构为 SFA 的精简单进程版：无 AIDL/命令通道，状态与日志经 VpnEvents 送回 Flutter。
class SmVpnService : VpnService(), PlatformInterface {
    companion object {
        private const val TAG = "SmVpnService"
        const val ACTION_START = "com.sm.sm_mobile.vpn.START"
        const val ACTION_STOP = "com.sm.sm_mobile.vpn.STOP"
        const val EXTRA_CONFIG_PATH = "config_path"

        @Volatile
        var isRunning = false
            private set
    }

    private var boxService: BoxService? = null
    private var tunFd: ParcelFileDescriptor? = null
    private val serviceThread = Executors.newSingleThreadExecutor()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpn()
            else -> startVpn(intent?.getStringExtra(EXTRA_CONFIG_PATH))
        }
        return START_STICKY
    }

    override fun onRevoke() {
        // 用户在系统设置里断开 VPN
        stopVpn()
    }

    override fun onDestroy() {
        serviceThread.shutdown()
        super.onDestroy()
    }

    private fun startVpn(configPath: String?) {
        if (isRunning || boxService != null) {
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
        serviceThread.execute {
            try {
                val config = File(configPath).readText()
                val service = Libbox.newService(config, this)
                boxService = service
                service.start()
                isRunning = true
                VpnEvents.status("started")
            } catch (e: Exception) {
                Log.e(TAG, "start failed", e)
                VpnEvents.error(e.message ?: e.toString())
                VpnEvents.log("[vpn] 启动失败: ${e.message}")
                isRunning = false
                boxService = null
                shutdownService()
                VpnEvents.status("stopped")
            }
        }
    }

    private fun stopVpn() {
        if (!isRunning && boxService == null) {
            VpnEvents.status("stopped")
            shutdownService()
            return
        }
        VpnEvents.status("stopping")
        serviceThread.execute {
            try {
                boxService?.close()
            } catch (e: Exception) {
                Log.e(TAG, "close failed", e)
            } finally {
                isRunning = false
                boxService = null
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
            .setContentText("VPN 运行中")
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

    // ─── PlatformInterface（libbox v1.12.14）──────────────────────────────────

    override fun localDNSTransport(): LocalDNSTransport = LocalResolver

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!protect(fd)) throw IllegalStateException("protect fd failed")
    }

    private val v4Addresses = mutableListOf<Pair<String, Int>>()
    private val v6Addresses = mutableListOf<Pair<String, Int>>()

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing vpn permission")

        // 先物化地址列表（gomobile 迭代器只能遍历一次）
        v4Addresses.clear()
        v6Addresses.clear()
        val i4 = options.inet4Address
        while (i4.hasNext()) {
            val p = i4.next()
            v4Addresses.add(p.address() to p.prefix())
        }
        val i6 = options.inet6Address
        while (i6.hasNext()) {
            val p = i6.next()
            v6Addresses.add(p.address() to p.prefix())
        }

        val builder = Builder()
            .setSession("SM GUI")
            .setMtu(options.mtu)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        for ((addr, prefix) in v4Addresses) builder.addAddress(addr, prefix)
        for ((addr, prefix) in v6Addresses) builder.addAddress(addr, prefix)

        if (options.autoRoute) {
            // DNS 劫持地址（sing-tun 需要 /30 段才有；fakeip 等场景可能失败则跳过）
            runCatching { builder.addDnsServer(options.dnsServerAddress.value) }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                if (r4.hasNext()) {
                    while (r4.hasNext()) {
                        val p = r4.next()
                        builder.addRoute(p.address(), p.prefix())
                    }
                } else if (v4Addresses.isNotEmpty()) {
                    builder.addRoute("0.0.0.0", 0)
                }
                val r6 = options.inet6RouteAddress
                if (r6.hasNext()) {
                    while (r6.hasNext()) {
                        val p = r6.next()
                        builder.addRoute(p.address(), p.prefix())
                    }
                } else if (v6Addresses.isNotEmpty()) {
                    builder.addRoute("::", 0)
                }
                // route exclude 仅 API 34+ 支持（本应用生成的配置不含排除路由，防御性处理）
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val ex4 = options.inet4RouteExcludeAddress
                    while (ex4.hasNext()) {
                        val p = ex4.next()
                        builder.excludeRoute(IpPrefix(InetAddress.getByName(p.address()), p.prefix()))
                    }
                    val ex6 = options.inet6RouteExcludeAddress
                    while (ex6.hasNext()) {
                        val p = ex6.next()
                        builder.excludeRoute(IpPrefix(InetAddress.getByName(p.address()), p.prefix()))
                    }
                }
            } else {
                val r4 = options.inet4RouteRange
                if (r4.hasNext()) {
                    while (r4.hasNext()) {
                        val p = r4.next()
                        builder.addRoute(p.address(), p.prefix())
                    }
                } else if (v4Addresses.isNotEmpty()) {
                    builder.addRoute("0.0.0.0", 0)
                }
                val r6 = options.inet6RouteRange
                if (r6.hasNext()) {
                    while (r6.hasNext()) {
                        val p = r6.next()
                        builder.addRoute(p.address(), p.prefix())
                    }
                } else if (v6Addresses.isNotEmpty()) {
                    builder.addRoute("::", 0)
                }
            }

            val includePackage = options.includePackage
            while (includePackage.hasNext()) {
                runCatching { builder.addAllowedApplication(includePackage.next()) }
            }
            val excludePackage = options.excludePackage
            while (excludePackage.hasNext()) {
                runCatching { builder.addDisallowedApplication(excludePackage.next()) }
            }
        }

        val pfd = builder.establish()
            ?: error("android: the application is not prepared or is revoked")
        tunFd = pfd
        return pfd.fd
    }

    override fun writeLog(message: String) {
        VpnEvents.log(message)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            error("requires Android 10")
        }
        val uid = SmApplication.connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == android.os.Process.INVALID_UID) error("android: connection owner not found")
        return uid
    }

    override fun packageNameByUid(uid: Int): String =
        SmApplication.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: ""

    override fun uidByPackageName(packageName: String?): Int {
        val name = packageName ?: ""
        val uid = SmApplication.packageManager.getPackageUid(name, 0)
        if (uid == -1) throw IllegalArgumentException("package not found: $name")
        return uid
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(null)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        val networkInterfaces = runCatching {
            NetworkInterface.getNetworkInterfaces()?.toList()
        }.getOrDefault(emptyList()) ?: emptyList()
        for (nif in networkInterfaces) {
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = nif.name
            boxInterface.index = nif.index
            runCatching { boxInterface.mtu = nif.mtu }
            boxInterface.addresses = StringArray(
                nif.interfaceAddresses.map { addr ->
                    if (addr.address is Inet6Address) {
                        "${addr.address.hostAddress}/${addr.networkPrefixLength}"
                    } else {
                        "${addr.address.hostAddress}/${addr.networkPrefixLength}"
                    }
                }.iterator(),
            )
            boxInterface.flags = when {
                nif.isLoopback -> 8 // IFF_LOOPBACK
                nif.isUp -> 1 or 64 // IFF_UP | IFF_RUNNING（Java 层无法查询 RUNNING，按 up 处理）
                else -> 0
            }
            boxInterface.type = when {
                nif.name.startsWith("wlan") -> Libbox.InterfaceTypeWIFI
                nif.name.startsWith("rmnet") || nif.name.startsWith("ccmni") ->
                    Libbox.InterfaceTypeCellular
                nif.name.startsWith("eth") -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.dnsServer = StringArray(emptyList<String>().iterator())
            boxInterface.metered = false
            interfaces.add(boxInterface)
        }
        return InterfaceArray(interfaces.iterator())
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun systemCertificates(): StringIterator = StringArray(emptyList<String>().iterator())

    override fun clearDNSCache() {
    }

    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
        // 前台通知由本服务自管，忽略 libbox 的通知请求
    }

    // ─── gomobile 迭代器适配 ────────────────────────────────────────────────────

    class StringArray(private val iterator: Iterator<String>) : StringIterator {
        override fun len(): Int = 0 // core 不使用
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
    }

    class InterfaceArray(private val iterator: Iterator<LibboxNetworkInterface>) :
        NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): LibboxNetworkInterface = iterator.next()
    }
}
