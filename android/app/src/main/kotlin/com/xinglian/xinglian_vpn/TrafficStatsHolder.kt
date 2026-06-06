package com.kele.kele_vpn

/** StarVpnService 后台轮询写入，MainActivity 只读 */
object TrafficStatsHolder {
    @Volatile
    var upBps: Long = 0L
        private set

    @Volatile
    var downBps: Long = 0L
        private set

    fun update(up: Long, down: Long) {
        upBps = up
        downBps = down
    }

    fun reset() {
        upBps = 0L
        downBps = 0L
    }
}
