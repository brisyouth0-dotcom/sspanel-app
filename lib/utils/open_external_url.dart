import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/ios_export_bridge.dart';

/// 打开支付/外链：不依赖 canLaunchUrl（各端常误报 false）
Future<bool> openExternalUrl(String raw) async {
  final uri = normalizeExternalUri(raw);
  final target = uri.toString();
  if (IosExportBridge.supported) {
    if (await IosExportBridge.openUrl(target)) {
      return true;
    }
  }

  const modes = [
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
    LaunchMode.inAppBrowserView,
  ];
  for (final mode in modes) {
    try {
      if (await launchUrl(uri, mode: mode)) {
        return true;
      }
    } catch (_) {
      // 尝试下一种打开方式
    }
  }
  return false;
}

Uri normalizeExternalUri(String raw) {
  var s = raw.trim();
  if (s.isEmpty) {
    throw FormatException('empty url');
  }
  s = _decodeEncodedAbsoluteUri(s);
  if (s.startsWith('//')) {
    s = 'https:$s';
  } else if (s.startsWith('/')) {
    s = '${AppConfig.baseUrl}$s';
  } else if (!_hasUriScheme(s)) {
    final lower = s.toLowerCase();
    if (lower.startsWith('alipay') ||
        lower.startsWith('weixin') ||
        lower.startsWith('wxp://')) {
      // 支付宝/微信唤起链接原样保留
    } else if (s.contains('.') && !s.contains(' ')) {
      s = 'https://$s';
    }
  }
  return Uri.parse(s);
}

bool _hasUriScheme(String value) {
  return RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value);
}

String _decodeEncodedAbsoluteUri(String value) {
  final lower = value.toLowerCase();
  final looksEncoded =
      lower.startsWith('http%3a') ||
      lower.startsWith('https%3a') ||
      lower.startsWith('alipay%3a') ||
      lower.startsWith('alipays%3a') ||
      lower.startsWith('weixin%3a') ||
      lower.startsWith('wxp%3a');
  if (!looksEncoded) return value;
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}
