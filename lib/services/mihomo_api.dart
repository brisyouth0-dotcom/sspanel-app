import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Mihomo / Clash Meta external-controller REST 客户端
class MihomoApi {
  MihomoApi() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.mihomoControllerBase,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Authorization': 'Bearer ${AppConfig.mihomoSecret}',
        },
        validateStatus: (c) => c != null && c < 500,
      ),
    );
  }

  late final Dio _dio;

  Future<bool> isAlive() async {
    try {
      final r = await _dio.get<dynamic>('/version');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Windows 冷启动轮询用：短超时，避免单次探测阻塞过久。
  Future<bool> isAliveQuick() async {
    if (!Platform.isWindows) return isAlive();
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(milliseconds: 400);
      final req = await client.getUrl(
        Uri.parse('${AppConfig.mihomoControllerBase}/version'),
      );
      req.headers.set('Authorization', 'Bearer ${AppConfig.mihomoSecret}');
      final res = await req.close().timeout(const Duration(milliseconds: 700));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> proxies() async {
    final r = await _dio.get<dynamic>('/proxies');
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    return {};
  }

  Future<String> getMode() async {
    try {
      final r = await _dio.get<dynamic>('/configs');
      final data = r.data;
      if (data is Map<String, dynamic>) {
        final mode = data['mode'];
        if (mode is String && mode.isNotEmpty) return mode;
      }
    } catch (_) {}
    return 'rule';
  }

  Future<void> setMode(String mode) async {
    await _dio.patch<void>(
      '/configs',
      data: {'mode': mode},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> selectProxy(String group, String name) async {
    await _dio.put<void>(
      '/proxies/$group',
      data: {'name': name},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Map<String, dynamic>> traffic() async {
    final r = await _dio.get<dynamic>('/traffic');
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    return {};
  }

  Future<void> closeAllConnections() async {
    try {
      await _dio.delete<void>('/connections');
    } catch (_) {}
  }

  /// 读取策略组/代理当前选中的节点名（URLTest 的 now 字段）
  Future<String?> proxyNow(String proxyName) async {
    try {
      final encoded = Uri.encodeComponent(proxyName);
      final r = await _dio.get<dynamic>('/proxies/$encoded');
      if (r.statusCode != 200) return null;
      final data = r.data;
      if (data is Map<String, dynamic>) {
        final now = data['now']?.toString().trim();
        if (now != null && now.isNotEmpty) return now;
      }
    } catch (_) {}
    return null;
  }

  /// URLTest / Selector 组成员列表
  List<String> proxyGroupMembers(Map<String, dynamic>? groupData) {
    if (groupData == null) return const [];
    final all = groupData['all'];
    if (all is! List) return const [];
    return all.map((e) => e.toString()).toList();
  }

  /// 与订阅 url-test 一致用 http；https 在部分节点上会导致测速失败
  static const delayTestUrls = [
    'http://www.gstatic.com/generate_204',
    'http://cp.cloudflare.com/generate_204',
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://www.msftconnecttest.com/connecttest.txt',
    'https://www.gstatic.com/generate_204',
  ];

  int? _parseDelayValue(dynamic delay) {
    if (delay is num && delay > 0) return delay.round();
    if (delay is String) {
      final parsed = int.tryParse(delay.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  /// 读取 mihomo 已缓存的测速历史（URLTest / 上次 delay 测试）
  Future<int?> proxyHistoryDelay(String proxyName) async {
    try {
      final encoded = Uri.encodeComponent(proxyName);
      final r = await _dio.get<dynamic>('/proxies/$encoded');
      if (r.statusCode != 200) return null;
      final data = r.data;
      if (data is! Map<String, dynamic>) return null;
      final history = data['history'];
      if (history is! List) return null;
      for (var i = history.length - 1; i >= 0; i--) {
        final item = history[i];
        if (item is Map<String, dynamic>) {
          final ms = _parseDelayValue(item['delay']);
          if (ms != null) return ms;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 通过 mihomo 内核测延迟（与 Clash Verge 一致，走真实代理协议）
  Future<int?> testProxyDelay(
    String proxyName, {
    int? timeoutMs,
  }) async {
    final effectiveTimeout = timeoutMs ??
        (Platform.isWindows ? 30000 : 15000);
    final encodedPaths = <String>{
      Uri.encodeComponent(proxyName),
      proxyName,
    };
    for (final path in encodedPaths) {
      for (final url in delayTestUrls) {
        try {
          final r = await _dio.get<dynamic>(
            '/proxies/$path/delay',
            queryParameters: {
              'url': url,
              'timeout': effectiveTimeout,
            },
            options: Options(
              connectTimeout: Duration(
                milliseconds: Platform.isWindows ? 8000 : 5000,
              ),
              receiveTimeout: Duration(
                milliseconds: effectiveTimeout + 10000,
              ),
              validateStatus: (code) => code != null && code < 600,
            ),
          );
          if (r.statusCode != 200) continue;
          final data = r.data;
          if (data is Map<String, dynamic>) {
            final ms = _parseDelayValue(data['delay']);
            if (ms != null) return ms;
          }
        } catch (_) {}
      }
    }
    return proxyHistoryDelay(proxyName);
  }

  void dispose() => _dio.close();
}
