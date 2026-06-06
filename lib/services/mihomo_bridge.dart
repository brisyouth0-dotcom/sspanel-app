import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生层拉起 / 停止 mihomo 进程
class MihomoBridge {
  static const MethodChannel _channel =
      MethodChannel('com.panlink.vpn/mihomo');

  static bool get supported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isAndroid ||
          Platform.isIOS);

  static Future<String?> resolveBinary() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('resolveBinary');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> lastStartError() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('lastStartError');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> start({required String configPath}) async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('start', {
        'configPath': configPath,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Desktop target has no registered mihomo bridge.
    }
  }

  /// 读取 mihomo 实时速率（bps），VPN 建立后须走原生 protect
  static Future<({int up, int down})?> pollTraffic() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('pollTraffic');
      if (raw == null) return null;
      final up = (raw['up'] as num?)?.toInt() ?? 0;
      final down = (raw['down'] as num?)?.toInt() ?? 0;
      return (up: up, down: down);
    } on MissingPluginException {
      return null;
    }
  }

  /// Android VPN 已连接时切换节点（原生 protect 后访问 mihomo API）
  static Future<bool> applyNode({required String proxyName}) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('applyNode', {
        'proxyName': proxyName,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android 机型 VPN 策略（QUIC/DoT 拦截等），由 [DeviceVpnProfile] 提供
  static Future<AndroidVpnProfile> getDeviceVpnProfile() async {
    if (!Platform.isAndroid) return AndroidVpnProfile.stock;
    try {
      final raw = await _channel.invokeMethod<Map>('getDeviceVpnProfile');
      if (raw == null) return AndroidVpnProfile.stock;
      return AndroidVpnProfile(
        kind: raw['kind']?.toString() ?? 'STOCK',
        blockQuic: raw['blockQuic'] == true,
        blockDoT: raw['blockDoT'] == true,
      );
    } on MissingPluginException {
      return AndroidVpnProfile.stock;
    }
  }
}

/// 与 Android [DeviceVpnProfile] 对应的 Dart 侧策略
class AndroidVpnProfile {
  const AndroidVpnProfile({
    required this.kind,
    required this.blockQuic,
    required this.blockDoT,
  });

  final String kind;
  final bool blockQuic;
  final bool blockDoT;

  static const stock = AndroidVpnProfile(
    kind: 'STOCK',
    blockQuic: false,
    blockDoT: false,
  );
}
