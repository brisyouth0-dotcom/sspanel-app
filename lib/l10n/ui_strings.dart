import 'package:flutter/widgets.dart';

import 'ui_lang.dart';

typedef S = UiStrings;

/// 语言：简体中文（默认）/ 繁體中文 / English
class UiStrings {
  UiStrings(this.lang);

  final UiLang lang;

  Locale get flutterLocale => switch (lang) {
    UiLang.english => const Locale('en'),
    UiLang.traditionalChinese => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    ),
    UiLang.simplifiedChinese => const Locale('zh', 'CN'),
  };

  String _t(String en, String hans, String hant) {
    if (lang.isEn) return en;
    if (lang.isHant) return hant;
    return hans;
  }

  String get appTitle => _t('Panlink VPN', '灵猫加速器', '泛連VPN');

  String get welcomeBack => _t('Welcome back', '欢迎回来', '歡迎回來');
  String get upgradePlan => _t('Upgrade', '升级套餐', '升級套餐');
  String get selectServer => _t('Select server', '选择节点', '選擇節點');
  String get connected => _t('Connected', '已连接', '已連接');
  String get disconnected => _t('Disconnected', '未连接', '未連接');
  String get tapDisconnect => _t('Tap to disconnect', '点击断开', '點擊斷開');
  String get tapConnect => _t('Tap to connect', '点击连接', '點擊連接');
  String get expiredStatus => _t('Expired', '已到期', '已到期');

  String get realtimeTraffic => _t('Live traffic', '实时流量', '即時流量');
  String get uploadLabel => _t('Upload', '上传', '上傳');
  String get downloadLabel => _t('Download', '下载', '下載');
  String get systemProxy => _t('System proxy', '系统代理', '系統代理');
  String get systemProxySub => _t(
    'Route system traffic via mihomo',
    '连接后自动指向 127.0.0.1 代理',
    '連線後自動指向 127.0.0.1 代理',
  );
  String get autoSystemProxy =>
      _t('Auto-enable system proxy', '连接时自动开启系统代理', '連線時自動開啟系統代理');
  String systemProxyEndpoint(int port) => _t(
    'HTTP/SOCKS → 127.0.0.1:$port',
    'HTTP/SOCKS → 127.0.0.1:$port',
    'HTTP/SOCKS → 127.0.0.1:$port',
  );

  String daysLeftLine(int daysLeft) {
    if (daysLeft > 3650) return _t('Unlimited', '∞ 天剩余', '∞ 天剩餘');
    if (daysLeft > 0) {
      return _t('$daysLeft days left', '$daysLeft 天剩余', '$daysLeft 天剩餘');
    }
    return expiredStatus;
  }

  String get loginTitle => _t('Welcome back', '欢迎回来', '歡迎回來');
  String get loginSubtitle =>
      _t('Sign in to your Panlink account', '登录您的灵猫加速器账号', '登入您的泛連VPN帳號');
  String get emailHint => _t('Email', '邮箱地址', '郵箱地址');
  String get passwordHint => _t('Password', '密码', '密碼');
  String get loginButton => _t('Sign in', '登录', '登入');
  String get registerHint => _t('No account? ', '没有账号？ ', '沒有帳號？ ');
  String get registerLink => _t('Register', '注册账号', '註冊帳號');
  String get registerTitle => _t('Create account', '创建账号', '創建帳號');
  String get registerSubtitle =>
      _t('Join Panlink VPN today', '即刻加入灵猫加速器', '即刻加入泛連VPN');
  String get registerButton => _t('Sign up', '注册', '註冊');
  String get hasAccountHint =>
      _t('Already have an account? ', '已有账号？ ', '已有帳號？ ');
  String get inviteCodeHint =>
      _t('Invite code (optional)', '邀请码（选填）', '邀請碼（選填）');
  String get emailCodeHint => _t('Email verification code', '邮箱验证码', '郵箱驗證碼');
  String get sendCodeButton => _t('Send code', '发送验证码', '發送驗證碼');
  String sendCodeCountdown(int sec) =>
      _t('Resend (${sec}s)', '重新发送（$sec秒）', '重新發送（$sec秒）');
  String get codeSent =>
      _t('Verification code sent to your email', '验证码已发送至您的邮箱', '驗證碼已發送至您的郵箱');
  String get mfaHint => _t('2FA code', '两步验证码', '二步驗證碼');

  String get settings => _t('Settings', '设置', '設定');
  String get subscription => _t('Subscription', '订阅', '訂閱');
  String get planCurrent => _t('Current plan', '当前套餐', '當前套餐');
  String get expiry => _t('Expires on', '到期时间', '到期時間');
  String get noExpiry => _t('—', '—', '—');
  String get remainingTraffic => _t('Traffic left', '剩余流量', '剩餘流量');
  String get usedTraffic => _t('Used', '已用', '已用');

  String get funcSettings => _t('Features', '功能设置', '功能設定');
  String get configManagement => _t('Config', '配置管理', '配置管理');
  String get configSub =>
      _t('Subscription URL & Token', '订阅链接与 Token', '訂閱鏈接與 Token');
  String get rechargeRecords => _t('Recharge history', '充值记录', '充值記錄');
  String get appDisguise => _t('App disguise', '应用伪装', '應用偽裝');
  String get appDisguiseTitle => _t('App disguise', '应用伪装', '應用偽裝');
  String get appDisguiseIntroTitle =>
      _t('Choose your disguise', '选择你的伪装外观', '選擇你的偽裝外觀');
  String get appDisguiseIntroBody => _t(
    'Only the launcher icon and name change. VPN connections and all data stay intact. Some launchers may take a few seconds to refresh.',
    '切换后仅桌面图标和名称会变，VPN 连接和所有数据完全保留。桌面刷新可能需要几秒。',
    '切換後僅桌面圖標和名稱會變，VPN 連線和所有資料完全保留。桌面刷新可能需要幾秒。',
  );
  String get appDisguiseUnsupported => _t(
    'Launcher disguise is only available on Android.',
    '应用伪装仅支持 Android。',
    '應用偽裝僅支援 Android。',
  );
  String get appDisguiseApplied => _t('Disguise updated', '伪装已切换', '偽裝已切換');
  String get appDisguiseFailed =>
      _t('Failed to update disguise', '伪装切换失败', '偽裝切換失敗');
  String get appDisguiseOriginal =>
      _t('Lingmao Accelerator (Original)', '灵猫加速器（原版）', '靈貓加速器（原版）');
  String get appDisguiseOriginalSub =>
      _t('Show the real app icon and name', '显示真实应用图标和名称', '顯示真實應用圖標和名稱');
  String get appDisguiseCalculator => _t('Calculator', '计算器', '計算器');
  String get appDisguiseCalculatorSub =>
      _t('Disguise as system calculator', '伪装为系统计算器', '偽裝為系統計算器');
  String get appDisguiseWeather => _t('Weather', '天气', '天氣');
  String get appDisguiseWeatherSub =>
      _t('Disguise as weather app', '伪装为天气应用', '偽裝為天氣應用');
  String get appDisguiseNotes => _t('Notes', '便签', '便簽');
  String get appDisguiseNotesSub =>
      _t('Disguise as notes app', '伪装为便签应用', '偽裝為便簽應用');
  String get appDisguiseSettings => _t('Settings', '设置', '設定');
  String get appDisguiseSettingsSub =>
      _t('Disguise as system settings', '伪装为系统设置', '偽裝為系統設定');
  String get appDisguiseAlbum => _t('Photos', '相册', '相冊');
  String get appDisguiseAlbumSub =>
      _t('Disguise as photo album', '伪装为相册应用', '偽裝為相冊應用');
  String get appDisguiseGallery => _t('Gallery', '图库', '圖庫');
  String get appDisguiseGallerySub =>
      _t('Disguise as gallery app', '伪装为图库应用', '偽裝為圖庫應用');
  String get appDisguisePhone => _t('Phone', '电话', '電話');
  String get appDisguisePhoneSub =>
      _t('Disguise as dialer app', '伪装为电话应用', '偽裝為電話應用');

  String get others => _t('Other', '其他设置', '其他設定');
  String get language => _t('Language', '语言', '語言');
  String get chooseLanguageTitle => _t('Language', '语言', '語言');

  String get helpCenter => _t('Help center', '帮助中心', '幫助中心');
  String get helpCenterSub =>
      _t('FAQ & troubleshooting', '使用教程与常见问题', '使用教學與常見問題');

  String get changePassword => _t('Change password', '修改密码', '修改密碼');
  String get changePasswordSub =>
      _t('Update password in app', '在 App 内直接修改密码', '在 App 內直接修改密碼');

  String get customerService => _t('Contact support', '联系客服', '聯繫客服');
  String get customerServiceSub =>
      _t('Chat on Telegram', '跳转 Telegram 纸飞机客服', '跳轉 Telegram 紙飛機客服');

  String get ticketManagement => _t('Tickets', '工单管理', '工單管理');
  String get ticketManagementSub =>
      _t('View, reply and close tickets', '查看、回复与关闭工单', '查看、回覆與關閉工單');

  String get oldPasswordHint => _t('Current password', '当前密码', '當前密碼');
  String get newPasswordHint => _t('New password', '新密码', '新密碼');
  String get confirmPasswordHint =>
      _t('Confirm new password', '确认新密码', '確認新密碼');
  String get confirmChangePassword => _t('Save', '确认修改', '確認修改');
  String get passwordFieldsRequired =>
      _t('Please fill in all fields', '请填写完整', '請填寫完整');
  String get passwordTooShort =>
      _t('Password must be at least 6 characters', '密码至少 6 位', '密碼至少 6 位');
  String get passwordMismatch =>
      _t('Passwords do not match', '两次密码不一致', '兩次密碼不一致');
  String get passwordChanged => _t('Password updated', '密码修改成功', '密碼修改成功');

  String get about => _t('About', '关于', '關於');
  String aboutSub(String ver) =>
      _t('Panlink VPN $ver', '灵猫加速器 $ver', '泛連VPN $ver');

  String get logout => _t('Sign out', '退出登录', '退出登入');

  String get currentPassword => _t('Password: ', '当前密码：', '當前密碼：');
  String get copyLink => _t('Copy link', '复制链接', '複製連結');

  String get changePasswordDialogTitle => _t('Change password', '修改密码', '修改密碼');
  String get changePasswordDialogBody => _t(
    'Password changes happen on your panel\'s profile page.\nCopy the link, open Safari/Chrome on this device (or desktop), log in again, then open the link.',
    '修改登录密码需在站点「资料修改」页完成。\n已为您准备编辑页链接，请复制后在浏览器中登录相同账号再打开链接。',
    '修改登入密碼需在站台「資料修改」頁完成。\n已為您準備編輯頁鏈接，請複製後在瀏覽器中登入相同帳號再打開鏈接。',
  );
  String get cancel => _t('Cancel', '取消', '取消');
  String get linkCopied => _t('Link copied', '链接已复制', '鏈接已複製');

  String get searchDocsHint => _t('Search…', '搜索文档…', '搜尋文檔…');

  List<HelpFaqEntry> faqPairs() => switch (lang) {
    UiLang.english => HelpFaqData.en,
    UiLang.traditionalChinese => HelpFaqData.tw,
    UiLang.simplifiedChinese => HelpFaqData.cn,
  };
}

