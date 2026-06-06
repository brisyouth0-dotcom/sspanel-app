package com.kele.kele_vpn

import android.content.Context
import java.io.File

/** 跨组件读取 VPN 是否已建立（文件标记，避免多进程/静态变量不一致） */
object VpnState {
    private const val FLAG = "vpn_active.flag"
    private const val ERROR = "vpn_last_error.txt"

    fun setActive(context: Context, active: Boolean) {
        val file = File(context.applicationContext.filesDir, FLAG)
        if (active) {
            file.writeText("1")
            clearError(context)
        } else if (file.exists()) {
            file.delete()
        }
    }

    fun isActive(context: Context): Boolean {
        return File(context.applicationContext.filesDir, FLAG).exists()
    }

    fun setError(context: Context, message: String?) {
        val file = File(context.applicationContext.filesDir, ERROR)
        if (message.isNullOrBlank()) {
            if (file.exists()) file.delete()
        } else {
            file.writeText(message)
        }
    }

    fun lastError(context: Context): String? {
        val file = File(context.applicationContext.filesDir, ERROR)
        if (!file.exists()) return null
        return file.readText().trim().ifEmpty { null }
    }

    fun clearError(context: Context) {
        val file = File(context.applicationContext.filesDir, ERROR)
        if (file.exists()) file.delete()
    }
}
