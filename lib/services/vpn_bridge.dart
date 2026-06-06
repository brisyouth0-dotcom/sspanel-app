import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'panel_exceptions.dart';

/// 各端原生 VPN 桥接（Android 为完整 VpnService；iOS/macOS 为同名 MethodChannel，可扩展 Network Extension）。
class VpnBridge {
  static const MethodChannel _channel = MethodChannel('com.kele.kele_vpn/vpn');

  static bool get _native => !kIsWeb;

  static Future<bool> prepare() async {
    if (!_native) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('prepare')
          .timeout(const Duration(seconds: 90));
      return ok == true;
    } on TimeoutException {
      throw PanelApiException('VPN 授权超时，请在系统弹窗中允许 VPN 连接');
    } on PlatformException catch (e) {
      final detail = e.message?.trim();
      throw PanelApiException(
        detail != null && detail.isNotEmpty
            ? detail
            : 'VPN 授权失败（${e.code}）',
      );
    } on MissingPluginException {
      return true;
    }
  }

  static Future<void> start({
    required String nodeName,
    String? configPath,
    String? proxyName,
  }) async {
    if (!_native) return;
    try {
      await _channel
          .invokeMethod<void>('start', <String, dynamic>{
            'nodeName': nodeName,
            if (configPath != null && configPath.isNotEmpty)
              'configPath': configPath,
            if (proxyName != null && proxyName.isNotEmpty)
              'proxyName': proxyName,
          })
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw PanelApiException('VPN 启动超时，请关闭其他代理应用后重试');
    } on PlatformException catch (e) {
      final detail = e.message?.trim();
      throw PanelApiException(
        detail != null && detail.isNotEmpty
            ? detail
            : 'VPN 启动失败（${e.code}）',
      );
    } on MissingPluginException {
      // Windows/Linux 等尚未注册原生实现
    }
  }

  static Future<void> stop() async {
    if (!_native) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Windows/Linux 等尚未注册原生实现
    }
  }

  static Future<bool> isActive() async {
    if (!_native) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isActive');
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// 强杀进程后对齐 VPN 状态，关闭系统里残留的「连接中」
  static Future<bool> reconcile() async {
    if (!_native) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('reconcile');
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }
}
