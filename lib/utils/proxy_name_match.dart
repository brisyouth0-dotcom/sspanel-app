import 'node_filters.dart';

String _stripLeadingEmoji(String name) {
  return name.trim().replaceFirst(RegExp(r'^[📶🚀🔰\s]+'), '');
}

/// 倍率后缀，如 [x1.0] — 用于区分同名不同档位节点
String? extractProxyTierSuffix(String name) {
  final m = RegExp(r'\[x[\d.]+\]$', caseSensitive: false)
      .firstMatch(_stripLeadingEmoji(name));
  return m?.group(0)?.toLowerCase();
}

/// 面板节点名与 Clash 配置内代理名对齐（保留 [x1.0] 倍率后缀）
String normalizeProxyLabel(String name) {
  final s = _stripLeadingEmoji(name);
  return s.replaceAll(RegExp(r'[\s\-_·•]'), '').toLowerCase();
}

String? matchProxyName(String nodeName, Iterable<String> proxyNames) {
  final trimmed = nodeName.trim();
  final stripped = _stripLeadingEmoji(trimmed);
  final normNode = normalizeProxyLabel(trimmed);
  final nodeTier = extractProxyTierSuffix(stripped);

  String? best;
  var bestScore = -1;

  for (final proxy in proxyNames) {
    final proxyStripped = _stripLeadingEmoji(proxy);
    final proxyTier = extractProxyTierSuffix(proxyStripped);

    // 面板带 [x1.0] 必须匹配同倍率；面板无倍率则不匹配带倍率的代理
    if (nodeTier != null) {
      if (proxyTier != nodeTier) continue;
    } else if (proxyTier != null) {
      continue;
    }

    final normProxy = normalizeProxyLabel(proxy);
    final int score;
    if (proxy == trimmed) {
      score = 10000;
    } else if (proxyStripped == stripped) {
      score = 9500;
    } else if (normProxy == normNode) {
      score = 9000;
    } else if (normProxy.contains(normNode) || normNode.contains(normProxy)) {
      score = 8000 - (normProxy.length - normNode.length).abs();
    } else if (proxy.contains(trimmed) || trimmed.contains(proxy)) {
      score = 7000 - (proxy.length - trimmed.length).abs();
    } else {
      continue;
    }
    if (score > bestScore) {
      bestScore = score;
      best = proxy;
    }
  }
  return best;
}

bool isAutoSelectGroupName(String name) {
  final t = name.trim();
  if (autoSelectPreferredNames.contains(t)) return true;
  return t.contains('自动') || t.toLowerCase() == 'auto';
}

const autoSelectPreferredNames = [
  '自动选择',
  '🚀 自动选择',
  '♻️ 自动选择',
  'Auto',
  'AUTO',
];

/// 从 mihomo /proxies 响应中解析「自动选择」策略组名
String? resolveAutoSelectGroupName(Map<String, dynamic> proxies) {
  for (final name in autoSelectPreferredNames) {
    final val = proxies[name];
    if (val is Map) {
      final type = val['type']?.toString() ?? '';
      if (type == 'URLTest' || type == 'Fallback') return name;
    }
  }
  for (final entry in proxies.entries) {
    final val = entry.value;
    if (val is! Map) continue;
    final type = val['type']?.toString() ?? '';
    if (type != 'URLTest' && type != 'Fallback') continue;
    final key = entry.key;
    if (key.contains('自动') || key.toLowerCase().contains('auto')) {
      return key;
    }
  }
  return null;
}

/// 从 Clash YAML 解析「自动选择」策略组名（连接前 mihomo 未启动时使用）
String? resolveAutoSelectGroupFromYaml(String yaml) {
  final pgStart = yaml.indexOf(RegExp(r'^proxy-groups:\s*$', multiLine: true));
  if (pgStart < 0) return null;

  final tail = yaml.substring(pgStart);
  final rulesIdx = tail.indexOf(RegExp(r'^rules:\s*$', multiLine: true));
  final section = rulesIdx > 0 ? tail.substring(0, rulesIdx) : tail;

  final blocks = RegExp(
    r'(?:^|\n)\s*-\s*name:\s*(.+)$([\s\S]*?)(?=\n\s*-\s*name\s*:|\n\s*rules\s*:|$)',
    multiLine: true,
  ).allMatches(section);

  String? fallback;
  for (final block in blocks) {
    final rawName = block.group(1)?.trim() ?? '';
    final name = rawName
        .replaceAll(RegExp(r'''^["']|["']$'''), '')
        .replaceAll(RegExp(r',$'), '')
        .trim();
    final body = block.group(2) ?? '';
    final type = RegExp(r'^\s*type:\s*(.+)$', multiLine: true)
            .firstMatch(body)
            ?.group(1)
            ?.trim()
            .replaceAll(RegExp(r'''^["']|["']$'''), '') ??
        '';
    if (type != 'URLTest' && type != 'Fallback') continue;
    if (autoSelectPreferredNames.contains(name)) return name;
    if (name.contains('自动') || name.toLowerCase().contains('auto')) {
      fallback ??= name;
    }
  }
  return fallback;
}

