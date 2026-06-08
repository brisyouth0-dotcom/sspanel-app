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
    'https://www.gstatic.com/generate_204',
  ];

  /// 通过 mihomo 内核测延迟（与 Clash Verge 一致，走真实代理协议）
  Future<int?> testProxyDelay(
    String proxyName, {
    int timeoutMs = 15000,
  }) async {
    final encoded = Uri.encodeComponent(proxyName);
    for (final url in delayTestUrls) {
      try {
        final r = await _dio.get<dynamic>(
          '/proxies/$encoded/delay',
          queryParameters: {
            'url': url,
            'timeout': timeoutMs,
          },
          options: Options(
            receiveTimeout: Duration(milliseconds: timeoutMs + 8000),
            validateStatus: (code) => code != null && code < 600,
          ),
        );
        if (r.statusCode != 200) continue;
        final data = r.data;
        if (data is Map<String, dynamic>) {
          final delay = data['delay'];
          if (delay is num && delay > 0) return delay.round();
        }
      } catch (_) {}
    }
    return null;
  }

  void dispose() => _dio.close();
}
