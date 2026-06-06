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

  /// 通过 mihomo 内核测延迟（与 Clash Verge 一致，走真实代理协议）
  Future<int?> testProxyDelay(
    String proxyName, {
    int timeoutMs = 10000,
  }) async {
    try {
      final encoded = Uri.encodeComponent(proxyName);
      final r = await _dio.get<dynamic>(
        '/proxies/$encoded/delay',
        queryParameters: {
          'url': 'http://www.gstatic.com/generate_204',
          'timeout': timeoutMs,
        },
        options: Options(
          receiveTimeout: Duration(milliseconds: timeoutMs + 5000),
          validateStatus: (code) => code != null && code < 600,
        ),
      );
      if (r.statusCode != 200) return null;
      final data = r.data;
      if (data is Map<String, dynamic>) {
        final delay = data['delay'];
        if (delay is num && delay > 0) return delay.round();
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _dio.close();
}
