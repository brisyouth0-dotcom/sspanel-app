package com.kele.kele_vpn

import android.net.Uri
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
        "灵猫加速器",
        "🚀 节点选择",
        "节点选择",
        "Proxy",
        "PROXY",
    )

    private val metaGroupNames = setOf(
        "COMPATIBLE",
        "自动选择",
        "🚀 自动选择",
        "♻️ 自动选择",
        "故障转移",
        "Auto",
        "AUTO",
    )

    private val delayTestUrls = listOf(
        "http://www.gstatic.com/generate_204",
        "http://cp.cloudflare.com/generate_204",
        "https://www.gstatic.com/generate_204",
    )

    /** TUN 已建立后选路（须 protect，避免 API 套接字被 TUN 吞掉） */
    fun applyAfterTunnel(nodeLabel: String?): Boolean = applyBeforeTunnel(nodeLabel, protect = true)

    fun applyBeforeTunnel(nodeLabel: String?): Boolean =
        applyBeforeTunnel(nodeLabel, protect = false)

    private fun applyBeforeTunnel(nodeLabel: String?, protect: Boolean): Boolean {
        if (!MihomoReachability.waitForController(maxMs = 5000)) {
            Log.w(TAG, "controller not ready, rely on config pin")
            return false
        }
        var label = nodeLabel?.trim().orEmpty()
        if (label.isEmpty() || label == "—") {
            label = resolveDefaultLeaf(protect).orEmpty()
            if (label.isEmpty()) {
                Log.w(TAG, "no node label, skip routing")
                return false
            }
            Log.i(TAG, "auto default leaf=$label")
        }
        return try {
            for (attempt in 1..2) {
                if (applyOnce(label, protect = protect)) return true
                Thread.sleep(150)
            }
            Log.w(TAG, "routing API failed after retries, rely on config pin")
            false
        } catch (e: Exception) {
            Log.e(TAG, "applyBeforeTunnel failed", e)
            false
        }
    }

    private fun applyOnce(label: String, protect: Boolean): Boolean {
        // rule + 精简 rules（MATCH,GLOBAL + 拦截 DoT）；global 模式不执行 rules 会导致私人 DNS 绕过
        if (!patchMode("rule", protect)) {
            Log.w(TAG, "set rule mode failed")
        }
        val proxies = fetchProxies(protect) ?: run {
            Log.w(TAG, "fetch proxies failed")
            return false
        }
        val resolved = resolveLeafProxyName(label, proxies) ?: run {
            Log.w(TAG, "no proxy match for: $label")
            return false
        }
        val ok = applyChain(proxies, resolved, protect)
        if (ok) {
            closeConnections(protect)
            val now = readMainGroupNow(protect)
            if (now != null && now != resolved) {
                Log.w(TAG, "main group now=$now expected=$resolved")
            }
            Log.i(TAG, "routing chain ok proxy=$resolved")
        } else {
            Log.w(TAG, "routing chain failed proxy=$resolved")
        }
        return ok
    }

    private fun readMainGroupNow(protect: Boolean): String? {
        val proxies = fetchProxies(protect) ?: return null
        for (group in selectorGroups) {
            if (!proxies.has(group)) continue
            val now = proxies.optJSONObject(group)?.optString("now")?.trim()
            if (!now.isNullOrEmpty()) return now
        }
        return null
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

    /** 未指定节点时，从订阅叶子中挑默认出站（优先 x1.0 倍率） */
    fun resolveDefaultLeaf(protect: Boolean): String? {
        val proxies = fetchProxies(protect) ?: return null
        val leaves = mutableListOf<String>()
        val groupTypes = setOf("Selector", "URLTest", "Fallback", "LoadBalance", "Relay")
        for (key in proxies.keys()) {
            val item = proxies.optJSONObject(key) ?: continue
            if (!groupTypes.contains(item.optString("type")) && !isReservedName(key)) {
                leaves.add(key)
            }
        }
        for (name in leaves) {
            if (Regex("\\[x[\\d.]+\\]", RegexOption.IGNORE_CASE).containsMatchIn(name)) {
                return name
            }
        }
        for (group in selectorGroups) {
            val now = proxies.optJSONObject(group)?.optString("now")?.trim()
            if (!now.isNullOrEmpty()) {
                resolveLeafProxyName(now, proxies)?.let { return it }
            }
        }
        return leaves.firstOrNull()
    }

    private fun resolveLeafProxyName(nodeLabel: String, proxies: JSONObject): String? {
        val leaves = mutableListOf<String>()
        val groupTypes = setOf("Selector", "URLTest", "Fallback", "LoadBalance", "Relay")
        for (key in proxies.keys()) {
            val item = proxies.optJSONObject(key) ?: continue
            if (!groupTypes.contains(item.optString("type")) && !isReservedName(key)) {
                leaves.add(key)
            }
        }
        return ProxyNameMatcher.resolve(nodeLabel, leaves)
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
        val encoded = encodeApiPath(group)
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

    private fun encodeApiPath(segment: String): String =
        Uri.encode(segment, "UTF-8")

    /** 经 mihomo 对选中节点做延迟测试，验证代理出站是否可达 */
    fun measureProxyDelay(
        nodeLabel: String?,
        protect: Boolean,
        timeoutMs: Int = 15000,
    ): Long? {
        val label = nodeLabel?.trim().orEmpty()
        if (label.isEmpty() || label == "—") return null
        val proxies = fetchProxies(protect) ?: return null
        val resolved = resolveLeafProxyName(label, proxies) ?: return null
        return requestDelay(resolved, protect, timeoutMs)
    }

    private fun requestDelay(
        proxyOrGroup: String,
        protect: Boolean,
        timeoutMs: Int,
    ): Long? {
        val encoded = encodeApiPath(proxyOrGroup)
        for (rawUrl in delayTestUrls) {
            val testUrl = Uri.encode(rawUrl, "UTF-8")
            val resp = MihomoHttpClient.request(
                "GET",
                "/proxies/$encoded/delay?url=$testUrl&timeout=$timeoutMs",
                protect = protect,
                timeoutMs = timeoutMs + 3000,
            ) ?: continue
            if (!MihomoHttpClient.isSuccess(resp.statusCode)) {
                Log.w(
                    TAG,
                    "delay test HTTP ${resp.statusCode} proxy=$proxyOrGroup " +
                        "url=$rawUrl body=${resp.body.take(120)}",
                )
                continue
            }
            try {
                val delay = JSONObject(resp.body).optLong("delay", -1L)
                if (delay > 0) {
                    Log.i(TAG, "delay test $proxyOrGroup -> ${delay}ms url=$rawUrl")
                    return delay
                }
                Log.w(
                    TAG,
                    "delay test failed proxy=$proxyOrGroup url=$rawUrl " +
                        "body=${resp.body.take(120)}",
                )
            } catch (e: Exception) {
                Log.w(TAG, "delay parse: ${e.message}")
            }
        }
        return null
    }

    private fun isReservedName(name: String): Boolean {
        val n = name.trim().uppercase()
        return n == "GLOBAL" || n == "DIRECT" || n == "REJECT" ||
            n == "COMPATIBLE" || n == "PASS"
    }
}
