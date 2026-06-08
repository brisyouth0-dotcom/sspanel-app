import '../models/models.dart';
import 'proxy_name_match.dart';

/// 订阅里用于展示流量/到期信息的“伪节点”，不是可连接服务器
bool isSubscriptionInfoNode(String name) {
  final n = name.trim();
  if (n.isEmpty) return true;

  const markers = [
    '剩余流量',
    '距离下次重置',
    '套餐到期',
    '到期时间',
    '过期时间',
    '已用流量',
    '重置剩余',
  ];
  for (final m in markers) {
    if (n.contains(m)) return true;
  }

  if (RegExp(r'流量\s*[:：]').hasMatch(n)) return true;
  if (RegExp(r'^\d+(\.\d+)?\s*GB', caseSensitive: false).hasMatch(n)) {
    return true;
  }
  if (RegExp(r'^\d+\s*天').hasMatch(n)) return true;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(n)) return true;

  return false;
}

List<VpnNode> filterConnectableNodes(Iterable<VpnNode> nodes) {
  return nodes.where((n) => !isSubscriptionInfoNode(n.name)).toList();
}

/// Clash 配置里可连接的代理名（排除流量/到期信息项）
bool isConnectableProxyName(String name) {
  final n = name.trim();
  if (n.isEmpty || n == 'DIRECT' || n == 'REJECT') return false;
  return !isSubscriptionInfoNode(n);
}

/// 过滤自动选择结果，避免 DIRECT / COMPATIBLE 等策略组名进入 UI
String? sanitizeProxyLeaf(
  String? name, {
  Map<String, dynamic>? proxies,
}) {
  if (name == null) return null;
  final t = name.trim();
  if (!isConnectableProxyName(t)) return null;
  if (isReservedOutboundName(t)) return null;
  if (proxies != null && !isRealOutboundProxy(t, proxies)) return null;
  return t;
}
