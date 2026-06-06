import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// macOS 系统代理（HTTP / HTTPS / SOCKS → mihomo mixed-port）
class SystemProxyBridge {
  static const MethodChannel _channel =
      MethodChannel('com.panlink.vpn/system_proxy');

  static bool get supported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static Future<bool> enable({
    String host = AppConfig.systemProxyHost,
    int port = AppConfig.mihomoMixedPort,
  }) async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('enable', {
        'host': host,
        'port': port,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> disable() async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('disable');
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isEnabled');
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }
}
