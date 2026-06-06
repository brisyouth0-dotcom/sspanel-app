package com.kele.kele_vpn

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private var vpnPermissionResult: MethodChannel.Result? = null
    private val vpnWorker = Executors.newSingleThreadExecutor()

    override fun onResume() {
        super.onResume()
        VpnReconciler.reconcile(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VpnReconciler.reconcile(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "reconcile" -> {
                    VpnReconciler.reconcile(this)
                    result.success(isVpnTunnelReady(this))
                }
                "prepare" -> handleVpnPrepare(result)
                "start" -> {
                    vpnWorker.execute {
                        val error = startVpnBlocking(call.arguments)
                        runOnUiThread {
                            if (error != null) {
                                result.error("VPN_START", error, null)
                            } else {
                                result.success(null)
                            }
                        }
                    }
                }
                "stop" -> {
                    MihomoTrafficPoller.stop()
                    val svc = Intent(this, StarVpnService::class.java).apply {
                        action = StarVpnService.ACTION_STOP
                    }
                    startService(svc)
                    result.success(null)
                }
                "isActive" -> result.success(isVpnTunnelReady(this))
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIHOMO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "resolveBinary" -> result.success(MihomoManager.resolveBinary(this))
                "lastStartError" -> result.success(
                    MihomoManager.lastStartError ?: VpnState.lastError(this),
                )
                "start" -> {
                    val path = (call.arguments as? Map<*, *>)?.get("configPath")?.toString()
                    if (path.isNullOrEmpty()) {
                        result.success(false)
                    } else if (VpnState.isActive(this)) {
                        // VPN 已连接时由 StarVpnService 管理 mihomo，勿重复启动
                        result.success(MihomoReachability.isSocksReady())
                    } else {
                        vpnWorker.execute {
                            val ok = MihomoManager.start(this@MainActivity, path)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                }
                "stop" -> {
                    if (!VpnState.isActive(this)) {
                        vpnWorker.execute {
                            MihomoManager.stop()
                            runOnUiThread { result.success(null) }
                        }
                    } else {
                        result.success(null)
                    }
                }
                "getDeviceVpnProfile" -> result.success(DeviceVpnProfile.toChannelMap())
                "applyNode" -> {
                    val label = (call.arguments as? Map<*, *>)?.get("proxyName")?.toString()
                    if (label.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        vpnWorker.execute {
                            val ok = MihomoRouting.applyWithProtect(label)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                }
                "pollTraffic" -> {
                    result.success(
                        mapOf(
                            "up" to TrafficStatsHolder.upBps,
                            "down" to TrafficStatsHolder.downBps,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DISGUISE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> result.success(currentDisguise())
                "apply" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("id")?.toString() ?: "original"
                    result.success(applyDisguise(id))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleVpnPrepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        if (vpnPermissionResult != null) {
            result.error("VPN_BUSY", "正在等待 VPN 授权，请在系统弹窗中确认", null)
            return
        }
        vpnPermissionResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, VPN_PREPARE_CODE)
        } catch (e: Exception) {
            Log.e(TAG, "vpn prepare launch failed", e)
            vpnPermissionResult = null
            result.error("VPN_PREPARE", "无法打开 VPN 授权：${e.message}", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PREPARE_CODE) {
            val pending = vpnPermissionResult
            vpnPermissionResult = null
            pending?.success(resultCode == Activity.RESULT_OK)
        }
    }

    /** 在后台线程启动 VPN 服务（mihomo+TUN+hev 均在 StarVpnService 同进程完成） */
    private fun startVpnBlocking(arguments: Any?): String? {
        val args = arguments as? Map<*, *>
        val node = args?.get("nodeName")?.toString() ?: "—"
        val proxyLabel = args?.get("proxyName")?.toString() ?: node
        val configPath = args?.get("configPath")?.toString()
        VpnState.clearError(this)
        Log.i(TAG, "vpn start begin node=$node proxy=$proxyLabel")
        val svc = Intent(this, StarVpnService::class.java).apply {
            action = StarVpnService.ACTION_START
            putExtra(StarVpnService.EXTRA_NODE, node)
            putExtra(StarVpnService.EXTRA_PROXY_LABEL, proxyLabel)
            if (!configPath.isNullOrEmpty()) {
                putExtra(StarVpnService.EXTRA_CONFIG_PATH, configPath)
            }
        }
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(svc)
            } else {
                startService(svc)
            }
            Log.i(TAG, "vpn start: StarVpnService requested")
            null
        } catch (e: Exception) {
            Log.e(TAG, "startForegroundService failed", e)
            val detail = "VPN 服务启动失败：${e.message}"
            VpnState.setError(this, detail)
            detail
        }
    }

    override fun onDestroy() {
        vpnWorker.shutdownNow()
        super.onDestroy()
    }

    /**
     * 隧道是否就绪。仅读 [VpnState] 标记（在 mihomo+TUN+hev 全部成功后写入）。
     * 不可再探测 127.0.0.1:7890：TUN 起来后本进程探测 mixed-port 在 Pixel 等机型会失败。
     */
    private fun isVpnTunnelReady(context: android.content.Context): Boolean {
        return VpnState.isActive(context)
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val VPN_CHANNEL = "com.kele.kele_vpn/vpn"
        private const val MIHOMO_CHANNEL = "com.panlink.vpn/mihomo"
        private const val DISGUISE_CHANNEL = "com.kele.kele_vpn/app_disguise"
        private const val VPN_PREPARE_CODE = 0x7E01
    }

    private fun currentDisguise(): String {
        disguiseAliases.forEach { alias ->
            if (alias.id == "original") return@forEach
            val state = packageManager.getComponentEnabledSetting(component(alias.component))
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return alias.id
            }
        }
        return "original"
    }

    private fun applyDisguise(id: String): Boolean {
        val activeComponent = if (id == "original") {
            ComponentName(this, MainActivity::class.java)
        } else {
            val target = disguiseAliases.firstOrNull { it.id == id } ?: return false
            component(target.component)
        }

        if (id == "original") {
            packageManager.setComponentEnabledSetting(
                ComponentName(this, MainActivity::class.java),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            disguiseAliases.forEach { alias ->
                packageManager.setComponentEnabledSetting(
                    component(alias.component),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            refreshLauncherIcon(activeComponent)
            return true
        }
        val target = disguiseAliases.firstOrNull { it.id == id } ?: return false
        packageManager.setComponentEnabledSetting(
            ComponentName(this, MainActivity::class.java),
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        disguiseAliases.forEach { alias ->
            packageManager.setComponentEnabledSetting(
                component(alias.component),
                if (alias == target) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                },
                PackageManager.DONT_KILL_APP,
            )
        }
        refreshLauncherIcon(activeComponent)
        return true
    }

    private fun refreshLauncherIcon(activeComponent: ComponentName) {
        val manufacturer = Build.MANUFACTURER.orEmpty()
        if (manufacturer.equals("HUAWEI", ignoreCase = true) ||
            manufacturer.equals("HONOR", ignoreCase = true)
        ) {
            sendBroadcast(
                Intent("com.huawei.android.launcher.action.CHANGE_APPLICATION_ICON").apply {
                    putExtra("packageName", packageName)
                    putExtra("className", activeComponent.className)
                },
            )
        }
        sendBroadcast(
            Intent(Intent.ACTION_PACKAGE_CHANGED).apply {
                data = Uri.fromParts("package", packageName, null)
                putExtra(Intent.EXTRA_CHANGED_COMPONENT_NAME_LIST, arrayOf(activeComponent.className))
            },
        )
    }

    private fun component(name: String): ComponentName {
        return ComponentName(packageName, "$packageName.$name")
    }

    private data class DisguiseAlias(val id: String, val component: String)

    private val disguiseAliases = listOf(
        DisguiseAlias("original", "AliasOriginal"),
        DisguiseAlias("calculator", "AliasCalculator"),
        DisguiseAlias("weather", "AliasWeather"),
        DisguiseAlias("notes", "AliasNotes"),
        DisguiseAlias("settings", "AliasSettings"),
        DisguiseAlias("album", "AliasAlbum"),
        DisguiseAlias("gallery", "AliasGallery"),
        DisguiseAlias("phone", "AliasPhone"),
    )
}