class HelpFaqEntry {
  HelpFaqEntry({required this.category, required this.q, required this.a});
  final String category;
  final String q;
  final String a;
}

abstract class HelpFaqData {
  static final cn = [
    HelpFaqEntry(
      category: '网络问题',
      q: '节点没网，无法使用？',
      a: '请先确认账号未过期且有剩余流量；尝试更换线路或换节点；若多台设备共用，请关闭其他客户端后重试。仍不行请联系客服。',
    ),
    HelpFaqEntry(
      category: '网络问题',
      q: '速度很慢，怎么解决？',
      a: '建议优先连延迟较低的节点；避开高峰期；确认本地网络是否正常；若在 Wi‑Fi，可尝试 5GHz 或使用有线网。',
    ),
    HelpFaqEntry(
      category: '网络问题',
      q: '为什么近期所有 VPN 都卡顿？',
      a: '可能为运营商或出口拥塞、节点维护等。可多试几条线路并关注公告；问题持续时请向客服反馈具体地区与时间。',
    ),
    HelpFaqEntry(
      category: '网络问题',
      q: '为什么测试速度很低？',
      a: '测速结果受本地到此节点的路由影响，不代表国际总带宽；建议对比多个节点，并结合日常使用体感判断。',
    ),
    HelpFaqEntry(
      category: '网络问题',
      q: '什么是 Beta 节点？为什么推荐使用？',
      a: 'Beta 节点通常为新路线试运行，可能比正式线路延迟更低或更少拥堵，但可能存在不稳定；请视情况选用。',
    ),
    HelpFaqEntry(
      category: '账号问题',
      q: '为什么账号被封？',
      a: '常见原因是违反使用协议或多设备异常共用。请查收邮件/公告或直接联系客服确认原因与解封方式。',
    ),
    HelpFaqEntry(
      category: '账号问题',
      q: '忘记密码怎么办？',
      a: '请在站点登录页使用「找回密码」或发送重置邮件；若邮箱无法接收，请联系客服核验身份后处理。',
    ),
    HelpFaqEntry(
      category: '支付问题',
      q: '支持哪些支付方式？',
      a: '以您所在面板结账页显示的选项为准（如支付宝、微信、数字货币等）；若支付方式缺失，请联系管理员确认网关配置。',
    ),
  ];

