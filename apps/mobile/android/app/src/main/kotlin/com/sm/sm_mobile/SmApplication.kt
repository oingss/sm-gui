package com.sm.sm_mobile

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.SetupOptions
import java.io.File

/// 全局上下文 + libbox 初始化（对齐 SFA 的 Application）。
class SmApplication : Application() {
    companion object {
        @JvmStatic
        lateinit var appContext: Context
            private set

        val connectivity: ConnectivityManager
            get() = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val packageManager: PackageManager
            get() = appContext.packageManager
    }

    override fun onCreate() {
        super.onCreate()
        appContext = this
        // libbox 基础工作目录（sing-box 内部工作文件）
        val workingDir = File(cacheDir, "libbox").also { it.mkdirs() }
        val tempDir = File(cacheDir, "libbox-temp").also { it.mkdirs() }
        runCatching {
            val options = SetupOptions()
            options.basePath = cacheDir.path
            options.workingPath = workingDir.path
            options.tempPath = tempDir.path
            Libbox.setup(options)
        }
    }
}
