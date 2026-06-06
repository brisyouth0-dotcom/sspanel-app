/// 面板与 Mihomo 客户端配置（勿写入数据库等敏感项）
class AppConfig {
  /// Xboard 站点地址（灵猫加速器）
  static const String baseUrl = 'https://user.panlink.site';

  static const String subUrl = baseUrl;

  /// JSON API 前缀
  static String get apiBase => '$baseUrl/api/v1';

  static const String panelType = 'xboard';

  static const String panelAppName = '灵猫加速器';

  static const String userAgent =
      'PanlinkVPN/1.0.0 (Flutter; Xboard-Client)';

  /// Mihomo external-controller（仅本机）
  static const String mihomoControllerHost = '127.0.0.1';
  static const int mihomoControllerPort = 9090;
  static const String mihomoSecret = 'panlink-mihomo-local';

  static const int mihomoMixedPort = 7890;

  /// 系统代理指向 mihomo mixed-port
  static const String systemProxyHost = '127.0.0.1';

  static String get mihomoControllerBase =>
      'http://$mihomoControllerHost:$mihomoControllerPort';

  /// 兼容旧 SSPanel 代码路径
  static String get subscribeBase => '$subUrl/api/v1/client/subscribe';

  /// Telegram 客服（纸飞机），可在面板后台修改后同步更新
  static const String telegramSupportUrl = 'https://t.me/panlinkvpn';

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}
