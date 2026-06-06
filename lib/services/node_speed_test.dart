import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/models.dart';

class ProxyEndpoint {
  const ProxyEndpoint({
    required this.remark,
    required this.host,
    required this.port,
  });

  final String remark;
  final String host;
  final int port;
}

/// 拉取订阅后对各节点做 TCP 连通延迟测试。
class NodeSpeedTest {
  static const _timeout = Duration(seconds: 4);

  static Future<Map<String, int>> run(
    List<VpnNode> nodes,
    String subscribeBody, {
    void Function(String nodeId, int ms)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('节点测速请在 macOS 或手机端使用');
    }

    final endpoints = parseSubscription(subscribeBody);
    final results = <String, int>{};

    for (final node in nodes) {
      if (node.status == NodeStatus.offline) continue;
      final ep = _matchEndpoint(node, endpoints);
      if (ep == null) continue;
      final ms = await _tcpPing(ep.host, ep.port);
      if (ms != null) {
        results[node.id] = ms;
        onProgress?.call(node.id, ms);
      }
    }

    return results;
  }

  static List<ProxyEndpoint> parseSubscription(String body) {
    var text = body.trim();
    if (text.isEmpty) return [];

    if (!text.contains('://') && _looksBase64(text)) {
      try {
        text = utf8.decode(base64.decode(_normalizeBase64(text)));
      } catch (_) {}
    }

    final clashEndpoints = _parseClashYaml(text);
    if (clashEndpoints.isNotEmpty) return clashEndpoints;

    final endpoints = <ProxyEndpoint>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final ep = _parseLine(line);
      if (ep != null) endpoints.add(ep);
    }
    return endpoints;
  }

  static ProxyEndpoint? _parseLine(String line) {
    if (line.startsWith('ss://')) return _parseSs(line);
    if (line.startsWith('vmess://')) return _parseVmess(line);
    if (line.startsWith('trojan://')) return _parseTrojan(line);
    if (line.startsWith('vless://')) return _parseVless(line);
    return null;
  }

  static ProxyEndpoint? _parseSs(String line) {
    try {
      final uri = Uri.parse(line.split('#').first);
      var host = uri.host;
      var port = uri.port;
      var remark = uri.fragment;

      if (host.isEmpty && uri.userInfo.isNotEmpty) {
        final decoded = utf8.decode(base64.decode(_normalizeBase64(uri.userInfo)));
        final at = decoded.lastIndexOf('@');
        if (at > 0) {
          final hostPort = decoded.substring(at + 1);
          final hp = hostPort.split(':');
          host = hp.first;
          port = int.tryParse(hp.length > 1 ? hp.last : '') ?? 443;
        }
      }

      if (port == 0) port = 443;
      if (host.isEmpty) return null;
      return ProxyEndpoint(
        remark: Uri.decodeComponent(remark),
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  static ProxyEndpoint? _parseVmess(String line) {
    try {
      final payload = line.substring('vmess://'.length).split('#').first;
      final jsonStr = utf8.decode(base64.decode(_normalizeBase64(payload)));
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final host = m['add']?.toString() ?? m['host']?.toString() ?? '';
      final port = int.tryParse('${m['port']}') ?? 443;
      final remark = m['ps']?.toString() ?? m['remark']?.toString() ?? '';
      if (host.isEmpty) return null;
      return ProxyEndpoint(remark: remark, host: host, port: port);
    } catch (_) {
      return null;
    }
  }

  static ProxyEndpoint? _parseTrojan(String line) {
    try {
      final uri = Uri.parse(line);
      final host = uri.host;
      final port = uri.port == 0 ? 443 : uri.port;
      if (host.isEmpty) return null;
      return ProxyEndpoint(
        remark: Uri.decodeComponent(uri.fragment),
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  static ProxyEndpoint? _parseVless(String line) {
    try {
      final uri = Uri.parse(line.split('#').first);
      final host = uri.host;
      final port = uri.port == 0 ? 443 : uri.port;
      if (host.isEmpty) return null;
      return ProxyEndpoint(
        remark: Uri.decodeComponent(uri.fragment),
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  static List<ProxyEndpoint> _parseClashYaml(String text) {
    final proxiesStart = text.indexOf(RegExp(r'^proxies:\s*$', multiLine: true));
    if (proxiesStart < 0) return [];

    final tail = text.substring(proxiesStart);
    final endMatch = RegExp(
      r'^(proxy-groups|rules|rule-providers|listeners):\s*$',
      multiLine: true,
    ).firstMatch(tail);
    final proxiesText = endMatch == null ? tail : tail.substring(0, endMatch.start);

    final endpoints = <ProxyEndpoint>[];
    final seen = <String>{};

    void addEndpoint(String? name, String? server, String? portRaw) {
      final remark = _cleanYamlScalar(name);
      final host = _cleanYamlScalar(server);
      final port = int.tryParse('${portRaw ?? ''}') ?? 0;
      if (remark == null || host == null || host.isEmpty || port <= 0) return;
      final key = '$remark|$host|$port';
      if (!seen.add(key)) return;
      endpoints.add(ProxyEndpoint(remark: remark, host: host, port: port));
    }

    for (final m in RegExp(
      r'-\s*\{[^}]*\bname\s*:\s*([^,\n}]+)[^}]*\bserver\s*:\s*([^,\n}]+)[^}]*\bport\s*:\s*(\d+)',
      multiLine: true,
    ).allMatches(proxiesText)) {
      addEndpoint(m.group(1), m.group(2), m.group(3));
    }

    final blocks = RegExp(
      r'(?:^|\n)\s*-\s*name\s*:\s*(.+)$([\s\S]*?)(?=\n\s*-\s*name\s*:|\n\s*(?:proxy-groups|rules|rule-providers|listeners)\s*:|$)',
      multiLine: true,
    ).allMatches(proxiesText);

    for (final block in blocks) {
      final name = block.group(1);
      final body = block.group(2) ?? '';
      final server = RegExp(r'^\s*server\s*:\s*(.+)$', multiLine: true).firstMatch(body)?.group(1);
      final port = RegExp(r'^\s*port\s*:\s*(\d+)\s*$', multiLine: true).firstMatch(body)?.group(1);
      addEndpoint(name, server, port);
    }

    return endpoints;
  }

  static String? _cleanYamlScalar(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.endsWith(',')) value = value.substring(0, value.length - 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value.replaceAll(r'\"', '"').replaceAll(r"\'", "'").trim();
  }

  static ProxyEndpoint? _matchEndpoint(VpnNode node, List<ProxyEndpoint> endpoints) {
    final name = node.name.trim();
    final normNode = _norm(name);

    for (final ep in endpoints) {
      final r = ep.remark.trim();
      if (r.isEmpty) continue;
      if (r == name || r.contains(name) || name.contains(r)) return ep;
      final normRemark = _norm(r);
      if (normRemark == normNode ||
          normRemark.contains(normNode) ||
          normNode.contains(normRemark)) {
        return ep;
      }
    }
    return null;
  }

  static String _norm(String s) =>
      s.replaceAll(RegExp(r'[\s\-_·•]'), '').toLowerCase();

  static Future<int?> _tcpPing(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: _timeout,
      );
      await socket.close();
      sw.stop();
      return sw.elapsedMilliseconds.clamp(1, 99999);
    } catch (_) {
      return null;
    }
  }

  static bool _looksBase64(String s) {
    final t = s.replaceAll(RegExp(r'\s'), '');
    return t.length > 40 && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(t);
  }

  static String _normalizeBase64(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s'), '');
    final mod = t.length % 4;
    if (mod > 0) t += '=' * (4 - mod);
    return t;
  }
}
