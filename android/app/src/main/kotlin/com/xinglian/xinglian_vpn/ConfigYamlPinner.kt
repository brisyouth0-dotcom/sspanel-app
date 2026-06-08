package com.kele.kele_vpn

import android.util.Log
import java.io.File

/** 在 mihomo 启动前把选中节点置顶，并下沉 DIRECT/REJECT */
object ConfigYamlPinner {
    private const val TAG = "ConfigYamlPinner"

    private val sinkGroupNames = setOf(
        "COMPATIBLE",
        "自动选择",
        "🚀 自动选择",
        "♻️ 自动选择",
        "故障转移",
        "Auto",
        "AUTO",
        "DIRECT",
        "REJECT",
        "GLOBAL",
    )

    @Volatile
    var lastPinnedPath: String? = null
        private set

    @Volatile
    var lastPinSucceeded: Boolean = false
        private set

    fun pin(configPath: String, nodeLabel: String?): String {
        // 不改写 YAML：文本 pin 易破坏 proxy-groups 缩进，选路由 MihomoRouting API 完成
        lastPinSucceeded = false
        lastPinnedPath = configPath
        val label = nodeLabel?.trim().orEmpty()
        if (label.isNotEmpty() && label != "—") {
            Log.i(TAG, "skip yaml pin proxy=$label use=${configPath}")
        }
        return configPath
    }

    private fun parseLeafNames(yaml: String): List<String> {
        val proxiesStart = yaml.indexOfFirstLine("proxies:")
        val pgStart = yaml.indexOfFirstLine("proxy-groups:")
        if (proxiesStart < 0) return emptyList()
        val end = if (pgStart > proxiesStart) pgStart else yaml.length
        val section = yaml.substring(proxiesStart, end)
        val names = mutableListOf<String>()
        Regex("""^\s*-\s*name:\s*(.+)$""", RegexOption.MULTILINE)
            .findAll(section)
            .mapTo(names) { it.groupValues[1].trim().trim('"', '\'') }
        Regex("""\{[^}]*\bname:\s*['"]?([^,'"\n}]+)['"]?""", RegexOption.MULTILINE)
            .findAll(section)
            .mapTo(names) { it.groupValues[1].trim() }
        return names.distinct()
    }

    private fun reorderProxyGroups(yaml: String, resolved: String): String {
        val lines = yaml.split('\n')
        val out = mutableListOf<String>()
        var inProxyGroups = false
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            if (line.trim() == "proxy-groups:") {
                inProxyGroups = true
            }
            if (inProxyGroups && line.trim() == "proxies:") {
                out.add(line)
                i++
                val entries = mutableListOf<String>()
                while (i < lines.size) {
                    val entry = lines[i]
                    if (entry.trim().startsWith("- ")) {
                        entries.add(entry)
                        i++
                        continue
                    }
                    break
                }
                val nameOf = { e: String ->
                    e.trim().removePrefix("- ").trim().trim('"', '\'')
                }
                val selected = entries.filter { nameOf(it) == resolved }
                val sunk = entries.filter { nameOf(it) in sinkGroupNames }
                val others = entries.filter {
                    val n = nameOf(it)
                    n != resolved && n !in sinkGroupNames
                }
                if (selected.isEmpty()) {
                    val quoted = if (resolved.contains('[') || resolved.contains(':')) {
                        "  - \"$resolved\""
                    } else {
                        "  - $resolved"
                    }
                    out.add(quoted)
                } else {
                    out.addAll(selected)
                }
                out.addAll(others)
                out.addAll(sunk)
                continue
            }
            out.add(line)
            i++
        }
        return out.joinToString("\n")
    }

    private fun String.indexOfFirstLine(key: String): Int {
        val idx = indexOf("\n$key")
        return if (idx >= 0) idx + 1 else if (startsWith(key)) 0 else -1
    }
}
