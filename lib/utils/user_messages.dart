import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// 将底层异常转成用户可读提示（避免直接展示 Dio/XMLHttpRequest 原文）。
class UserMessages {
  static String networkError(Object error) {
    if (error is DioException) {
      return _fromDio(error);
    }
    final explicit = _explicitMessage(error);
    if (explicit != null) return explicit;
    final raw = error.toString();
    if (_looksLikeConnectionFailure(raw)) {
      return _connectionHint();
    }
    return '操作失败，请稍后重试';
  }

  static String? _explicitMessage(Object error) {
    if (error is Exception) {
      final raw = error.toString();
      const prefix = 'Exception: ';
      if (raw.startsWith(prefix)) {
        final msg = raw.substring(prefix.length).trim();
        if (msg.isNotEmpty && msg.length <= 240) return msg;
      }
    }
    return null;
  }

  static String _fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return _connectionHint();
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) return '账号或密码错误，或会话已失效';
        if (code != null) return '服务器返回异常（$code），请稍后重试';
        return '服务器响应异常，请稍后重试';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        if (_looksLikeConnectionFailure(error.message ?? '')) {
          return _connectionHint();
        }
        return '网络请求失败，请稍后重试';
    }
  }

  static bool _looksLikeConnectionFailure(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('xmlhttprequest') ||
        lower.contains('connection error') ||
        lower.contains('connection errored') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception');
  }

  static String _connectionHint() {
    if (kIsWeb) {
      return '当前在浏览器中运行，无法直接登录远程面板（跨域限制）。\n'
          '请使用 macOS / Android / iOS 运行：flutter run -d macos';
    }
    return '无法连接服务器，请检查网络或确认面板地址：\n${AppConfig.baseUrl}';
  }
}
