package com.sm.sm_mobile

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/// VpnService → Flutter 事件桥（契约见 packages/ui_mobile/lib/src/vpn_engine.dart）：
///   {type: 'status', status: 'starting'|'started'|'stopping'|'stopped'}
///   {type: 'log', line: String}
///   {type: 'error', message: String}
object VpnEvents {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun setSink(sink: EventChannel.EventSink?) {
        this.sink = sink
    }

    fun status(status: String) = post(mapOf("type" to "status", "status" to status))

    fun log(line: String) = post(mapOf("type" to "log", "line" to line))

    fun error(message: String) = post(mapOf("type" to "error", "message" to message))

    private fun post(map: Map<String, String>) {
        mainHandler.post {
            val s = sink ?: return@post
            runCatching { s.success(map) }
        }
    }
}
