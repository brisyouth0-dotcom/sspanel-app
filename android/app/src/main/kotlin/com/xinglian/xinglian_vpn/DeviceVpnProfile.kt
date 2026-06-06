package com.kele.kele_vpn

import android.os.Build

/**
 * 按机型调整 VPN 参数。
 * - 鸿蒙系：虚拟 DNS、关 IPv6、拦截 QUIC/DoT、系统 HTTP 代理（浏览器）
 * - 国产 OEM：同鸿蒙系 DNS 策略
 * - 原生 Android（Google Pixel 等）：hev UDP-in-TCP（与 mihomo 最稳）、放行 QUIC（TikTok）
 */
object DeviceVpnProfile {
    /** hev mapdns 虚拟 DNS */
    const val VIRTUAL_DNS = "172.19.0.2"

    /**
     * Android VPN 下发的 DNS。
     * builtin TUN 无 mapdns，须用 TUN 网关；hev 路径用 [VIRTUAL_DNS] 交给 mapdns。
     */
    val tunnelDnsServer: String
        get() = if (useMihomoBuiltinTun) "172.19.0.1" else VIRTUAL_DNS

    enum class Kind {
        /** 华为 / 鸿蒙 / WIKO 等 */
        HARMONY,
        /** 小米 / OPPO / vivo 等国产 ROM，DNS 易劫持 */
        OEM_CHINA,
        /** Google Pixel、三星国际版、Motorola 等原生或近原生 ROM */
        STOCK,
    }

    val kind: Kind
        get() = when {
            isHarmonyFamily() -> Kind.HARMONY
            isOemChinaFamily() -> Kind.OEM_CHINA
            else -> Kind.STOCK
        }

    val mtu: Int
        get() = when (kind) {
            Kind.STOCK -> 1280
            Kind.HARMONY, Kind.OEM_CHINA -> 1200
        }

    /** IPv6 TUN 在部分机型上会导致无流量 */
    val useIpv6Tunnel: Boolean
        get() = false

    /**
     * mihomo 子进程 + file-descriptor TUN 在 Pixel 上数据面不通（延迟测试可过但 0 流量）。
     * 全机型统一 hev-socks5-tunnel → mihomo mixed-port。
     */
    val useMihomoBuiltinTun: Boolean
        get() = false

    /** hev SOCKS5 UDP 中继：全 Android 用 udp（与 mihomo mixed-port 最匹配） */
    val hevUdpMode: String
        get() = "udp"

    /** TUN 读包模式：非阻塞在部分 Pixel 上会导致 0 流量 */
    val tunBlocking: Boolean
        get() = kind == Kind.STOCK

    /** TikTok 等依赖 QUIC(UDP/443)，原生 Android 上不要拦截 */
    val blockQuic: Boolean
        get() = kind != Kind.STOCK

    /** 私人 DNS(DoT) 绕过 mapdns；Pixel 也建议拦截（Android 私人 DNS 很常见） */
    val blockDoT: Boolean
        get() = true

    /** 浏览器 DoH 不走 mapdns，鸿蒙/国产 ROM 用系统 HTTP 代理兜底 */
    val useHttpProxy: Boolean
        get() = kind != Kind.STOCK

    fun toChannelMap(): Map<String, Any> = mapOf(
        "kind" to kind.name,
        "hevUdp" to hevUdpMode,
        "blockQuic" to blockQuic,
        "blockDoT" to blockDoT,
        "useMihomoBuiltinTun" to useMihomoBuiltinTun,
        "tunBlocking" to tunBlocking,
    )

    fun logTag(): String =
        "${Build.MANUFACTURER}/${Build.MODEL} kind=$kind mtu=$mtu " +
            "builtinTun=$useMihomoBuiltinTun hevUdp=$hevUdpMode quicBlock=$blockQuic"

    private fun isHarmonyFamily(): Boolean {
        val m = Build.MANUFACTURER.lowercase()
        val b = Build.BRAND.lowercase()
        val harmonyLike = setOf(
            "huawei", "honor", "wiko", "hinova", "nzone", "tianyi", "liantong",
        )
        if (m in harmonyLike || b in harmonyLike) return true
        val display = "${Build.DISPLAY} ${Build.FINGERPRINT} ${Build.PRODUCT}".lowercase()
        return display.contains("harmony") || isHarmonyOs()
    }

    private fun isOemChinaFamily(): Boolean {
        val m = Build.MANUFACTURER.lowercase()
        val b = Build.BRAND.lowercase()
        val oemChina = setOf(
            "xiaomi", "redmi", "poco", "blackshark",
            "oppo", "realme", "oneplus",
            "vivo", "iqoo",
            "meizu", "zte", "nubia", "coolpad", "leeco", "smartisan",
            "gionee", "lenovo",
        )
        if (m in oemChina || b in oemChina) return true
        val product = "${Build.PRODUCT} ${Build.FINGERPRINT}".lowercase()
        return product.contains("miui") ||
            product.contains("hyperos") ||
            product.contains("coloros") ||
            product.contains("funtouch") ||
            product.contains("originos")
    }

    private fun isHarmonyOs(): Boolean {
        return try {
            Class.forName("com.huawei.system.BuildEx")
                .getMethod("getOsBrand")
                .invoke(null)
                ?.toString()
                ?.equals("harmony", ignoreCase = true) == true
        } catch (_: Exception) {
            false
        }
    }
}
