package com.kele.kele_vpn

/** 面板节点名与 Clash 代理名对齐（保留倍率后缀如 x1.0） */
object ProxyNameMatcher {
    fun stripEmoji(name: String): String =
        name.trim().replace(Regex("^[📶🚀🔰\\s]+"), "")

    fun tierSuffix(name: String): String? =
        Regex("\\[x[\\d.]+\\]$", RegexOption.IGNORE_CASE)
            .find(stripEmoji(name))
            ?.value
            ?.lowercase()

    fun normalize(name: String): String =
        stripEmoji(name).replace(Regex("[\\s\\-_·•]"), "").lowercase()

    fun resolve(nodeLabel: String, candidates: Iterable<String>): String? {
        val trimmed = nodeLabel.trim()
        val stripped = stripEmoji(trimmed)
        val normNode = normalize(trimmed)
        val nodeTier = tierSuffix(trimmed)

        for (name in candidates) {
            val tier = tierSuffix(name)
            if (nodeTier != null) {
                if (tier != nodeTier) continue
            } else if (tier != null) {
                continue
            }
            if (name == trimmed) return name
        }
        for (name in candidates) {
            val tier = tierSuffix(name)
            if (nodeTier != null) {
                if (tier != nodeTier) continue
            } else if (tier != null) {
                continue
            }
            if (stripEmoji(name) == stripped) return name
        }
        for (name in candidates) {
            val tier = tierSuffix(name)
            if (nodeTier != null) {
                if (tier != nodeTier) continue
            } else if (tier != null) {
                continue
            }
            val norm = normalize(name)
            if (norm == normNode) return name
        }
        for (name in candidates) {
            val tier = tierSuffix(name)
            if (nodeTier != null) {
                if (tier != nodeTier) continue
            } else if (tier != null) {
                continue
            }
            val norm = normalize(name)
            if (norm.contains(normNode) || normNode.contains(norm)) return name
            if (name.contains(trimmed) || trimmed.contains(name)) return name
        }
        return null
    }
}
