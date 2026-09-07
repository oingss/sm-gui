package com.sm.sm_mobile

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

/// 默认网络监控：sing-box auto_detect_interface 依赖它感知默认出口变化。
/// 简化自 SFA 的 DefaultNetworkMonitor（无跨进程依赖）。
object DefaultNetworkMonitor {
    private var callback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    var defaultNetwork: Network? = null
        private set

    @Synchronized
    fun setListener(listener: InterfaceUpdateListener?) {
        val cm = SmApplication.connectivity
        callback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        callback = null
        if (listener == null) return
        defaultNetwork = cm.activeNetwork
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                update(network, listener)
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                update(network, listener)
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                update(network, listener)
            }

            override fun onLost(network: Network) {
                if (network == defaultNetwork) {
                    defaultNetwork = cm.activeNetwork
                    emit(listener)
                }
            }
        }
        callback = cb
        runCatching {
            cm.registerNetworkCallback(NetworkRequest.Builder().build(), cb)
        }
        emit(listener)
    }

    private fun update(network: Network, listener: InterfaceUpdateListener) {
        defaultNetwork = network
        emit(listener)
    }

    private fun emit(listener: InterfaceUpdateListener) {
        val network = defaultNetwork ?: return
        val lp = SmApplication.connectivity.getLinkProperties(network) ?: return
        val name = lp.interfaceName ?: return
        val caps = SmApplication.connectivity.getNetworkCapabilities(network)
        val expensive = caps != null &&
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        val index = runCatching { NetworkInterface.getByName(name)?.index ?: 0 }
            .getOrDefault(0)
        listener.updateDefaultInterface(name, index, expensive, false)
    }
}
