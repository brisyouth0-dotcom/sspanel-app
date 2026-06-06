package com.kele.kele_vpn

import java.net.InetSocketAddress
import java.net.Socket

/** 跨进程检测主进程 mihomo mixed-port 是否就绪 */
object MihomoReachability {
    private const val SOCKS_PORT = 7890
    private const val CONTROLLER_PORT = MihomoController.PORT

    fun isSocksReady(): Boolean = isPortOpen(SOCKS_PORT)

    fun isControllerReady(): Boolean = isPortOpen(CONTROLLER_PORT)

    fun waitForSocks(maxMs: Int = 8000): Boolean {
        return waitForPort(SOCKS_PORT, maxMs)
    }

    fun waitForController(maxMs: Int = 8000): Boolean {
        return waitForPort(CONTROLLER_PORT, maxMs)
    }

    private fun waitForPort(port: Int, maxMs: Int): Boolean {
        val deadline = System.currentTimeMillis() + maxMs
        while (System.currentTimeMillis() < deadline) {
            if (isPortOpen(port)) return true
            Thread.sleep(250)
        }
        return isPortOpen(port)
    }

    private fun isPortOpen(port: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 600)
                true
            }
        } catch (_: Exception) {
            false
        }
    }
}