  static final tw = [
    HelpFaqEntry(
      category: '網絡問題',
      q: '節點沒網，無法使用？',
      a: '請先確認帳號未過期且有剩餘流量；嘗試更換線路或換節點；若多台設備共用，請關閉其他客戶端後重試。仍不行請聯繫客服。',
    ),
    HelpFaqEntry(
      category: '網絡問題',
      q: '速度很慢，怎麼解決？',
      a: '建議優先連延遲較低的節點；避開高峰期；確認本地網絡是否正常；若在 Wi‑Fi，可嘗試 5GHz 或使用有線網。',
    ),
    HelpFaqEntry(
      category: '網絡問題',
      q: '為什麼近期所有 VPN 都卡頓？',
      a: '可能為運營商或出口擁塞、節點維護等。可多試幾條線路並關注公告；問題持續時請向客服反饋具體地區與時間。',
    ),
    HelpFaqEntry(
      category: '網絡問題',
      q: '為什麼測試速度很低？',
      a: '測速結果受本地到此節點的路由影響，不代表國際總頻寬；建議對比多個節點，並結合日常使用體感判斷。',
    ),
    HelpFaqEntry(
      category: '網絡問題',
      q: '什麼是 Beta 節點？為什麼推薦使用？',
      a: 'Beta 節點通常為新路線試運行，可能比正式線路延遲更低或更少擁堵，但可能存在不穩定；請視情況選用。',
    ),
    HelpFaqEntry(
      category: '帳號問題',
      q: '為什麼帳號被封？',
      a: '常見原因是違反使用協議或多設備異常共用。請查收郵件/公告或直接聯繫客服確認原因與解封方式。',
    ),
    HelpFaqEntry(
      category: '帳號問題',
      q: '忘記密碼怎麼辦？',
      a: '請在站台登入頁使用「找回密碼」或發送重置郵件；若信箱無法接收，請聯繫客服核驗身分後處理。',
    ),
    HelpFaqEntry(
      category: '支付問題',
      q: '支持哪些支付方式？',
      a: '以您所在面板结账页顯示的選項為準（如支付寶、微信、數字貨幣等）；若支付方式缺失，請聯繫管理員確認網關配置。',
    ),
  ];

