package com.kele.kele_vpn

import android.util.Log
import java.io.File

/** 在 mihomo 启动前把选中节点置顶，并下沉 DIRECT/REJECT */
object ConfigYamlPinner {
    private const val TAG = "ConfigYamlPinner"

    @Volatile
    var lastPinnedPath: String? = null
        private set

    fun pin(configPath: String, nodeLabel: String?): String {
        val label = nodeLabel?.trim().orEmpty()
        if (label.isEmpty() || label == "—") {
            lastPinnedPath = configPath
            return configPath
        }
        val file = File(configPath)
        if (!file.exists()) {
            lastPinnedPath = configPath
            return configPath
        }
        return try {
            val yaml = file.readText()
            val leafNames = parseLeafNames(yaml)
            val resolved = resolveProxyName(label, leafNames) ?: run {
                Log.w(TAG, "no leaf match for $label")
                return configPath
            }
            val pinned = reorderProxyGroups(yaml, resolved)
            val out = File(file.parentFile, "config.pinned.yaml")
            out.writeText(pinned)
            lastPinnedPath = out.absolutePath
            Log.i(TAG, "pinned proxy=$resolved -> ${out.absolutePath}")
            out.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "pin failed: ${e.message}")
            configPath
        }
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
                val directReject = entries.filter {
                    val n = nameOf(it)
                    n == "DIRECT" || n == "REJECT"
                }
                val others = entries.filter {
                    val n = nameOf(it)
                    n != resolved && n != "DIRECT" && n != "REJECT"
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
                out.addAll(directReject)
                continue
            }
            out.add(line)
            i++
        }
        return out.joinToString("\n")
    }

    private fun resolveProxyName(nodeLabel: String, leafNames: List<String>): String? {
        val trimmed = nodeLabel.trim()
        val normNode = normalizeLabel(trimmed)
        for (name in leafNames) {
            if (name == trimmed) return name
        }
        for (name in leafNames) {
            if (normalizeLabel(name) == normNode) return name
        }
        for (name in leafNames) {
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

    private fun String.indexOfFirstLine(key: String): Int {
        val idx = indexOf("\n$key")
        return if (idx >= 0) idx + 1 else if (startsWith(key)) 0 else -1
    }
}
