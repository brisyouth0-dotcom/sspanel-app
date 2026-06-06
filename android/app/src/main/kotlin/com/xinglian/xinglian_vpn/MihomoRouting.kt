package com.kele.kele_vpn

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * 在 TUN 建立前通过 mihomo REST API 设置全局模式并选中节点。
 * GLOBAL 组常只含子策略组（如「节点选择」），须链式选中。
 */
object MihomoRouting {
    private const val TAG = "MihomoRouting"

    private val selectorGroups = listOf(
        "🚀 节点选择",
        "节点选择",
        "Proxy",
        "PROXY",
        "灵猫加速器",
    )

    /** TUN 已建立后选路（须 protect，避免 API 套接字被 TUN 吞掉） */
    fun applyAfterTunnel(nodeLabel: String?): Boolean = applyBeforeTunnel(nodeLabel, protect = true)

    fun applyBeforeTunnel(nodeLabel: String?): Boolean =
        applyBeforeTunnel(nodeLabel, protect = false)

    private fun applyBeforeTunnel(nodeLabel: String?, protect: Boolean): Boolean {
        val label = nodeLabel?.trim().orEmpty()
        if (label.isEmpty() || label == "—") {
            Log.w(TAG, "no node label, skip routing")
            return false
        }
        if (!MihomoReachability.waitForController(maxMs = 15000)) {
            Log.w(TAG, "controller not ready, rely on config pin")
            return false
        }
        return try {
            for (attempt in 1..5) {
                if (applyOnce(label, protect = protect)) return true
                Thread.sleep(400)
            }
            Log.w(TAG, "routing API failed after retries, rely on config pin")
            false
        } catch (e: Exception) {
            Log.e(TAG, "applyBeforeTunnel failed", e)
            false
        }
    }

    private fun applyOnce(label: String, protect: Boolean): Boolean {
        if (!patchMode("global", protect)) {
            Log.w(TAG, "set global mode failed")
        }
        val proxies = fetchProxies(protect) ?: run {
            Log.w(TAG, "fetch proxies failed")
            return false
        }
        val resolved = resolveProxyName(label, proxies) ?: run {
            Log.w(TAG, "no proxy match for: $label")
            return false
        }
        val ok = applyChain(proxies, resolved, protect)
        if (ok) {
            closeConnections(protect)
            Log.i(TAG, "routing chain ok proxy=$resolved")
        } else {
            Log.w(TAG, "routing chain failed proxy=$resolved")
        }
        return ok
    }

    /** TUN 已建立后切换节点（需 protect 套接字） */
    fun applyWithProtect(nodeLabel: String): Boolean {
        val label = nodeLabel.trim()
        if (label.isEmpty() || label == "—") return false
        return try {
            applyOnce(label, protect = true)
        } catch (e: Exception) {
            Log.w(TAG, "applyWithProtect: ${e.message}")
            false
        }
    }

    /**
     * 1. 在含该节点的所有 Selector 里选中叶子
     * 2. GLOBAL 能直选叶子则直选；否则 GLOBAL → 子策略组（已选中叶子）
     */
    private fun applyChain(
        proxies: JSONObject,
        resolved: String,
        protect: Boolean,
    ): Boolean {
        val selectors = mutableListOf<String>()
        for (key in proxies.keys()) {
            val item = proxies.optJSONObject(key) ?: continue
            if (item.optString("type") == "Selector") {
                selectors.add(key)
            }
        }
        for (group in selectors) {
            if (group == "GLOBAL") continue
            if (groupContains(proxies, group, resolved)) {
                val ok = selectProxy(group, resolved, protect)
                Log.i(TAG, "select $resolved in $group -> $ok")
            }
        }
        if (groupContains(proxies, "GLOBAL", resolved)) {
            val ok = selectProxy("GLOBAL", resolved, protect)
            Log.i(TAG, "GLOBAL direct $resolved -> $ok")
            return ok
        }
        for (sub in selectorGroups) {
            if (!proxies.has(sub)) continue
            if (!groupContains(proxies, sub, resolved)) continue
            selectProxy(sub, resolved, protect)
            if (groupContains(proxies, "GLOBAL", sub)) {
                val ok = selectProxy("GLOBAL", sub, protect)
                Log.i(TAG, "GLOBAL -> $sub -> $resolved ok=$ok")
                return ok
            }
        }
        return false
    }

    private fun groupContains(proxies: JSONObject, group: String, name: String): Boolean {
        val item = proxies.optJSONObject(group) ?: return false
        val all = item.optJSONArray("all") ?: return false
        return arrayContains(all, name)
    }

