package com.kele.kele_vpn

import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 强杀进程 / 鸿蒙清理后台后，VPN 文件标记与系统 VPN 状态可能不一致。
 * 应用重新打开时对齐状态并关闭残留隧道。
 */
object VpnReconciler {
    private const val TAG = "VpnReconciler"

    fun reconcile(context: Context) {
        val app = context.applicationContext
        val flagActive = VpnState.isActive(app)
        val serviceAlive = StarVpnService.isServiceAlive

        // 服务在跑、标记未写入 = 正在建隧道，勿误杀
        if (serviceAlive && !flagActive) {
            return
        }

        // 强杀后文件标记残留，服务已不在
        if (flagActive && !serviceAlive) {
            Log.w(TAG, "reconcile: stale flag (service gone)")
            VpnState.setActive(app, false)
            requestStop(app)
            return
        }

        // 标记已写入且服务在跑 — 隧道正常
    }

    fun requestStop(context: Context) {
        try {
            val intent = Intent(context, StarVpnService::class.java).apply {
                action = StarVpnService.ACTION_STOP
            }
            context.startService(intent)
        } catch (e: Exception) {
            Log.w(TAG, "requestStop failed: ${e.message}")
        }
    }
}