/// 从 Clash YAML 解析 proxies 段内的叶子节点名
List<String> extractLeafNamesFromYaml(String yaml) {
  final proxiesStart = yaml.indexOf(RegExp(r'^proxies:\s*$', multiLine: true));
  final pgStart = yaml.indexOf(RegExp(r'^proxy-groups:\s*$', multiLine: true));
  if (proxiesStart < 0) return const [];
  final end = pgStart > proxiesStart ? pgStart : yaml.length;
  final section = yaml.substring(proxiesStart, end);
  final names = <String>[];
  final nameRe = RegExp(r'^\s*-\s*name:\s*(.+)$', multiLine: true);
  for (final m in nameRe.allMatches(section)) {
    final raw = m.group(1)?.trim() ?? '';
    if (raw.isEmpty) continue;
    names.add(raw.replaceAll(RegExp(r'''^["']|["']$'''), ''));
  }
  final inlineRe = RegExp(
    r'''\{[^}]*\bname:\s*['"]?([^,'"\n}]+)['"]?''',
    multiLine: true,
  );
  for (final m in inlineRe.allMatches(section)) {
    final n = m.group(1)?.trim() ?? '';
    if (n.isNotEmpty) names.add(n);
  }
  return names.toSet().toList();
}

List<String> leafProxyNames(Map<String, dynamic> proxies) {
  const groupTypes = {'Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay'};
  return proxies.entries
      .where((e) {
        final val = e.value;
        if (val is! Map) return false;
        final type = val['type']?.toString() ?? '';
        return !groupTypes.contains(type);
      })
      .map((e) => e.key)
      .toList();
}

/// 可测速/可连接的叶子代理（排除 DIRECT、流量信息等）
List<String> connectableLeafProxyNames(Map<String, dynamic> proxies) {
  return leafProxyNames(proxies).where(isConnectableProxyName).toList();
}

const proxyGroupTypes = {
  'Selector',
  'URLTest',
  'Fallback',
  'LoadBalance',
  'Relay',
};

/// Clash 内置 / 策略组占位名，不能作为实际出站节点
const reservedOutboundNames = {
  'GLOBAL',
  'DIRECT',
  'REJECT',
  'COMPATIBLE',
  'PASS',
  'PROXY',
  'Proxy',
  '节点选择',
  '🚀 节点选择',
  '灵猫加速器',
  '自动选择',
  '🚀 自动选择',
  '♻️ 自动选择',
  'Auto',
  'AUTO',
};

bool isReservedOutboundName(String name) {
  final t = name.trim();
  if (t.isEmpty) return true;
  if (reservedOutboundNames.contains(t)) return true;
  return t.toUpperCase() == 'COMPATIBLE' || t.toUpperCase() == 'GLOBAL';
}

bool isProxyGroupEntry(Map<String, dynamic>? item) {
  if (item == null) return false;
  final type = item['type']?.toString() ?? '';
  return proxyGroupTypes.contains(type);
}

/// mihomo /proxies 里是否为真实可连代理（非策略组）
bool isRealOutboundProxy(String name, Map<String, dynamic> proxies) {
  final trimmed = name.trim();
  if (!isConnectableProxyName(trimmed)) return false;
  if (isReservedOutboundName(trimmed)) return false;
  final item = proxies[trimmed];
  if (item is! Map<String, dynamic>) return false;
  return !isProxyGroupEntry(item);
}

/// 真实可连的出站代理名
List<String> realOutboundProxyNames(Map<String, dynamic> proxies) {
  return connectableLeafProxyNames(proxies)
      .where((n) => isRealOutboundProxy(n, proxies))
      .toList();
}
