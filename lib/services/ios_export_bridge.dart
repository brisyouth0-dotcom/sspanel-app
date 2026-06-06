import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 订阅导出（Shadowrocket / Stash 等第三方客户端）
class IosExportBridge {
  static const MethodChannel _channel =
      MethodChannel('com.kele.kele_vpn/ios_export');

  static bool get supported => !kIsWeb && Platform.isIOS;

  static Future<bool> copyText(String text) async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('copyText', {'text': text});
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openUrl(String url) async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return ok == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shadowrocket 订阅导入 URL
  static String shadowrocketImportUrl(String subscribeUrl) {
    final encoded = Uri.encodeComponent(subscribeUrl);
    return 'shadowrocket://add/sub://$encoded?remark=${Uri.encodeComponent('灵猫加速器')}';
  }

  /// Stash 订阅导入 URL
  static String stashImportUrl(String subscribeUrl) {
    final encoded = Uri.encodeComponent(subscribeUrl);
    return 'stash://install-config?url=$encoded';
  }
}
