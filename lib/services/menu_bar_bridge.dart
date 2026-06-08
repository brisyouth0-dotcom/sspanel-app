import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef MenuBarActionHandler = Future<void> Function(
  String action, [
  Map<String, dynamic>? args,
]);

/// macOS 菜单栏托盘桥接
class MenuBarBridge {
  static const MethodChannel _channel =
      MethodChannel('com.panlink.vpn/menu_bar');

  static bool get supported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static void install(MenuBarActionHandler onAction) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'menuAction') {
        final raw = call.arguments;
        if (raw is Map) {
          final action = raw['action']?.toString() ?? '';
          if (action.isNotEmpty) {
            await onAction(action, Map<String, dynamic>.from(raw));
          }
        }
        return;
      }
      final method = call.method;
      if (method.isNotEmpty) {
        await onAction(method);
      }
    });
  }

  static Future<void> updateMenu({
    required bool connected,
    String? nodeName,
    required String mode,
    required List<Map<String, String>> nodes,
    String? selectedNodeId,
    bool autoSelectActive = false,
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('updateMenu', {
        'connected': connected,
        'nodeName': nodeName ?? '',
        'mode': mode,
        'nodes': nodes,
        'selectedNodeId': selectedNodeId ?? '',
        'autoSelectActive': autoSelectActive,
      });
    } on MissingPluginException {
      // macOS target has no registered menu bar bridge.
    }
  }
}
