import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// 带 Cookie 持久化的 Dio 客户端。
class SspanelHttpClient {
  SspanelHttpClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json, text/html, */*',
          'X-Requested-With': 'XMLHttpRequest',
          'User-Agent': AppConfig.userAgent,
        },
        validateStatus: (code) => code != null && code < 500,
      ),
    );
  }

  late final Dio _dio;
  CookieJar? _jar;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    if (kIsWeb) {
      // Web：由浏览器管理 Cookie；dio_cookie_manager 明确禁止在 Web 使用
      _ready = true;
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final storage = FileStorage('${dir.path}/.cookies/');
    _jar = PersistCookieJar(storage: storage);
    _dio.interceptors.add(CookieManager(_jar!));
    _ready = true;
  }

  Future<void> clearCookies() async {
    if (kIsWeb) return;
    await _jar?.deleteAll();
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
  }) async {
    await init();
    return _dio.get<dynamic>(
      path,
      queryParameters: query,
      options: Options(
        headers: {
          'Referer': referer ?? '${AppConfig.baseUrl}/user',
        },
        followRedirects: true,
      ),
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    await init();
    return _dio.post<dynamic>(
      path,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
  }

  Map<String, dynamic>? decodeJson(Response<dynamic> response) {
    try {
      final body = response.data;
      if (body is Map<String, dynamic>) return body;
      if (body is String) {
        final t = body.trim();
        if (t.isEmpty || t.startsWith('<')) return null;
        return jsonDecode(t) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String responseBody(Response<dynamic> response) {
    final data = response.data;
    if (data is String) return data;
    return data?.toString() ?? '';
  }

  void dispose() => _dio.close();
}
