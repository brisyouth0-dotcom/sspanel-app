package com.kele.kele_vpn

import android.os.Build

/**
 * 按机型调整 VPN 参数。
 * - 鸿蒙/华为：纯 TUN+mapdns（172.19.0.2）、hev TCP 中继、放行 QUIC（Google/YouTube）
 * - 国产 OEM（小米/OPPO 等）：HTTP 代理兜底、拦截 QUIC/DoT
 * - 原生 Android（Pixel 等）：纯 TUN+mapdns（198.18.0.2）、hev UDP、放行 QUIC
 */
object DeviceVpnProfile {
    /** Android VPN TUN 网关（系统 HTTP 代理指向 mixed-port，走 TUN 数据面） */
    const val TUN_GATEWAY = "172.19.0.1"

    /**
     * hev / 本进程连 mihomo mixed-port。
     * 本 App 已 [VpnService.Builder.addDisallowedApplication]，须走 127.0.0.1 而非 TUN 网关。
     */
    const val MIHOMO_SOCKS_HOST = "127.0.0.1"

    /**
     * hev mapdns 虚拟 DNS。
     * 鸿蒙对 198.18.0.0/15 兼容差，用 TUN 同网段 172.19.0.2；Pixel 等用 sockstun 惯例 198.18.0.2。
     */
    val virtualDns: String
        get() = if (kind == Kind.HARMONY) "172.19.0.2" else "198.18.0.2"

    /**
     * Android VPN 下发的 DNS。
     * builtin TUN 无 mapdns，须用 TUN 网关；hev 路径用 [virtualDns] 交给 mapdns。
     */
    val tunnelDnsServer: String
        get() = if (useMihomoBuiltinTun) "172.19.0.1" else virtualDns

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

    /** hev SOCKS5 UDP 中继：鸿蒙 UDP 不稳定改 tcp；其余机型 udp */
    val hevUdpMode: String
        get() = if (kind == Kind.HARMONY) "tcp" else "udp"

    /** TUN 阻塞读：Pixel / 鸿蒙 上非阻塞易导致 0 流量 */
    val tunBlocking: Boolean
        get() = kind == Kind.STOCK || kind == Kind.HARMONY

    /** 仅国产 OEM 拦截 QUIC；鸿蒙/Pixel 访问 Google/YouTube 需放行 UDP/443 */
    val blockQuic: Boolean
        get() = kind == Kind.OEM_CHINA

    /** 私人 DNS(DoT) 绕过 mapdns；Pixel 也建议拦截（Android 私人 DNS 很常见） */
    val blockDoT: Boolean
        get() = true

    /**
     * 系统 HTTP 代理 → TUN 网关 mixed-port。
     * 仅小米/OPPO 等 OEM 启用；鸿蒙/Pixel 走纯 TUN+mapdns（HTTP 代理在鸿蒙上易导致 Google 离线）。
     */
    val useHttpProxy: Boolean
        get() = kind == Kind.OEM_CHINA

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
