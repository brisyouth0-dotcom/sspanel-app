import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../config/app_config.dart';
import '../models/models.dart';
import '../utils/node_filters.dart';
import 'panel_exceptions.dart';
import 'xboard_http_client.dart';

/// 对接 Xboard / V2board 面板（https://user.panlink.site）
class XboardApi {
  XboardApi({XboardHttpClient? http}) : _http = http ?? XboardHttpClient();

  final XboardHttpClient _http;

  String? _email;
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
    if (_http.authData == null || _http.authData!.isEmpty) return false;
    try {
      await refreshUser();
      return isLoggedIn;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<bool> login(String email, String password, {String? code}) async {
    if (code != null && code.isNotEmpty) {
      throw MfaRequiredException('当前面板未开启二步验证，请留空验证码');
    }

    final response = await _http.post(
      '/passport/auth/login',
      data: {'email': email.trim(), 'password': password},
      auth: false,
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '登录失败');

    final data = json!['data'] as Map<String, dynamic>? ?? {};
    final authData = data['auth_data']?.toString();
    if (authData == null || authData.isEmpty) {
      throw PanelApiException('登录失败：未返回 auth_data');
    }

    await _http.setAuthData(authData);
    _email = email.trim();
    await refreshUser();
    return true;
  }

  /// 注册新账号，返回注册成功后是否已自动登录。
  /// [inviteCode] 选填，取决于面板是否开启邀请码强制验证。
  /// [emailCode] 邮箱验证码，面板开启邮件验证时必填。
  Future<bool> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
  }) async {
    final body = <String, dynamic>{'email': email.trim(), 'password': password};
    if (inviteCode != null && inviteCode.isNotEmpty) {
      body['invite_code'] = inviteCode.trim();
    }
    if (emailCode != null && emailCode.isNotEmpty) {
      body['email_code'] = emailCode.trim();
    }

    final response = await _http.post(
      '/passport/auth/register',
      data: body,
      auth: false,
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '注册失败');

    final data = json!['data'] as Map<String, dynamic>? ?? {};
    final authData = data['auth_data']?.toString();

    // 部分面板注册后直接返回 auth_data 并自动登录
    if (authData != null && authData.isNotEmpty) {
      await _http.setAuthData(authData);
      _email = email.trim();
      await refreshUser();
      return true;
    }

    // 部分面板需要邮件验证，不会立即返回 auth_data
    return false;
  }

  /// 发送邮箱验证码，[context] 为 "register" / "reset_password" 等场景。
  Future<void> sendEmailCode(
    String email, {
    String context = 'register',
  }) async {
    final response = await _http.post(
      '/passport/comm/sendEmailVerify',
      data: {'email': email.trim(), 'context': context},
      auth: false,
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '发送验证码失败');
  }

  Future<void> logout() async {
    await _http.setAuthData(null);
    _profile = null;
    _config = null;
    _connected = false;
    _selectedNodeId = null;
    _email = null;
  }

  Future<void> refreshUser() async {
    final infoRes = await _http.get('/user/info');
    final infoJson = _http.decodeJson(infoRes);
    _ensureSuccess(infoJson, fallback: '获取用户信息失败');
    final user = infoJson!['data'] as Map<String, dynamic>? ?? {};

    final subRes = await _http.get('/user/getSubscribe');
    final subJson = _http.decodeJson(subRes);
    _ensureSuccess(subJson, fallback: '获取订阅信息失败');
    final sub = subJson!['data'] as Map<String, dynamic>? ?? {};

    final plan =
        sub['plan'] as Map<String, dynamic>? ??
        user['plan'] as Map<String, dynamic>?;
    final planName = plan?['name']?.toString() ?? '未订阅';
    final hasSubscription = plan != null && planName != '未订阅';

    final transferEnable = _trafficToGb(
      sub['transfer_enable'] ?? user['transfer_enable'],
    );
    final usedGb = _trafficToGb(
      ((sub['u'] ?? user['u'] ?? 0) as num) +
          ((sub['d'] ?? user['d'] ?? 0) as num),
    );

    final expiredAt = hasSubscription
        ? _parseExpiryTimestamp(sub['expired_at'] ?? user['expired_at'])
        : null;

    _profile = UserProfile(
      email: user['email']?.toString() ?? _email ?? '',
      planName: planName,
      usedTrafficGb: usedGb,
      totalTrafficGb: transferEnable > 0 ? transferEnable : usedGb,
      expireAt: expiredAt,
      checkedInToday: true,
      balance: (user['balance'] as num? ?? 0) / 100,
    );

    final subscribeUrl = sub['subscribe_url']?.toString() ?? '';
    final token =
        sub['token']?.toString() ?? _tokenFromSubscribeUrl(subscribeUrl) ?? '';
    _config = SubscriptionConfig(
      subscribeUrl: subscribeUrl,
      token: token,
      lastUpdated: DateTime.now(),
    );
  }

  Future<bool> checkIn() async {
    await refreshUser();
    return true;
  }

  Future<void> toggleConnection() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _connected = !_connected;
  }

  void selectNode(String nodeId) => _selectedNodeId = nodeId;

  Future<List<VpnNode>> fetchNodes() async {
    Object? serverError;
    var serverNodes = <VpnNode>[];
    try {
      serverNodes = await _fetchServerNodes();
    } catch (e) {
      serverError = e;
    }

    final subscriptionNodes = await _fetchSubscriptionNodes();
    final merged = filterConnectableNodes(
      _mergeNodes(subscriptionNodes, serverNodes),
    );
    if (merged.isNotEmpty) return merged;

    if (serverError != null) {
      Error.throwWithStackTrace(serverError, StackTrace.current);
    }
    return [];
  }

  Future<List<VpnNode>> _fetchServerNodes() async {
    final response = await _http.get('/user/server/fetch');
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '获取节点失败');
    final list = _flattenServerList(_payloadData(json));

    var index = 0;
    return list.whereType<Map<String, dynamic>>().map((m) {
      index++;
      final rawId =
          m['id'] ?? m['name'] ?? m['show'] ?? m['remarks'] ?? m['host'];
      final id = 'server-$index-$rawId';
      final name =
          (m['name'] ??
                  m['show'] ??
                  m['remarks'] ??
                  m['server_name'] ??
                  m['server'] ??
                  m['host'])
              ?.toString() ??
          '节点';
      final online =
          m['is_online'] == 1 ||
          m['is_online'] == true ||
          m['online'] == 1 ||
          m['online'] == true;
      return VpnNode(
        id: id,
        name: name,
        region: _regionFromServerNode(m, name),
        status: online ? NodeStatus.online : NodeStatus.online,
        latencyMs: int.tryParse('${m['latency'] ?? m['ping'] ?? ''}'),
        loadPercent: int.tryParse('${m['load'] ?? 0}') ?? 0,
        shareLink: name,
      );
    }).toList();
  }

  List<dynamic> _flattenServerList(dynamic data) {
    final result = <Map<String, dynamic>>[];

    void walk(dynamic value) {
      if (value is List<dynamic>) {
        for (final item in value) {
          walk(item);
        }
        return;
      }
      if (value is Map<String, dynamic>) {
        final hasNodeName =
            value['name'] != null ||
            value['show'] != null ||
            value['remarks'] != null ||
            value['server_name'] != null ||
            value['server'] != null ||
            value['host'] != null;
        if (hasNodeName) {
          result.add(value);
          return;
        }
        for (final child in value.values) {
          walk(child);
        }
      }
    }

    walk(data);
    if (result.isNotEmpty) return result;
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      return data.values
          .expand((value) => value is List<dynamic> ? value : [value])
          .toList();
    }
    return [];
  }

  dynamic _payloadData(Map<String, dynamic>? json) {
    if (json == null) return null;
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return data['data'] ??
          data['items'] ??
          data['list'] ??
          data['servers'] ??
          data['nodes'] ??
          data;
    }
    return data ??
        json['servers'] ??
        json['nodes'] ??
        json['items'] ??
        json['list'];
  }

  String _regionFromServerNode(Map<String, dynamic> node, String name) {
    final tags = node['tags'];
    if (tags is List && tags.isNotEmpty) return tags.first.toString();
    final direct =
        node['country'] ??
        node['region'] ??
        node['area'] ??
        node['location'] ??
        node['group'];
    final text = direct?.toString();
    if (text != null && text.isNotEmpty) return text;
    return _regionFromNodeName(name);
  }

  Future<List<VpnNode>> _fetchSubscriptionNodes() async {
    try {
      final body = await fetchSubscribeText();
      return _nodesFromSubscriptionText(body);
    } catch (_) {
      return [];
    }
  }

  List<VpnNode> _nodesFromSubscriptionText(String body) {
    var text = body.trim();
    if (text.isEmpty) return [];

    if (!text.contains('://') && _looksBase64(text)) {
      try {
        text = utf8.decode(base64.decode(_normalizeBase64(text)));
      } catch (_) {}
    }

    final nodes = <VpnNode>[];
    final clashNodes = _nodesFromClashYaml(text);
    if (clashNodes.isNotEmpty) return clashNodes;

    var index = 0;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('://')) {
        continue;
      }
      final name = _nameFromShareLink(line);
      if (name == null || name.isEmpty) continue;
      index++;
      nodes.add(
        VpnNode(
          id: 'sub-$index-$name',
          name: name,
          region: _regionFromNodeName(name),
          status: NodeStatus.online,
          latencyMs: null,
          loadPercent: 0,
          shareLink: name,
        ),
      );
    }
    return nodes;
  }

  List<VpnNode> _nodesFromClashYaml(String text) {
    final proxiesStart = text.indexOf(
      RegExp(r'^proxies:\s*$', multiLine: true),
    );
    if (proxiesStart < 0) return [];
    final tail = text.substring(proxiesStart);
    final endMatch = RegExp(
      r'^(proxy-groups|rules|rule-providers|listeners):\s*$',
      multiLine: true,
    ).firstMatch(tail);
    final proxiesText = endMatch == null
        ? tail
        : tail.substring(0, endMatch.start);
    final names = <String>[];

    void addName(String? raw) {
      final name = _cleanYamlScalar(raw);
      if (name == null || name.isEmpty || isSubscriptionInfoNode(name)) {
        return;
      }
      names.add(name);
    }

    for (final m in RegExp(
      r'(?:^|\n)\s*-\s*\{[^}]*\bname\s*:\s*([^,\n}]+)',
      multiLine: true,
    ).allMatches(proxiesText)) {
      addName(m.group(1));
    }
    for (final m in RegExp(
      r'(?:^|\n)\s*-\s*name\s*:\s*(.+)$',
      multiLine: true,
    ).allMatches(proxiesText)) {
      addName(m.group(1));
    }

    var index = 0;
    return names.map((name) {
      index++;
      return VpnNode(
        id: 'clash-$index-$name',
        name: name,
        region: _regionFromNodeName(name),
        status: NodeStatus.online,
        latencyMs: null,
        loadPercent: 0,
        shareLink: name,
      );
    }).toList();
  }

  String? _cleanYamlScalar(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.endsWith(',')) {
      value = value.substring(0, value.length - 1).trim();
    }
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value.replaceAll(r'\"', '"').replaceAll(r"\'", "'").trim();
  }

  List<VpnNode> _mergeNodes(List<VpnNode> primary, List<VpnNode> fallback) {
    final result = <VpnNode>[];
    final seenIds = <String>{};
    final primaryByName = _groupNodesByName(primary);
    final fallbackByName = _groupNodesByName(fallback);
    final keys = <String>{...primaryByName.keys, ...fallbackByName.keys};

    for (final key in keys) {
      final primaryGroup = primaryByName[key] ?? const <VpnNode>[];
      final fallbackGroup = fallbackByName[key] ?? const <VpnNode>[];
      final targetCount = primaryGroup.length > fallbackGroup.length
          ? primaryGroup.length
          : fallbackGroup.length;
      var addedForName = 0;

      for (final node in primaryGroup) {
        if (seenIds.add(node.id)) {
          result.add(node);
          addedForName++;
        }
      }

      for (final node in fallbackGroup) {
        if (addedForName >= targetCount) break;
        if (seenIds.add(node.id)) {
          result.add(node);
          addedForName++;
        }
      }
    }
    return result;
  }

  Map<String, List<VpnNode>> _groupNodesByName(List<VpnNode> nodes) {
    final grouped = <String, List<VpnNode>>{};
    for (final node in nodes) {
      final key = node.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(node);
    }
    return grouped;
  }

  String? _nameFromShareLink(String line) {
    if (line.startsWith('vmess://')) return _vmessName(line);
    final hash = line.indexOf('#');
    if (hash >= 0 && hash < line.length - 1) {
      return Uri.decodeComponent(line.substring(hash + 1)).trim();
    }
    final uri = Uri.tryParse(line);
    return uri?.host.isNotEmpty == true ? uri!.host : null;
  }

  String? _vmessName(String line) {
    try {
      final payload = line.substring('vmess://'.length).split('#').first;
      final jsonText = utf8.decode(base64.decode(_normalizeBase64(payload)));
      final json = jsonDecode(jsonText) as Map<String, dynamic>;
      return (json['ps'] ?? json['remark'] ?? json['add'])?.toString().trim();
    } catch (_) {
      return null;
    }
  }

  String _regionFromNodeName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'[\u4e00-\u9fff]{2,}|[A-Z]{2,}').firstMatch(trimmed);
    if (match != null) return match.group(0) ?? '';
    final chars = trimmed.runes.take(2).toList();
    return String.fromCharCodes(chars);
  }

  bool _looksBase64(String s) {
    final compact = s.replaceAll(RegExp(r'\s+'), '');
    return compact.length % 4 == 0 &&
        RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact);
  }

  String _normalizeBase64(String s) {
    var out = s
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    while (out.length % 4 != 0) {
      out += '=';
    }
    return out;
  }

  Future<void> updateSubscription({
    required String subscribeUrl,
    required String token,
  }) async {
    final response = await _http.get('/user/resetSecurity');
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '重置订阅失败');
    await refreshUser();
  }

  Future<List<ShopPlan>> fetchPlans() async {
    final response = await _http.get('/user/plan/fetch');
    final json = _http.decodeJson(response);
    if (json == null || json['status'] != 'success') {
      return _fetchGuestPlans();
    }
    final list = json['data'] as List<dynamic>? ?? [];
    return list.map(_planFromJson).toList();
  }

  Future<List<ShopPlan>> _fetchGuestPlans() async {
    final response = await _http.get('/guest/plan/fetch', auth: false);
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '获取套餐失败');
    final list = json!['data'] as List<dynamic>? ?? [];
    return list.map(_planFromJson).toList();
  }

  ShopPlan _planFromJson(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final resetMethod = (m['reset_traffic_method'] as num?)?.toInt() ?? 1;
    final periods = _periodsFromPlanJson(m);
    final onetime = _priceNum(m['onetime_price']);
    final month = _priceNum(m['month_price']);

    final isPermanent =
        resetMethod == 2 ||
        (onetime != null && onetime > 0 && (month == null || month <= 0));
    final kind = isPermanent ? ProductKind.permanent : ProductKind.periodic;

    final fallbackPeriod = periods.isNotEmpty
        ? periods.first
        : PlanPeriod(
            id: isPermanent ? 'onetime_price' : 'month_price',
            label: isPermanent ? '永久' : '月付',
            price: ((isPermanent ? onetime : month) ?? onetime ?? 0) / 100,
          );

    return ShopPlan(
      id: '${m['id']}',
      name: m['name']?.toString() ?? '',
      price: fallbackPeriod.price,
      trafficGb: (m['transfer_enable'] as num?)?.toInt() ?? 0,
      durationDays: isPermanent ? 0 : 30,
      description: m['content']?.toString() ?? '',
      kind: kind,
      orderPeriod: fallbackPeriod.id,
      features: (m['content']?.toString() ?? '')
          .split('\n')
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      periods: periods,
    );
  }

  List<PlanPeriod> _periodsFromPlanJson(Map<String, dynamic> m) {
    const fields = [
      ('month_price', '月付', null),
      ('quarter_price', '季付', '省 5%'),
      ('half_year_price', '半年付', null),
      ('year_price', '年付', '省 16%'),
      ('two_year_price', '两年付', null),
      ('three_year_price', '三年付', null),
      ('onetime_price', '永久', null),
    ];

    final periods = <PlanPeriod>[];
    for (final field in fields) {
      final raw = _priceNum(m[field.$1]);
      if (raw == null || raw <= 0) continue;
      periods.add(
        PlanPeriod(
          id: field.$1,
          label: field.$2,
          price: raw / 100,
          badge: field.$3,
        ),
      );
    }
    return periods;
  }

  num? _priceNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  Future<OrderResult> createProductOrder(
    String productId, {
    String period = 'month_price',
    String coupon = '',
  }) async {
    final body = <String, dynamic>{
      'plan_id': int.tryParse(productId) ?? productId,
      'period': period,
    };
    if (coupon.isNotEmpty) body['coupon_code'] = coupon;

    final response = await _http.post('/user/order/save', data: body);
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '创建订单失败');
    final data = json!['data'];
    final tradeNo = data is Map
        ? data['trade_no']?.toString()
        : data?.toString();
    if (tradeNo == null || tradeNo.isEmpty) {
      throw PanelApiException('创建订单失败：无 trade_no');
    }
    return OrderResult(
      invoiceId: tradeNo,
      redirectPath: '/user/order/$tradeNo',
    );
  }

  Future<List<PaymentMethod>> fetchPaymentMethods(String invoiceId) async {
    final response = await _http.get(
      '/user/order/getPaymentMethod',
      query: {'trade_no': invoiceId},
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '获取支付方式失败');
    final list = json!['data'] as List<dynamic>? ?? [];

    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = m['id']?.toString() ?? m['payment']?.toString() ?? '';
      final name = m['name']?.toString() ?? id;
      return PaymentMethod(id: id, name: name, type: PaymentGatewayType.other);
    }).toList();
  }

  String paymentUrl(String gateway, {String? invoiceId}) {
    final base = '${AppConfig.baseUrl}/api/v1/user/order/checkout';
    if (invoiceId == null) return base;
    return '$base?trade_no=$invoiceId&method=$gateway';
  }

  Future<bool> purchasePlan(String planId) async {
    await createProductOrder(planId);
    return true;
  }

  Future<List<RechargeRecord>> fetchRecharges() async {
    final response = await _http.get('/user/order/fetch');
    final json = _http.decodeJson(response);
    if (json == null || json['status'] != 'success') return [];
    final list = json['data'] as List<dynamic>? ?? [];

    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final statusCode = m['status'] as num? ?? 0;
      final status = switch (statusCode) {
        0 => '待支付',
        1 => '开通中',
        2 => '已取消',
        3 => '已完成',
        _ => '$statusCode',
      };
      return RechargeRecord(
        id: '${m['trade_no'] ?? m['id']}',
        amount: (m['total_amount'] as num? ?? m['price'] as num? ?? 0) / 100,
        method: m['payment']?.toString() ?? '订单',
        createdAt: _parseTimestamp(m['created_at']),
        status: status,
      );
    }).toList();
  }

  Future<List<SupportTicket>> fetchTickets() async {
    final response = await _http.get('/user/ticket/fetch');
    final json = _http.decodeJson(response);
    if (json == null || json['status'] != 'success') return [];
    final list = json['data'] as List<dynamic>? ?? [];
    return list.map(_ticketFromListJson).toList();
  }

  Future<SupportTicket> fetchTicketDetail(String id) async {
    final response = await _http.get('/user/ticket/fetch', query: {'id': id});
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '获取工单详情失败');
    final data = json!['data'] as Map<String, dynamic>? ?? {};
    return _ticketFromDetailJson(data);
  }

  Future<bool> replyTicket(String id, String message) async {
    final ticketId = int.tryParse(id) ?? id;
    final response = await _http.post(
      '/user/ticket/reply',
      data: {'id': ticketId, 'ticket_id': ticketId, 'message': message},
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '回复失败');
    return true;
  }

  Future<bool> closeTicket(String id) async {
    final response = await _http.post(
      '/user/ticket/close',
      data: {'id': int.tryParse(id) ?? id},
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '关闭工单失败');
    return true;
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final response = await _http.post(
      '/user/changePassword',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '修改密码失败');
  }

  Future<String?> fetchTelegramUrl() async {
    try {
      final response = await _http.get('/user/telegram/getBotInfo');
      final json = _http.decodeJson(response);
      if (json != null && json['status'] == 'success') {
        final username = json['data']?['username']?.toString();
        if (username != null && username.isNotEmpty) {
          return 'https://t.me/$username';
        }
      }
    } catch (_) {}
    return AppConfig.telegramSupportUrl;
  }

  SupportTicket _ticketFromListJson(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    return SupportTicket(
      id: '${m['id']}',
      subject: m['subject']?.toString() ?? '工单',
      status: _ticketStatus(m),
      updatedAt: _parseTimestamp(m['updated_at'] ?? m['created_at']),
      preview: m['message']?.toString() ?? '',
      closed: (m['status'] as num? ?? 0) != 0,
    );
  }

  SupportTicket _ticketFromDetailJson(Map<String, dynamic> m) {
    final messagesRaw = m['message'] as List<dynamic>? ?? [];
    final messages = messagesRaw.map((raw) {
      final msg = raw as Map<String, dynamic>;
      return TicketMessage(
        id: '${msg['id']}',
        message: msg['message']?.toString() ?? '',
        isMe: msg['is_me'] == true || msg['is_me'] == 1,
        createdAt: _parseTimestamp(msg['created_at']),
      );
    }).toList();
    final preview = messages.isNotEmpty
        ? messages.last.message
        : m['message']?.toString() ?? '';
    return SupportTicket(
      id: '${m['id']}',
      subject: m['subject']?.toString() ?? '工单',
      status: _ticketStatus(m),
      updatedAt: _parseTimestamp(m['updated_at'] ?? m['created_at']),
      preview: preview,
      messages: messages,
      closed: (m['status'] as num? ?? 0) != 0,
    );
  }

  TicketStatus _ticketStatus(Map<String, dynamic> m) {
    if ((m['status'] as num? ?? 0) != 0) return TicketStatus.closed;
    final reply = m['reply_status'] as num? ?? 0;
    if (reply != 0) return TicketStatus.replied;
    return TicketStatus.open;
  }

  Future<List<Announcement>> fetchAnnouncements() async {
    final response = await _http.get('/user/notice/fetch');
    final json = _http.decodeJson(response);
    if (json == null) return [];

    final status = json['status']?.toString();
    if (status != null && status != 'success') return [];

    final list = _noticeListFromJson(json['data']);
    return list
        .map(_announcementFromNoticeJson)
        .where((ann) => ann.content.trim().isNotEmpty)
        .toList();
  }

  List<dynamic> _noticeListFromJson(dynamic data) {
    return switch (data) {
      List<dynamic> items => items,
      Map<String, dynamic> m =>
        (m['data'] as List<dynamic>?) ??
            (m['items'] as List<dynamic>?) ??
            (m['list'] as List<dynamic>?) ??
            const <dynamic>[],
      _ => const <dynamic>[],
    };
  }

  Announcement _announcementFromNoticeJson(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final title = m['title']?.toString() ?? '';
    final content = _plainNoticeText(
      m['content']?.toString() ??
          m['message']?.toString() ??
          m['txt']?.toString() ??
          '',
    );
    final merged = [
      if (title.isNotEmpty) title,
      if (content.isNotEmpty && content != title) content,
    ].join('\n');
    return Announcement(
      id: '${m['id']}',
      content: merged,
      publishedAt: _parseTimestamp(
        m['created_at'] ?? m['updated_at'] ?? m['created_time'],
      ),
    );
  }

  String _plainNoticeText(String text) {
    if (!text.contains('<')) return text.trim();
    return html_parser.parse(text).body?.text.trim() ?? text.trim();
  }

  /// 用于 iOS 导出到 Shadowrocket / Stash 的订阅链接
  String? get clashSubscribeImportUrl {
    final candidates = _subscribeCandidates(flag: 'clash');
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<String> fetchSubscribeText() async {
    final candidates = _subscribeCandidates(flag: 'clash');
    if (candidates.isEmpty) {
      throw PanelApiException('无订阅链接，无法获取配置');
    }

    PanelApiException? lastError;
    for (final url in candidates) {
      try {
        final body = await _http.fetchSubscribeContent(url);
        _validateClashSubscribe(body);
        return body;
      } on PanelApiException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = PanelApiException('拉取订阅失败：$e');
      }
    }
    throw lastError ?? PanelApiException('无法获取 Clash 订阅配置');
  }

  List<String> _subscribeCandidates({required String flag}) {
    final subscribeUrl = _config?.subscribeUrl ?? '';
    final token = _config?.token ?? _tokenFromSubscribeUrl(subscribeUrl) ?? '';
    final seen = <String>{};
    final out = <String>[];

    void add(String? url) {
      if (url == null || url.isEmpty || !seen.add(url)) return;
      out.add(url);
    }

    // 1. 标准 API 不带 flag（灵猫面板 flag=clash 会返回空 proxies 规则模板）
    if (token.isNotEmpty) {
      add(_buildSubscribeUrl(AppConfig.subscribeBase, token: token));
    }

    // 2. 带 flag 的 API（部分面板需要）
    if (token.isNotEmpty && flag.isNotEmpty) {
      add(
        _buildSubscribeUrl(AppConfig.subscribeBase, token: token, flag: flag),
      );
    }

    // 3. 面板 subscribe_url 仅尝试 API 形态（/link/ 在此面板返回网页）
    if (subscribeUrl.isNotEmpty &&
        subscribeUrl.contains('/api/v1/client/subscribe')) {
      add(
        _buildSubscribeUrl(subscribeUrl, token: token.isEmpty ? null : token),
      );
      if (flag.isNotEmpty) {
        add(
          _buildSubscribeUrl(
            subscribeUrl,
            token: token.isEmpty ? null : token,
            flag: flag,
          ),
        );
      }
    }

    return out;
  }

  String _buildSubscribeUrl(String base, {String? token, String? flag}) {
    final uri = Uri.parse(base);
    final params = Map<String, String>.from(uri.queryParameters);
    if (token != null && token.isNotEmpty && !params.containsKey('token')) {
      params['token'] = token;
    }
    if (flag != null && flag.isNotEmpty) {
      params['flag'] = flag;
    }
    return uri.replace(queryParameters: params).toString();
  }

  void _validateClashSubscribe(String body) {
    final text = body.trimLeft();
    final lower = text.toLowerCase();
    if (lower.startsWith('<!doctype html') ||
        lower.startsWith('<html') ||
        lower.contains('<div id="root"')) {
      throw PanelApiException('订阅链接返回的是网页，不是 Clash 配置');
    }
    if (!text.contains('proxies:') && !text.contains('proxy-groups:')) {
      throw PanelApiException('订阅内容不是有效的 Clash 配置');
    }
    final proxiesStart = text.indexOf(
      RegExp(r'^proxies:\s*$', multiLine: true),
    );
    if (proxiesStart < 0) {
      throw PanelApiException('订阅配置缺少 proxies 节点列表');
    }
    final tail = text.substring(proxiesStart);
    final hasProxyEntry = RegExp(
      r'-\s*(?:name\s*:|(?:\{[^}]*\bname\s*:))',
      multiLine: true,
    ).hasMatch(tail);
    if (!hasProxyEntry) {
      throw PanelApiException('订阅中没有可用节点（proxies 为空）');
    }
  }

  Future<bool> createTicket(String subject, String content) async {
    final response = await _http.post(
      '/user/ticket/save',
      data: {'subject': subject, 'level': 1, 'message': content},
    );
    final json = _http.decodeJson(response);
    _ensureSuccess(json, fallback: '提交工单失败');
    return true;
  }

  String importUrl(ImportClient client) {
    final flag = switch (client) {
      ImportClient.clash => 'clash',
      ImportClient.singBox => 'singbox',
      ImportClient.quantumultX => 'quantumult%20x',
    };
    final candidates = _subscribeCandidates(flag: flag);
    if (candidates.isNotEmpty) return candidates.first;
    return '';
  }

  String get clashSubscribeUrl => importUrl(ImportClient.clash);

  String? _tokenFromSubscribeUrl(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final queryToken = uri.queryParameters['token'];
    if (queryToken != null && queryToken.isNotEmpty) return queryToken;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments[segments.length - 2] == 'link') {
      return segments.last;
    }
    return null;
  }

  void _ensureSuccess(Map<String, dynamic>? json, {required String fallback}) {
    if (json == null) throw PanelApiException(fallback);
    final status = json['status']?.toString();
    final ret = json['ret'];
    final ok =
        (status == null && json.containsKey('data')) ||
        status == 'success' ||
        status == 'ok' ||
        status == '1' ||
        ret == 1 ||
        ret == true;
    if (!ok) {
      throw PanelApiException(json['message']?.toString() ?? fallback);
    }
  }

  double _trafficToGb(dynamic value) {
    if (value == null) return 0;
    final n = (value is num)
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    if (n > 1024 * 1024) return n / 1024 / 1024 / 1024;
    return n;
  }

  DateTime? _parseExpiryTimestamp(dynamic ts) {
    if (ts == null || ts == '' || ts == 0) return null;
    if (ts is num) {
      if (ts == 0) return null;
      final sec = ts > 1e12 ? ts / 1000 : ts;
      if (sec <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
    }
    return DateTime.tryParse(ts.toString());
  }

  DateTime _parseTimestamp(dynamic ts) {
    return _parseExpiryTimestamp(ts) ?? DateTime.now();
  }
}