    private fun arrayContains(arr: JSONArray, name: String): Boolean {
        for (i in 0 until arr.length()) {
            if (arr.optString(i) == name) return true
        }
        return false
    }

    private fun resolveProxyName(nodeLabel: String, proxies: JSONObject): String? {
        val trimmed = nodeLabel.trim()
        val normNode = normalizeLabel(trimmed)
        val leaves = mutableListOf<String>()
        val groupTypes = setOf("Selector", "URLTest", "Fallback", "LoadBalance", "Relay")
        for (key in proxies.keys()) {
            val item = proxies.optJSONObject(key) ?: continue
            if (!groupTypes.contains(item.optString("type"))) {
                leaves.add(key)
            }
        }
        for (name in leaves) {
            if (name == trimmed) return name
        }
        for (name in leaves) {
            if (normalizeLabel(name) == normNode) return name
        }
        for (name in leaves) {
            val norm = normalizeLabel(name)
            if (norm.contains(normNode) || normNode.contains(norm)) return name
            if (name.contains(trimmed) || trimmed.contains(name)) return name
        }
        return null
    }

    private fun normalizeLabel(name: String): String {
        var s = name.trim()
        s = s.replace(Regex("^[📶🚀🔰\\s]+"), "")
        return s.replace(Regex("[\\s\\-_·•]"), "").lowercase()
    }

    private fun fetchProxies(protect: Boolean = false): JSONObject? {
        val resp = MihomoHttpClient.request("GET", "/proxies", protect = protect) ?: return null
        if (!MihomoHttpClient.isSuccess(resp.statusCode)) {
            Log.w(TAG, "GET /proxies -> ${resp.statusCode}")
            return null
        }
        return try {
            JSONObject(resp.body).optJSONObject("proxies")
        } catch (e: Exception) {
            Log.w(TAG, "parse proxies: ${e.message} body=${resp.body.take(120)}")
            null
        }
    }

    private fun patchMode(mode: String, protect: Boolean = false): Boolean {
        val payload = JSONObject().put("mode", mode).toString()
        val resp = MihomoHttpClient.request("PATCH", "/configs", payload, protect) ?: return false
        return MihomoHttpClient.isSuccess(resp.statusCode)
    }

    private fun selectProxy(group: String, proxy: String, protect: Boolean = false): Boolean {
        val encoded = java.net.URLEncoder.encode(group, "UTF-8").replace("+", "%20")
        val payload = JSONObject().put("name", proxy).toString()
        val resp = MihomoHttpClient.request(
            "PUT",
            "/proxies/$encoded",
            payload,
            protect,
        ) ?: return false
        return MihomoHttpClient.isSuccess(resp.statusCode)
    }

    private fun closeConnections(protect: Boolean = false): Boolean {
        val resp = MihomoHttpClient.request("DELETE", "/connections", protect = protect)
            ?: return false
        return MihomoHttpClient.isSuccess(resp.statusCode)
    }

    /** 经 mihomo 对选中节点做延迟测试，验证代理出站是否可达 */
    fun measureProxyDelay(
        nodeLabel: String?,
        protect: Boolean,
        timeoutMs: Int = 8000,
    ): Long? {
        val label = nodeLabel?.trim().orEmpty()
        if (label.isEmpty() || label == "—") return null
        val proxies = fetchProxies(protect) ?: return null
        val resolved = resolveProxyName(label, proxies) ?: return null
        val encoded = java.net.URLEncoder.encode(resolved, "UTF-8").replace("+", "%20")
        val testUrl = java.net.URLEncoder.encode(
            "http://www.gstatic.com/generate_204",
            "UTF-8",
        )
        val resp = MihomoHttpClient.request(
            "GET",
            "/proxies/$encoded/delay?url=$testUrl&timeout=$timeoutMs",
            protect = protect,
            timeoutMs = timeoutMs + 3000,
        ) ?: return null
        if (!MihomoHttpClient.isSuccess(resp.statusCode)) {
            Log.w(TAG, "delay test HTTP ${resp.statusCode} proxy=$resolved")
            return null
        }
        return try {
            val delay = JSONObject(resp.body).optLong("delay", -1L)
            if (delay > 0) {
                Log.i(TAG, "delay test $resolved -> ${delay}ms")
                delay
            } else {
                Log.w(TAG, "delay test failed proxy=$resolved body=${resp.body.take(80)}")
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "delay parse: ${e.message}")
            null
        }
    }
}
