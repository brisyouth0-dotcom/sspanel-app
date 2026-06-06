/// 面板节点名与 Clash 配置内代理名对齐（去除 emoji / 空白差异）
String normalizeProxyLabel(String name) {
  var s = name.trim();
  s = s.replaceFirst(RegExp(r'^[📶🚀🔰\s]+'), '');
  return s.replaceAll(RegExp(r'[\s\-_·•]'), '').toLowerCase();
}

String? matchProxyName(String nodeName, Iterable<String> proxyNames) {
  final trimmed = nodeName.trim();
  final normNode = normalizeProxyLabel(trimmed);

  for (final proxy in proxyNames) {
    if (proxy == trimmed) return proxy;
  }
  for (final proxy in proxyNames) {
    if (normalizeProxyLabel(proxy) == normNode) return proxy;
  }
  for (final proxy in proxyNames) {
    final normProxy = normalizeProxyLabel(proxy);
    if (normProxy.contains(normNode) || normNode.contains(normProxy)) {
      return proxy;
    }
    if (proxy.contains(trimmed) || trimmed.contains(proxy)) return proxy;
  }
  return null;
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
