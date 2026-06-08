package com.kele.kele_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 同进程 VPN：mihomo + TUN + hev；hev 经 127.0.0.1 连 mixed-port（本 App 已排除在 TUN 外）。
 */
class StarVpnService : VpnService() {

    private var tunInterface: ParcelFileDescriptor? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val trafficExecutor = Executors.newSingleThreadScheduledExecutor()
    private var trafficTask: ScheduledFuture<*>? = null
    private var watchdogTask: ScheduledFuture<*>? = null
    private var lastProxyLabel: String? = null
    private var hevUdpAttempt = 0
    private val starting = AtomicBoolean(false)

    companion object {
        private const val TAG = "StarVpnService"
        const val ACTION_START = "com.kele.kele_vpn.action.START"
        const val ACTION_STOP = "com.kele.kele_vpn.action.STOP"
        const val EXTRA_NODE = "node_name"
        const val EXTRA_PROXY_LABEL = "proxy_label"
        const val EXTRA_CONFIG_PATH = "config_path"
        private const val CHANNEL_ID = "xinglian_vpn_channel"
        private const val NOTIFY_ID = 7101
        private const val MIHOMO_SOCKS_PORT = 7890

        @Volatile
        var isServiceAlive: Boolean = false
            private set

        @Volatile
        private var instance: StarVpnService? = null

        /** 保护套接字不走 TUN；必须在 [Socket.connect] 之后调用 */
        fun protectSocket(socket: Socket): Boolean {
            val svc = instance ?: return true
            if (!socket.isConnected) return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return true
            return try {
                val pfd = ParcelFileDescriptor.fromSocket(socket)
                try {
                    svc.protect(pfd.fd)
                } finally {
                    pfd.close()
                }
            } catch (e: Exception) {
                val fd = socketFdInt(socket)
                if (fd != null) {
                    svc.protect(fd)
                } else {
                    Log.w(TAG, "protectSocket: ${e.message}")
                    false
                }
            }
        }

        private fun socketFdInt(socket: Socket): Int? {
            return try {
                val implField = Socket::class.java.getDeclaredField("impl")
                implField.isAccessible = true
                val impl = implField.get(socket) ?: return null
                val fdField = impl.javaClass.superclass?.getDeclaredField("fd")
                    ?: impl.javaClass.getDeclaredField("fd")
                fdField.isAccessible = true
                when (val fdObj = fdField.get(impl)) {
                    is java.io.FileDescriptor -> {
                        val desc = java.io.FileDescriptor::class.java
                            .getDeclaredField("descriptor")
                        desc.isAccessible = true
                        desc.getInt(fdObj)
                    }
                    is Int -> fdObj
                    else -> null
                }
            } catch (_: Exception) {
                null
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        isServiceAlive = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY 被系统拉起时 intent 为空，勿建立残缺 VPN（鸿蒙会卡在「连接中」）
        if (intent == null) {
            Log.w(TAG, "onStartCommand null intent — stale restart, tearing down")
            worker.execute {
                teardown()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            return START_NOT_STICKY
        }
        when (intent.action) {
            ACTION_STOP -> {
                worker.execute {
                    teardown()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
                return START_NOT_STICKY
            }
            else -> {
                val node = intent?.getStringExtra(EXTRA_NODE) ?: "—"
                val proxyLabel = intent?.getStringExtra(EXTRA_PROXY_LABEL)
                val configPath = intent?.getStringExtra(EXTRA_CONFIG_PATH)
                val sessionName = getString(R.string.vpn_session_name)
                try {
                    showForegroundNotification(sessionName, node)
                } catch (e: Throwable) {
                    Log.e(TAG, "startForeground failed", e)
                    fail("VPN 服务启动失败：${e.message}")
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (starting.compareAndSet(false, true)) {
                    worker.execute {
                        try {
                            startTunnel(sessionName, configPath, proxyLabel)
                        } catch (e: Throwable) {
                            Log.e(TAG, "vpn start crashed", e)
                            fail("VPN 启动异常：${e.message}")
                            teardown()
                            stopForeground(STOP_FOREGROUND_REMOVE)
                            stopSelf()
                        } finally {
                            starting.set(false)
                        }
                    }
                }
            }
        }
        // 进程被杀后不要自动重启 VPN，避免系统设置里一直显示「连接中」
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved — stopping VPN")
        teardown()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun showForegroundNotification(sessionName: String, node: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.vpn_notification_channel),
                NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(ch)
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(sessionName)
            .setContentText(getString(R.string.vpn_notification_text, node))
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFY_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFY_ID, notif)
        }
    }

    private fun establishTunnel(sessionName: String) {
        try {
            tunInterface?.close()
        } catch (_: Exception) {
        }
        val profile = DeviceVpnProfile
        Log.i(
            TAG,
            "establishTunnel ${profile.logTag()} mtu=${profile.mtu} " +
                "dns=${profile.tunnelDnsServer} ipv6=${profile.useIpv6Tunnel} " +
                "hevUdp=${profile.hevUdpMode}",
        )
        val builder = Builder()
            .setSession(sessionName)
            .setBlocking(profile.tunBlocking)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(profile.tunnelDnsServer)
            .setMtu(profile.mtu)
        if (profile.useIpv6Tunnel) {
            builder
                .addAddress("fd00::1", 128)
                .addRoute("::", 0)
                .addDnsServer("2001:4860:4860::8888")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
            if (profile.useHttpProxy) {
                // 鸿蒙/国产 ROM 浏览器常走 DoH，用系统 HTTP 代理强制经 mihomo
                builder.setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        DeviceVpnProfile.TUN_GATEWAY,
                        MIHOMO_SOCKS_PORT,
                    ),
                )
                Log.i(
                    TAG,
                    "VPN HTTP proxy → ${DeviceVpnProfile.TUN_GATEWAY}:$MIHOMO_SOCKS_PORT",
                )
            }
        }
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            Log.w(TAG, "addDisallowedApplication: ${e.message}")
        }
        tunInterface = builder.establish()
    }

