package com.sm.sm_mobile

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Flutter ↔ 原生桥：
///   MethodChannel `sm_gui/vpn`:
///     prepare() → Future<bool>                  请求 VPN 权限（弹系统授权页）
///     start(configPath, core, stack) → void      启动前台 VpnService（按内核路由）
///     stop() → void                              两个服务都发停止（各自幂等）
///     isRunning(core) → bool
///   EventChannel `sm_gui/vpn/events`: 状态/日志/错误事件（契约见 VpnEvents）
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "sm_gui/vpn"
        private const val EVENTS = "sm_gui/vpn/events"
        private const val REQUEST_VPN = 1001
    }

    private var vpnPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> requestVpnPermission(result)
                    "start" -> {
                        val path = call.argument<String>("configPath")
                        val core = call.argument<String>("core") ?: "sing-box"
                        val stack = call.argument<String>("stack") ?: "mixed"
                        if (path == null) {
                            result.error("invalid_args", "configPath required", null)
                            return@setMethodCallHandler
                        }
                        val serviceClass = if (core == "mihomo") SmMihomoVpnService::class.java
                        else SmVpnService::class.java
                        val intent = Intent(this, serviceClass)
                            .setAction(SmVpnService.ACTION_START)
                            .putExtra(SmVpnService.EXTRA_CONFIG_PATH, path)
                            .putExtra(SmMihomoVpnService.EXTRA_STACK, stack)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        // 两个服务都发停止（各自幂等，仅运行中的会有实际动作）
                        for (cls in listOf(SmVpnService::class.java, SmMihomoVpnService::class.java)) {
                            val intent = Intent(this, cls).setAction(SmVpnService.ACTION_STOP)
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "isRunning" -> {
                        val core = call.argument<String>("core") ?: "sing-box"
                        result.success(
                            if (core == "mihomo") SmMihomoVpnService.isRunning else SmVpnService.isRunning,
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    mainHandler.post { VpnEvents.setSink(events) }
                }

                override fun onCancel(args: Any?) {
                    mainHandler.post { VpnEvents.setSink(null) }
                }
            })
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        if (vpnPermissionResult != null) {
            result.error("busy", "已有授权请求进行中", null)
            return
        }
        val intent = VpnService.prepare(this)
        if (intent == null) {
            // 已有 VPN 权限
            result.success(true)
            return
        }
        vpnPermissionResult = result
        try {
            startActivityForResult(intent, REQUEST_VPN)
        } catch (e: Exception) {
            vpnPermissionResult = null
            result.success(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN) {
            val pending = vpnPermissionResult
            vpnPermissionResult = null
            pending?.success(resultCode == RESULT_OK)
        }
    }
}
