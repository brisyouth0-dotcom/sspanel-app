import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Xboard / V2board 风格 JSON API 客户端（Bearer auth_data）
class XboardHttpClient {
  XboardHttpClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBase,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': AppConfig.userAgent,
        },
        validateStatus: (code) => code != null && code < 500,
      ),
    );
  }

  static const _tokenKey = 'xboard_auth_data';

  late final Dio _dio;
  String? _authData;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authData = prefs.getString(_tokenKey);
  }

  String? get authData => _authData;

  void clearAuthDataLocally() {
    _authData = null;
  }

  Future<void> setAuthData(String? token) async {
    _authData = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  Map<String, String> _headers({bool auth = true}) {
    final h = <String, String>{};
    if (auth && _authData != null && _authData!.isNotEmpty) {
      h['Authorization'] = _authData!.startsWith('Bearer ')
          ? _authData!
          : 'Bearer $_authData';
    }
    return h;
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) async {
    await init();
    return _dio.get<dynamic>(
      path,
      queryParameters: query,
      options: Options(headers: _headers(auth: auth)),
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    bool auth = true,
  }) async {
    await init();
    return _dio.post<dynamic>(
      path,
      data: data,
      options: Options(headers: _headers(auth: auth)),
    );
  }

  Future<Response<dynamic>> getAbsolute(String url) async {
    await init();
    return _dio.get<dynamic>(
      url,
      options: Options(
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Accept': '*/*',
        },
      ),
    );
  }

  /// 拉取 Clash 订阅正文（模拟 Clash 客户端 UA，附带登录态）
  Future<String> fetchSubscribeContent(String url) async {
    await init();
    const userAgents = [
      'clash.meta',
      'ClashMeta/1.19.0',
      'ClashForAndroid/2.8.28',
      AppConfig.userAgent,
    ];
    Object? lastError;
    for (final ua in userAgents) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(
            headers: {
              'User-Agent': ua,
              'Accept': 'text/yaml, text/plain, application/yaml, */*',
              if (_authData != null && _authData!.isNotEmpty)
                'Authorization': _authData!.startsWith('Bearer ')
                    ? _authData!
                    : 'Bearer $_authData',
            },
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (code) => code != null && code < 500,
          ),
        );
        if (response.statusCode == 200) {
          final body = response.data ?? '';
          if (body.trim().isNotEmpty) return body;
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        error: lastError,
      );
    }
    return '';
  }

  Map<String, dynamic>? decodeJson(Response<dynamic> response) {
    try {
      final body = response.data;
      if (body is Map<String, dynamic>) return body;
      if (body is String) {
        final t = body.trim();
        if (t.isEmpty) return null;
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
