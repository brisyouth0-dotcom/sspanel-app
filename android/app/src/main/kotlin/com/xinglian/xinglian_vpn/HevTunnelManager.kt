package com.kele.kele_vpn

import android.content.Context
import android.util.Log
import hev.sockstun.TProxyService
import java.io.File

/** TUN 流量经 SOCKS5 转发到本机 mihomo mixed-port */
object HevTunnelManager {
    private const val TAG = "HevTunnelManager"

    @Volatile
    var running: Boolean = false
        private set

    fun start(
        context: Context,
        tunFd: Int,
        socksPort: Int = 7890,
        mtu: Int = 1280,
        useIpv6: Boolean = true,
        udpMode: String? = null,
    ): Boolean {
        stop()
        return try {
            val ipv6Line = if (useIpv6) "\n  ipv6: fd00::1" else ""
            val udp = udpMode ?: DeviceVpnProfile.hevUdpMode
            val config = File(context.cacheDir, "hev-tunnel.yml")
            config.writeText(
                """
                misc:
                  log-level: warn
                  connect-timeout: 15000
                  tcp-read-write-timeout: 300000
                  udp-read-write-timeout: 120000
                tunnel:
                  mtu: $mtu$ipv6Line
                socks5:
                  port: $socksPort
                  address: 127.0.0.1
                  udp: $udp
                mapdns:
                  address: ${DeviceVpnProfile.VIRTUAL_DNS}
                  port: 53
                  network: 198.18.0.0
                  netmask: 255.255.0.0
                  cache-size: 10000
                """.trimIndent()
            )
            Log.i(TAG, "starting hev tunFd=$tunFd mtu=$mtu udp=$udp")
            TProxyService.TProxyStartService(config.absolutePath, tunFd)
            running = true
            true
        } catch (e: Throwable) {
            Log.e(TAG, "start failed", e)
            running = false
            false
        }
    }

    fun stop() {
        try {
            if (running) {
                TProxyService.TProxyStopService()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "stop: ${e.message}")
        } finally {
            running = false
        }
    }
}