    private fun startTunnel(sessionName: String, configPath: String?, proxyLabel: String?) {
        teardown()
        VpnState.clearError(this)
        val profile = DeviceVpnProfile
        val effectiveConfig = if (!configPath.isNullOrEmpty()) {
            ConfigYamlPinner.pin(configPath, proxyLabel)
        } else {
            null
        }
        val configPinned = ConfigYamlPinner.lastPinSucceeded

        if (profile.useMihomoBuiltinTun) {
            startBuiltinTunTunnel(sessionName, effectiveConfig, proxyLabel, configPinned)
        } else {
            startHevTunnel(sessionName, effectiveConfig, proxyLabel, configPinned)
        }
    }

    /** Pixel 等原生机：Android TUN fd 直接交给 mihomo gvisor */
    private fun startBuiltinTunTunnel(
        sessionName: String,
        effectiveConfig: String?,
        proxyLabel: String?,
        configPinned: Boolean,
    ) {
        establishTunnel(sessionName)
        val tun = tunInterface
        if (tun == null) {
            fail("VPN 隧道建立失败，请确认已授予 VPN 权限")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (effectiveConfig.isNullOrEmpty()) {
            fail("缺少 mihomo 配置")
            teardown()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        Log.i(TAG, "starting mihomo builtin TUN…")
        if (!MihomoManager.start(this, effectiveConfig, tun.fd)) {
            val detail = MihomoManager.lastStartError ?: "mihomo 启动失败"
            Log.e(TAG, detail)
            fail(detail)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (!MihomoReachability.waitForSocks(maxMs = 8000)) {
            MihomoManager.stop()
            fail(MihomoManager.lastStartError ?: "mihomo 端口未就绪")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        Log.i(TAG, "mihomo ready on 127.0.0.1:$MIHOMO_SOCKS_PORT")
        applyProxyRouting(proxyLabel, afterTunnel = true, configPinned = configPinned)
        if (MihomoRouting.measureProxyDelay(proxyLabel, protect = true, timeoutMs = 6000) != null) {
            finalizeVpnReady("TUN → mihomo (builtin)", proxyLabel)
            return
        }
        Log.w(TAG, "builtin TUN delay test failed, falling back to hev…")
        if (fallbackBuiltinToHev(proxyLabel)) {
            finalizeVpnReady("TUN → hev (fallback)", proxyLabel)
            return
        }
        fail("节点不可达（延迟测试失败），请更换延迟较低的节点后重试")
        teardown()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun finalizeVpnReady(pathLabel: String, proxyLabel: String?) {
        Log.i(TAG, "VPN ready: $pathLabel")
        lastProxyLabel = proxyLabel
        hevUdpAttempt = 0
        VpnState.setActive(this, true)
        startTrafficPolling()
        startZeroTrafficWatchdog()
    }

    /** builtin TUN 数据面异常时，保留 TUN fd，改走 hev → mihomo */
    private fun fallbackBuiltinToHev(proxyLabel: String?): Boolean {
        MihomoManager.stop()
        val configPath = ConfigYamlPinner.lastPinnedPath
        if (configPath.isNullOrEmpty()) {
            Log.e(TAG, "hev fallback: no pinned config")
            return false
        }
        if (!MihomoManager.start(this, configPath)) {
            Log.e(TAG, "hev fallback: mihomo start failed")
            return false
        }
        if (!MihomoReachability.waitForSocks(maxMs = 12000)) {
            MihomoManager.stop()
            Log.e(TAG, "hev fallback: socks not ready")
            return false
        }
        MihomoRouting.applyAfterTunnel(proxyLabel)
        val tun = tunInterface ?: return false
        if (!HevTunnelManager.start(
                this,
                tun.fd,
                MIHOMO_SOCKS_PORT,
                mtu = DeviceVpnProfile.mtu,
                useIpv6 = DeviceVpnProfile.useIpv6Tunnel,
            )
        ) {
            Log.e(TAG, "hev fallback: hev start failed")
            return false
        }
        return MihomoRouting.measureProxyDelay(proxyLabel, protect = true) != null
    }

    /** 鸿蒙/国产 ROM：mihomo mixed-port + hev-socks5-tunnel */
    private fun startHevTunnel(
        sessionName: String,
        effectiveConfig: String?,
        proxyLabel: String?,
        configPinned: Boolean,
    ) {
        if (!effectiveConfig.isNullOrEmpty()) {
            Log.i(TAG, "starting mihomo…")
            if (!MihomoManager.start(this, effectiveConfig)) {
                val detail = MihomoManager.lastStartError ?: "mihomo 启动失败"
                Log.e(TAG, detail)
                fail(detail)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }
            if (!MihomoReachability.waitForSocks(maxMs = 8000)) {
                MihomoManager.stop()
                fail(MihomoManager.lastStartError ?: "mihomo 端口未就绪")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }
            Log.i(TAG, "mihomo ready on 127.0.0.1:$MIHOMO_SOCKS_PORT")
            applyProxyRouting(
                proxyLabel,
                afterTunnel = false,
                configPinned = configPinned,
            )
            val preLabel = proxyLabel?.trim().orEmpty()
            if (preLabel.isNotEmpty() && preLabel != "—") {
                val preDelay = MihomoRouting.measureProxyDelay(
                    proxyLabel,
                    protect = false,
                    timeoutMs = 6000,
                )
                if (preDelay != null) {
                    Log.i(TAG, "pre-tunnel delay ok ${preDelay}ms proxy=$preLabel")
                } else {
                    Log.w(TAG, "pre-tunnel delay failed proxy=$preLabel")
                }
            }
        }

        establishTunnel(sessionName)
        val tun = tunInterface
        if (tun == null) {
            fail("VPN 隧道建立失败，请确认已授予 VPN 权限")
            MihomoManager.stop()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        if (!HevTunnelManager.start(
                this,
                tun.fd,
                MIHOMO_SOCKS_PORT,
                mtu = DeviceVpnProfile.mtu,
                useIpv6 = DeviceVpnProfile.useIpv6Tunnel,
            )
        ) {
            fail("TUN 转发启动失败")
            teardown()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        finalizeVpnTunnel(proxyLabel, configPinned)
    }

    /** pin 只改 YAML 顺序；mihomo 会缓存策略组选中项，重连须 API 强制选路 */
    private fun applyProxyRouting(
        proxyLabel: String?,
        afterTunnel: Boolean,
        configPinned: Boolean,
    ): Boolean {
        val raw = proxyLabel?.trim().orEmpty()
        val routedLabel =
            if (raw.isEmpty() || raw == "—") null else proxyLabel
        val ok = if (afterTunnel) {
            MihomoRouting.applyAfterTunnel(routedLabel)
        } else {
            MihomoRouting.applyBeforeTunnel(routedLabel)
        }
        val label = raw.ifEmpty { "auto" }
        when {
            ok && configPinned ->
                Log.i(TAG, "routing ok (pinned) proxy=$label afterTunnel=$afterTunnel")
            ok -> Log.i(TAG, "routing ok proxy=$label afterTunnel=$afterTunnel")
            else ->
                Log.w(
                    TAG,
                    "routing incomplete proxy=$label pinned=$configPinned afterTunnel=$afterTunnel",
                )
        }
        return ok
    }

    /** TUN/hev 就绪：protect 下重新选路后立即标记连接成功（测速在后台进行） */
    private fun finalizeVpnTunnel(proxyLabel: String?, configPinned: Boolean) {
        applyProxyRouting(proxyLabel, afterTunnel = true, configPinned = configPinned)
        val label = proxyLabel?.trim().orEmpty()
        val pathLabel =
            "TUN → hev(${DeviceVpnProfile.hevUdpMode}) → " +
                "${DeviceVpnProfile.MIHOMO_SOCKS_HOST}:$MIHOMO_SOCKS_PORT"
        finalizeVpnReady(pathLabel, proxyLabel)
        if (label.isNotEmpty() && label != "—") {
            trafficExecutor.execute {
                val delay = MihomoRouting.measureProxyDelay(
                    proxyLabel,
                    protect = true,
                    timeoutMs = 8000,
                )
                if (delay != null) {
                    Log.i(TAG, "background delay ok ${delay}ms proxy=$label")
                } else {
                    Log.w(TAG, "background delay failed proxy=$label")
                }
            }
        }
    }

    private fun readHevTrafficBytes(): Long {
        return try {
            val stats = hev.sockstun.TProxyService.TProxyGetStats() ?: return 0L
            if (stats.size < 4) return 0L
            stats[1] + stats[3]
        } catch (_: Exception) {
            0L
        }
    }

    private fun startZeroTrafficWatchdog() {
        watchdogTask?.cancel(true)
        watchdogTask = trafficExecutor.schedule({
            if (!VpnState.isActive(this)) return@schedule
            val up = TrafficStatsHolder.upBps
            val down = TrafficStatsHolder.downBps
            if (up > 0 || down > 0) {
                Log.i(TAG, "watchdog: traffic flowing up=$up down=$down")
                return@schedule
            }
            if (!HevTunnelManager.running) return@schedule
            val hevBytes = readHevTrafficBytes()
            // hev 有流量但 mihomo /traffic 轮询偶发为 0，勿误切 udp→tcp（会破坏 Pixel 浏览器）
            if (hevBytes > 4096L) {
                Log.i(
                    TAG,
                    "watchdog: hev data plane active hevBytes=$hevBytes (mihomo poll idle)",
                )
                return@schedule
            }
            Log.w(TAG, "watchdog: low traffic hevBytes=$hevBytes")
            if (hevBytes <= 64L) {
                VpnState.setError(
                    applicationContext,
                    "隧道已建立但无数据流量，请关闭系统「私人DNS」后重试或更换节点",
                )
            }
        }, 12, TimeUnit.SECONDS)
    }

    private fun startTrafficPolling() {
        stopTrafficPolling()
        trafficTask = trafficExecutor.scheduleAtFixedRate({
            try {
                val sample = MihomoTrafficPoller.pollOnce()
                if (sample != null) {
                    TrafficStatsHolder.update(sample.first, sample.second)
                }
            } catch (_: Exception) {
            }
        }, 300, 500, TimeUnit.MILLISECONDS)
    }

    private fun stopTrafficPolling() {
        watchdogTask?.cancel(true)
        watchdogTask = null
        trafficTask?.cancel(true)
        trafficTask = null
        TrafficStatsHolder.reset()
    }

    private fun fail(message: String) {
        VpnState.setError(applicationContext, message)
        VpnState.setActive(this, false)
    }

    private fun teardown() {
        stopTrafficPolling()
        VpnState.setActive(this, false)
        HevTunnelManager.stop()
        MihomoManager.stop()
        try {
            tunInterface?.close()
        } catch (_: Exception) {
        }
        tunInterface = null
    }

    override fun onDestroy() {
        teardown()
        instance = null
        isServiceAlive = false
        worker.shutdownNow()
        trafficExecutor.shutdownNow()
        super.onDestroy()
    }
}