  static final en = [
    HelpFaqEntry(
      category: 'Network',
      q: 'The node connects but no internet?',
      a: 'Check expiry and quota; switch nodes/lines and avoid running multiple sessions. If issues persist, contact support.',
    ),
    HelpFaqEntry(
      category: 'Network',
      q: 'Speed is slow—what can I do?',
      a: 'Pick a lower-latency node; try off-peak hours; verify Wi‑Fi or try another network.',
    ),
    HelpFaqEntry(
      category: 'Network',
      q: 'Why does everything lag lately?',
      a: 'Could be ISP routing or node maintenance—try multiple nodes and monitor announcements.',
    ),
    HelpFaqEntry(
      category: 'Network',
      q: 'Why does the speed test look low?',
      a: 'It reflects routing only to that node—not your full throughput. Compare nodes and judge by real-world use.',
    ),
    HelpFaqEntry(
      category: 'Network',
      q: 'What are Beta nodes?',
      a: 'They are trial routes and may perform better early on but might be unstable; use as needed.',
    ),
    HelpFaqEntry(
      category: 'Account',
      q: 'Why was my account banned?',
      a: 'Usually due to ToS breaches or abusive sharing—check mail/announcements or ask support.',
    ),
    HelpFaqEntry(
      category: 'Account',
      q: 'I forgot my password.',
      a: 'Use reset password on the panel login page or contact support to verify ownership.',
    ),
    HelpFaqEntry(
      category: 'Payment',
      q: 'Which payment methods are supported?',
      a: 'Whatever appears on checkout: Alipay, WeChat Pay, crypto, cards, etc.—it depends on the panel.',
    ),
  ];
}
