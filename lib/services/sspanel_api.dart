import '../config/app_config.dart';
import '../models/models.dart';
import 'sspanel_http_client.dart';
import 'sspanel_parsers.dart';

class SspanelApiException implements Exception {
  SspanelApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MfaRequiredException implements Exception {
  MfaRequiredException(this.message);
  final String message;
}

/// 对接 SSPanel / SSPanel-UIM（https://ceshi1.store）
/// 文档：https://marcosteam.gitbook.io/sspanel-api/yong-hu-ren-zheng
class SspanelApi {
  SspanelApi({SspanelHttpClient? http}) : _http = http ?? SspanelHttpClient();

  final SspanelHttpClient _http;

  String? _email;
  bool? _legacyApi;
  UserProfile? _profile;
  SubscriptionConfig? _config;
  bool _connected = false;
  String? _selectedNodeId;

  bool get isLoggedIn => _profile != null;
  UserProfile get profile => _profile!;
  bool get isConnected => _connected;
  String? get selectedNodeId => _selectedNodeId;
  SubscriptionConfig get config => _config!;

  Future<void> init() => _http.init();

  Future<bool> tryRestoreSession() async {
    await init();
    try {
      final response = await _http.get('/user');
      final html = _http.responseBody(response);
      if (SspanelParsers.sessionRejected(
        html,
        statusCode: response.statusCode,
        location: response.headers.value('location'),
      )) {
        return false;
      }
      _email ??= RegExp(r'[\w.+-]+@[\w.-]+\.\w+').firstMatch(html)?.group(0);
      if (_email == null) return false;
      await refreshUser();
      return isLoggedIn;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<bool> login(
    String email,
    String password, {
    String? code,
  }) async {
    final body = <String, String>{
      'email': email.trim(),
      'password': password,
      'remember_me': 'true', // UIM: remember_me === 'true' → 7 天 Cookie
    };
    if (code != null && code.isNotEmpty) {
      body['code'] = code;
    }

    final response = await _http.post('/auth/login', data: body);
    final json = _http.decodeJson(response);

    if (json != null) {
      final ret = json['ret'];
      final msg = json['msg']?.toString() ?? '';
      if (ret == 0) {
        throw SspanelApiException(msg.isNotEmpty ? msg : '登录失败');
      }
      if (msg.contains('二步') ||
          msg.contains('MFA') ||
          response.headers.value('hx-redirect')?.contains('mfa') == true) {
        throw MfaRequiredException(msg.isNotEmpty ? msg : '需要二步验证码');
      }
    }

    final redirect = response.headers.value('hx-redirect');
    final bool loginOk;
    if (json != null) {
      loginOk = json['ret'] == 1;
    } else {
      // SSPanel-UIM 成功时通常只返回 HX-Redirect + Set-Cookie，无 JSON
      loginOk = response.statusCode == 200 &&
          redirect != null &&
          !redirect.contains('mfa');
    }

    if (!loginOk) {
      throw SspanelApiException('登录失败，未获得有效会话');
    }

    _email = email.trim();

    // UIM 登录成功常带 HX-Redirect，先访问一次以写入完整会话 Cookie
    if (redirect != null && redirect.isNotEmpty) {
      final path = redirect.startsWith('http')
          ? Uri.parse(redirect).path
          : redirect.startsWith('/')
              ? redirect
              : '/$redirect';
      try {
        await _http.get(path);
      } catch (_) {}
    }

    // 预热用户区页面，确保后续 /user/server、/user/product 带上会话
    try {
      await _http.get('/user');
      await _http.get('/user/server');
      await _http.get('/user/product');
    } catch (_) {}

    try {
      await refreshUser();
    } on SspanelApiException catch (e) {
      throw SspanelApiException(
        '账号密码正确，但无法建立登录会话。\n'
        '若面板开启了 IP/设备绑定，请在后台关闭或保持同一网络后重试。\n'
        '详情：${e.message}',
      );
    } catch (e) {
      throw SspanelApiException('登录后加载资料失败：$e');
    }
    return true;
  }

  Future<void> logout() async {
    _profile = null;
    _config = null;
    _connected = false;
    _selectedNodeId = null;
    _email = null;
    _legacyApi = null;
    try {
      await _http.get('/auth/logout');
    } catch (_) {}
    try {
      await _http.get('/user/logout');
    } catch (_) {}
    await _http.clearCookies();
  }

  Future<void> refreshUser() async {
    if (_email == null) throw SspanelApiException('未登录');

    _legacyApi ??= await _probeLegacyApi();

    if (_legacyApi!) {
      await _loadLegacyUser();
    } else {
      await _loadUimUser();
    }
  }

  Future<bool> _probeLegacyApi() async {
    final r = await _http.get('/getuserinfo');
    return r.statusCode == 200 && _http.decodeJson(r) != null;
  }

  Future<void> _loadLegacyUser() async {
    final response = await _http.get('/getuserinfo');
    final json = _http.decodeJson(response);
    if (json == null || json['ret'] != 1) {
      throw SspanelApiException('获取用户信息失败');
    }
    final info = json['info'] as Map<String, dynamic>? ?? {};
    final user = info['user'] as Map<String, dynamic>? ?? {};
    final baseUrl = info['baseUrl']?.toString() ?? AppConfig.baseUrl;
    final subUrl = info['subUrl']?.toString() ?? '/sub/';
    final token = info['ssrSubToken']?.toString() ?? '';

    final used = _bytesToGb(user['u'] ?? user['d'] ?? 0);
    final total = _bytesToGb(user['transfer_enable'] ?? 0);
    final usedFromText = SspanelParsers.parseTrafficGb(user['lastUsedTraffic']?.toString() ?? '0');

    _profile = UserProfile(
      email: user['email']?.toString() ?? _email!,
      planName: 'LV.${user['class'] ?? 0}',
      usedTrafficGb: used > 0 ? used : usedFromText,
      totalTrafficGb: total > 0 ? total : used + SspanelParsers.parseTrafficGb(user['unusedTraffic']?.toString() ?? '0'),
      expireAt: _parseExpire(user['expire_in']?.toString()),
      checkedInToday: user['isAbleToCheckin'] == false,
      balance: double.tryParse(user['money']?.toString() ?? '') ?? 0,
    );

    final subscribeUrl = _joinSubscribeUrl(baseUrl, subUrl, token);
    _config = SubscriptionConfig(
      subscribeUrl: subscribeUrl,
      token: token,
      lastUpdated: DateTime.now(),
    );
  }

  Future<void> _loadUimUser() async {
    final response = await _http.get('/user');
    final html = _http.responseBody(response);
    if (SspanelParsers.sessionRejected(
      html,
      statusCode: response.statusCode,
      location: response.headers.value('location'),
    )) {
      throw SspanelApiException('登录会话未生效，请重试或检查面板 IP/设备绑定');
    }
    final subUrl = SspanelParsers.universalSubUrl(html);
    final baseProfile = SspanelParsers.userFromDashboardHtml(html, email: _email!);
    if (baseProfile == null) {
      throw SspanelApiException('解析用户信息失败');
    }
    var profile = baseProfile;

    try {
      final profilePage = await _http.get('/user/profile');
      final profileHtml = _http.responseBody(profilePage);
      final totalUsed = RegExp(
        r'账户累计使用流量[\s\S]*?mb-3">\s*([^<]+)',
      ).firstMatch(profileHtml)?.group(1)?.trim();
      if (totalUsed != null) {
        final usedGb = SspanelParsers.parseTrafficGb(totalUsed);
        profile = UserProfile(
          email: profile.email,
          planName: profile.planName,
          usedTrafficGb: usedGb,
          totalTrafficGb: profile.remainingTrafficGb + usedGb,
          expireAt: profile.expireAt,
          checkedInToday: profile.checkedInToday,
          balance: profile.balance,
        );
      }
    } catch (_) {}

    _profile = profile;
    final token = subUrl != null ? SspanelParsers.extractSubToken(subUrl) ?? '' : '';
    _config = SubscriptionConfig(
      subscribeUrl: subUrl ?? '${AppConfig.subscribeBase}/$token',
      token: token,
      lastUpdated: DateTime.now(),
    );
  }

  Future<bool> checkIn() async {
    final response = await _http.post('/user/checkin');
    final json = _http.decodeJson(response);
    if (json != null) {
      if (json['ret'] != 1) {
        throw SspanelApiException(json['msg']?.toString() ?? '签到失败');
      }
      await refreshUser();
      return true;
    }
    throw SspanelApiException('签到失败');
  }

  Future<void> toggleConnection() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _connected = !_connected;
  }

  void selectNode(String nodeId) => _selectedNodeId = nodeId;

  Future<List<VpnNode>> fetchNodes() async {
    if (_legacyApi == true) {
      return _fetchLegacyNodes();
    }
    return _fetchUimNodes();
  }

  Future<List<VpnNode>> _fetchLegacyNodes() async {
    final response = await _http.get('/getnodelist');
    final json = _http.decodeJson(response);
    if (json == null || json['ret'] != 1) return [];

    final nodeinfo = json['nodeinfo'] as Map<String, dynamic>? ?? {};
    final nodes = nodeinfo['nodes'] as List<dynamic>? ?? [];
    return nodes.map((n) {
      final m = n as Map<String, dynamic>;
      final online = m['online'] == 1 || m['online'] == true;
      return VpnNode(
        id: '${m['id']}',
        name: m['name']?.toString() ?? '节点',
        region: m['type']?.toString() ?? '',
        status: online ? NodeStatus.online : NodeStatus.offline,
        latencyMs: int.tryParse('${m['ping'] ?? m['latency']}'),
        loadPercent: int.tryParse('${m['load']}') ?? 0,
        shareLink: m['ss_url']?.toString() ?? m['node_connector']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<VpnNode>> _fetchUimNodes() async {
    final response = await _http.get('/user/server');
    final html = _http.responseBody(response);
    final nodes = SspanelParsers.nodesFromServerHtml(html);
    if (nodes.isNotEmpty) return nodes;
    if (SspanelParsers.looksLikeLoginPage(html)) return [];
    return nodes;
  }

  Future<void> updateSubscription({
    required String subscribeUrl,
    required String token,
  }) async {
    if (_legacyApi == true && token.isNotEmpty) {
      await _http.get('/getnewsubtoken');
      await refreshUser();
      return;
    }
    final response = await _http.post('/user/edit/url_reset');
    final json = _http.decodeJson(response);
    if (json != null && json['ret'] != 1) {
      throw SspanelApiException(json['msg']?.toString() ?? '重置订阅失败');
    }
    await refreshUser();
    if (subscribeUrl.isNotEmpty && _config != null) {
      _config = SubscriptionConfig(
        subscribeUrl: _config!.subscribeUrl,
        token: token.isNotEmpty ? token : _config!.token,
        lastUpdated: DateTime.now(),
      );
    }
  }

  Future<List<ShopPlan>> fetchPlans() async {
    if (_legacyApi == true) {
      final response = await _http.get('/getusershops');
      final json = _http.decodeJson(response);
      if (json != null && json['ret'] == 1) {
        final arr = json['arr'] as Map<String, dynamic>? ?? {};
        final shops = arr['shops'] as List<dynamic>? ?? [];
        return shops.map((s) {
          final m = s as Map<String, dynamic>;
          return ShopPlan(
            id: '${m['id']}',
            name: m['name']?.toString() ?? '',
            price: double.tryParse(m['price']?.toString() ?? '') ?? 0,
            trafficGb: int.tryParse('${m['bandwidth'] ?? 0}') ?? 0,
            durationDays: int.tryParse('${m['expire'] ?? 30}') ?? 30,
            description: m['content']?.toString() ?? '',
          );
        }).toList();
      }
    }
    final response = await _http.get('/user/product');
    final html = _http.responseBody(response);
    final plans = SspanelParsers.productsFromHtml(html);
    if (plans.isNotEmpty) return plans;

    if (SspanelParsers.looksLikeLoginPage(html)) {
      throw SspanelApiException('无法加载商品，请重新登录');
    }
    if (SspanelParsers.looksLikeProductPage(html)) {
      throw SspanelApiException('商品页解析失败，请稍后重试');
    }
    throw SspanelApiException('无法加载商品，请检查网络或重新登录');
  }

  Future<OrderResult> createProductOrder(String productId, {String coupon = ''}) async {
    final response = await _http.post(
      '/user/order/create',
      data: {
        'type': 'product',
        'product_id': productId,
        'coupon': coupon,
      },
    );
    final redirect = response.headers.value('hx-redirect') ??
        response.headers.value('location');
    if (redirect == null) {
      final json = _http.decodeJson(response);
      throw SspanelApiException(json?['msg']?.toString() ?? '创建订单失败');
    }
    final m = RegExp(r'/user/invoice/(\d+)/view').firstMatch(redirect);
    if (m == null) {
      throw SspanelApiException('无法解析账单 ID');
    }
    return OrderResult(invoiceId: m.group(1)!, redirectPath: redirect);
  }

  Future<List<PaymentMethod>> fetchPaymentMethods(String invoiceId) async {
    final response = await _http.get('/user/invoice/$invoiceId/view');
    var methods = SspanelParsers.paymentMethodsFromHtml(_http.responseBody(response));
    if (methods.isEmpty) {
      final money = await _http.get('/user/money');
      methods = SspanelParsers.paymentMethodsFromHtml(_http.responseBody(money));
    }
    return methods;
  }

  Future<CheckoutResult> checkoutOrder(String tradeNo, String methodId) async {
    return CheckoutResult(
      type: 1,
      data: paymentUrl(methodId, invoiceId: tradeNo),
    );
  }

  String paymentUrl(String gateway, {String? invoiceId}) {
    final base = '${AppConfig.baseUrl}/user/payment/purchase/$gateway';
    if (invoiceId == null) return base;
    return '$base?invoice_id=$invoiceId';
  }

  Future<bool> purchasePlan(String planId) async {
    await createProductOrder(planId);
    return true;
  }

  Future<List<RechargeRecord>> fetchRecharges() async {
    if (_legacyApi == true) {
      final response = await _http.post('/getChargeLog');
      final json = _http.decodeJson(response);
      if (json != null && json['ret'] == 1) {
        final codes = json['codes'] as List<dynamic>? ?? [];
        return codes.asMap().entries.map((e) {
          final m = e.value as Map<String, dynamic>;
          return RechargeRecord(
            id: '${e.key}',
            amount: double.tryParse('${m['number']}') ?? 0,
            method: m['code']?.toString() ?? '充值',
            createdAt: DateTime.tryParse(m['usedatetime']?.toString() ?? '') ?? DateTime.now(),
            status: '已完成',
          );
        }).toList();
      }
    }

    final response = await _http.post('/user/invoice/ajax');
    final json = _http.decodeJson(response);
    if (json == null) return [];
    final invoices = json['invoices'] as List<dynamic>? ?? [];
    return invoices.map((inv) {
      final m = inv as Map<String, dynamic>;
      return RechargeRecord(
        id: '${m['id']}',
        amount: double.tryParse('${m['price']}') ?? 0,
        method: m['type']?.toString() ?? '账单',
        createdAt: DateTime.tryParse(m['create_time']?.toString() ?? '') ?? DateTime.now(),
        status: m['status']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<SupportTicket>> fetchTickets() async {
    final response = await _http.get('/user/ticket');
    return SspanelParsers.ticketsFromHtml(_http.responseBody(response));
  }

  Future<List<Announcement>> fetchAnnouncements() async {
    final response = await _http.get('/user/announcement');
    final html = _http.responseBody(response);
    if (SspanelParsers.looksLikeLoginPage(html)) {
      throw SspanelApiException('无法加载公告，请重新登录');
    }
    return SspanelParsers.announcementsFromHtml(html);
  }

  Future<String> fetchSubscribeText() async {
    final url = _config?.subscribeUrl ?? '';
    if (url.isEmpty) throw SspanelApiException('无订阅链接，无法测速');
    final uri = Uri.parse(url);
    final path = uri.hasScheme
        ? '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
        : (url.startsWith('/') ? url : '/$url');
    final response = await _http.get(path, referer: '${AppConfig.baseUrl}/user/server');
    return _http.responseBody(response);
  }

  Future<bool> createTicket(String subject, String content) async {
    final response = await _http.post(
      '/user/ticket',
      data: {
        'title': subject,
        'comment': content,
        'markdown': content,
        'type': 'other',
      },
    );
    final json = _http.decodeJson(response);
    if (json != null && json['ret'] != 1) {
      throw SspanelApiException(json['msg']?.toString() ?? '提交失败');
    }
    return (response.statusCode ?? 500) < 400;
  }

  String importUrl(ImportClient client) {
    final base = _config?.subscribeUrl ?? '';
    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    switch (client) {
      case ImportClient.quantumultX:
        return '$normalized/quantumult%20x';
      case ImportClient.clash:
        return '$normalized/clash';
      case ImportClient.singBox:
        return '$normalized/singbox';
    }
  }

  double _bytesToGb(dynamic bytes) {
    final b = double.tryParse('$bytes') ?? 0;
    return b / 1024 / 1024 / 1024;
  }

  DateTime? _parseExpire(String? expireIn) {
    if (expireIn == null || expireIn.isEmpty) return null;
    return DateTime.tryParse(expireIn);
  }

  String _joinSubscribeUrl(String baseUrl, String subUrl, String token) {
    if (subUrl.startsWith('http')) {
      return subUrl.contains(token) ? subUrl : '$subUrl$token';
    }
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final path = subUrl.startsWith('/') ? subUrl : '/$subUrl';
    return '$base$path$token';
  }
}
