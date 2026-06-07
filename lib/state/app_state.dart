import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../l10n/ui_lang.dart';
import '../l10n/ui_strings.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_disguise_bridge.dart';
import '../services/menu_bar_bridge.dart';
import '../services/mihomo_traffic_monitor.dart';
import '../services/ios_export_bridge.dart';
import '../services/mihomo_service.dart';
import '../services/node_speed_test.dart';
import '../services/panel_exceptions.dart';
import '../services/system_proxy_bridge.dart';
import '../services/read_state_store.dart';
import '../services/vpn_bridge.dart';
import '../utils/user_messages.dart';

class AppState extends ChangeNotifier {
  static const _prefUiLangKey = 'ui_lang';
  static const _prefAppDisguiseKey = 'app_disguise';

  AppState({ApiService? api, MihomoService? mihomo})
    : _api = api ?? ApiService(),
      _mihomo = mihomo ?? MihomoService();

  final ApiService _api;
  final MihomoService _mihomo;
  final ReadStateStore _readState = ReadStateStore();
  MihomoTrafficMonitor? _trafficMonitor;
  DateTime? _lastTrafficNotify;
  bool _initialized = false;
  int _loadingCount = 0;
  String? _loadingMessage;

  String? _error;
  List<VpnNode>? _nodes;
  List<ShopPlan>? _plans;
  List<RechargeRecord>? _recharges;
  List<SupportTicket>? _tickets;
  List<PaymentMethod>? _paymentMethods;
  List<Announcement>? _announcements;
  Map<String, int>? _nodePingMs;
  bool _speedTesting = false;
  bool _connecting = false;
  String? _nodeSearch;
  int _shellTabIndex = 0;

  String? _sessionPassword;
  UiLang _uiLang = UiLang.simplifiedChinese;
  AppDisguiseOption _appDisguiseOption = AppDisguiseOption.original;

  int _trafficUpBps = 0;
  int _trafficDownBps = 0;
  bool _systemProxyEnabled = false;
  String _proxyMode = 'rule';

  bool get mihomoSupported => _mihomo.isSupported;
  bool get systemProxySupported => SystemProxyBridge.supported;
  int get trafficUpBps => _trafficUpBps;
  int get trafficDownBps => _trafficDownBps;
  bool get systemProxyEnabled => _systemProxyEnabled;
  String get proxyMode => _proxyMode;

  bool get initialized => _initialized;
  bool get isLoggedIn => _api.isLoggedIn;
  int get shellTabIndex => _shellTabIndex;
  String get nodeSearch => _nodeSearch ?? '';
  bool get loading => _loadingCount > 0;
  bool get connecting => _connecting;
  String get loadingMessage => _loadingMessage ?? '请稍候…';
  String? get error => _error;
  UserProfile? get profile => _api.isLoggedIn ? _api.profile : null;
  bool get isConnected => _api.isConnected;
  String? get selectedNodeId => _api.selectedNodeId;
  SubscriptionConfig? get config => _api.isLoggedIn ? _api.config : null;
  List<VpnNode>? get nodes => _nodes;
  List<ShopPlan>? get plans => _plans;
  List<RechargeRecord>? get recharges => _recharges;
  List<SupportTicket>? get tickets => _tickets;
  List<PaymentMethod>? get paymentMethods => _paymentMethods;
  List<Announcement>? get announcements => _announcements;
  bool get speedTesting => _speedTesting;
  Map<String, int>? get nodePingMs => _nodePingMs;

  int? pingMsForNode(String nodeId) => _nodePingMs?[nodeId];

  UiLang get uiLang => _uiLang;
  AppDisguiseOption get appDisguiseOption => _appDisguiseOption;
  bool get appDisguiseSupported => AppDisguiseBridge.supported;

  UiStrings get strings => UiStrings(_uiLang);

  String? get sessionPassword => _sessionPassword;

  String? _telegramUrl;
  String? get telegramUrl => _telegramUrl;

  Set<String> _readAnnouncementIds = {};
  Set<String> _readTicketIds = {};

  Set<String> get readAnnouncementIds => _readAnnouncementIds;

  int get unreadAnnouncementCount {
    final list = _announcements;
    if (list == null || list.isEmpty) return 0;
    return list.where((a) => !_readAnnouncementIds.contains(a.id)).length;
  }

  int get unreadTicketCount {
    final list = _tickets;
    if (list == null || list.isEmpty) return 0;
    return list
        .where(
          (t) =>
              t.status == TicketStatus.replied &&
              !_readTicketIds.contains(t.id),
        )
        .length;
  }

  List<RechargeRecord> get pendingRecharges =>
      _recharges?.where((r) => r.status == '待支付').toList() ?? const [];

  RechargeRecord? get firstPendingRecharge =>
      pendingRecharges.isNotEmpty ? pendingRecharges.first : null;

  Future<void> setUiLang(UiLang lang) async {
    _uiLang = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUiLangKey, lang.encode());
    } catch (_) {}
  }

  Future<void> loadUiLangPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _uiLang = UiLang.decode(prefs.getString(_prefUiLangKey));
      _appDisguiseOption = AppDisguiseOption.fromId(
        prefs.getString(_prefAppDisguiseKey),
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> setAppDisguiseOption(AppDisguiseOption option) async {
    final applied = await AppDisguiseBridge.apply(option);
    if (!applied && AppDisguiseBridge.supported) return false;
    _appDisguiseOption = option;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefAppDisguiseKey, option.id);
    } catch (_) {}
    return applied || !AppDisguiseBridge.supported;
  }

  Future<void> setProxyMode(String mode) async {
    if (!mihomoSupported || !isConnected) return;
    try {
      await _mihomo.setMode(mode);
      _proxyMode = mode;
      notifyListeners();
      await _syncMenuBar();
    } catch (_) {}
  }

  Future<void> setSystemProxy(bool enabled) async {
    if (!systemProxySupported) return;
    if (enabled) {
      _systemProxyEnabled = await SystemProxyBridge.enable(
        port: AppConfig.mihomoMixedPort,
      );
    } else {
      await SystemProxyBridge.disable();
      _systemProxyEnabled = false;
    }
    notifyListeners();
  }

  void _startTrafficMonitor() {
    if (!mihomoSupported || (!kIsWeb && Platform.isIOS)) return;
    _stopTrafficMonitor();
    final monitor = MihomoTrafficMonitor();
    _trafficMonitor = monitor;
    unawaited(
      monitor.start((up, down) {
        _trafficUpBps = up;
        _trafficDownBps = down;
        final now = DateTime.now();
        if (_lastTrafficNotify == null ||
            now.difference(_lastTrafficNotify!) >=
                const Duration(milliseconds: 450)) {
          _lastTrafficNotify = now;
          notifyListeners();
        }
      }),
    );
  }

  void _stopTrafficMonitor() {
    _trafficMonitor?.stop();
    _trafficMonitor = null;
    _trafficUpBps = 0;
    _trafficDownBps = 0;
    _lastTrafficNotify = null;
  }

  Future<void> _onVpnConnected() async {
    _startTrafficMonitor();
    if (systemProxySupported) {
      await setSystemProxy(true);
    }
    if (mihomoSupported) {
      try {
        _proxyMode = await _mihomo.getMode();
      } catch (_) {}
    }
    await _syncMenuBar();
  }

  Future<void> _onVpnDisconnected() async {
    _stopTrafficMonitor();
    if (systemProxySupported) {
      await setSystemProxy(false);
    }
    await _syncMenuBar();
  }

  /// 强杀 App 后系统 VPN 可能仍显示「连接中」，启动时对齐并刷新 UI
  Future<void> _reconcileAndroidVpnState() async {
    final active = await VpnBridge.reconcile();
    if (!active && _api.isConnected) {
      await _mihomo.disconnect();
      await _api.toggleConnection();
      _stopTrafficMonitor();
      notifyListeners();
    }
  }

  Future<void> _syncMenuBar() async {
    final node = nodeById(_api.selectedNodeId);
    final menuNodes = (_nodes ?? [])
        .map((n) => {'id': n.id, 'name': n.name})
        .toList();
    await MenuBarBridge.updateMenu(
      connected: isConnected,
      nodeName: node?.name,
      mode: _proxyMode,
      nodes: menuNodes,
      selectedNodeId: _api.selectedNodeId,
    );
  }

  List<VpnNode> get filteredNodes {
    final list = _nodes;
    if (list == null) return [];
    final q = nodeSearch.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((n) {
      final text = '${n.name} ${n.region} ${n.shareLink}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  List<ShopPlan> plansByKind(ProductKind kind) {
    return _plans?.where((p) => p.kind == kind).toList() ?? [];
  }

  void setNodeSearch(String value) {
    if (_nodeSearch == value) return;
    _nodeSearch = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _beginLoading(String message) {
    _loadingCount++;
    _loadingMessage = message;
    notifyListeners();
  }

  void _endLoading() {
    if (_loadingCount > 0) _loadingCount--;
    if (_loadingCount <= 0) {
      _loadingCount = 0;
      _loadingMessage = null;
    }
    notifyListeners();
  }

  Future<T> runWithLoading<T>(
    String message,
    Future<T> Function() action,
  ) async {
    _beginLoading(message);
    try {
      return await action();
    } finally {
      _endLoading();
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    MenuBarBridge.install((action, [args]) async {
      switch (action) {
        case 'toggleConnection':
          await toggleConnection();
        case 'setMode':
          final mode = args?['mode']?.toString();
          if (mode != null && mode.isNotEmpty) {
            await setProxyMode(mode);
          }
        case 'selectNode':
          final nodeId = args?['nodeId']?.toString();
          if (nodeId != null && nodeId.isNotEmpty) {
            selectNode(nodeId);
            await _syncMenuBar();
          }
      }
    });
    await loadUiLangPrefs();
    await _loadReadState();
    if (!kIsWeb && Platform.isAndroid) {
      await _reconcileAndroidVpnState();
    }
    if (_mihomo.isSupported &&
        (kIsWeb || (!Platform.isAndroid && !Platform.isIOS))) {
      // 桌面端后台启动 mihomo，避免阻塞首屏
      unawaited(_mihomo.bootstrap().catchError((_) {}));
    }
    await runWithLoading('正在连接服务器…', () async {
      await _api.init();
      final restored = await _api.tryRestoreSession();
      if (restored) {
        _beginLoading('正在恢复数据…');
        try {
          await Future.wait([
            loadPlans(force: true, quiet: true),
            loadNodes(quiet: true),
            _loadTelegramUrl(),
          ]);
        } finally {
          _endLoading();
        }
      }
      _initialized = true;
      await _syncMenuBar();
      notifyListeners();
    });
  }

  void goToShellTab(int index) {
    if (index < 0 || index > 2) return;
    _shellTabIndex = index;
    notifyListeners();
    if (index == 1) {
      loadPlans(force: true);
    }
  }

  Future<bool> login(String email, String password, {String? code}) async {
    _error = null;
    _beginLoading('正在登录…');
    try {
      await _api.login(email, password, code: code);
      _plans = null;
      _nodes = null;
      _loadingMessage = '正在加载套餐与节点…';
      notifyListeners();
      await Future.wait([
        loadPlans(force: true, quiet: true),
        loadNodes(quiet: true),
      ]);
      _loadTelegramUrl();
      _sessionPassword = password;
      return true;
    } on MfaRequiredException catch (e) {
      _error = e.message;
      notifyListeners();
      rethrow;
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return false;
    } finally {
      _endLoading();
    }
  }

  Future<bool> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
  }) async {
    _error = null;
    _beginLoading('正在注册…');
    try {
      final autoLoggedIn = await _api.register(
        email,
        password,
        inviteCode: inviteCode,
        emailCode: emailCode,
      );

      if (autoLoggedIn) {
        // 注册后直接返回了 auth_data，自动登录成功
        _plans = null;
        _nodes = null;
        _loadingMessage = '正在加载套餐与节点…';
        notifyListeners();
        await Future.wait([
          loadPlans(force: true, quiet: true),
          loadNodes(quiet: true),
        ]);
        _loadTelegramUrl();
        _sessionPassword = password;
        return true;
      } else {
        // 注册成功但需要邮件验证或审核
        _error = '注册成功，请查收验证邮件后登录';
        notifyListeners();
        return false;
      }
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return false;
    } finally {
      _endLoading();
    }
  }

  Future<bool> sendEmailCode(
    String email, {
    String context = 'register',
  }) async {
    _error = null;
    // 不发全局 loading，由调用方自行展示按钮 spinner
    try {
      await _api.sendEmailCode(email, context: context);
      return true;
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return false;
    }
  }

  void logout() {
    if (!kIsWeb) {
      unawaited(_onVpnDisconnected());
      _mihomo.disconnect();
      VpnBridge.stop();
      unawaited(_syncMenuBar());
    }
    _api.logout();
    _sessionPassword = null;
    _nodes = null;
    _plans = null;
    _recharges = null;
    _tickets = null;
    _shellTabIndex = 0;
    notifyListeners();
  }

  /// 切换连接并返回本次操作产生的错误（不含历史加载错误）
  Future<String?> toggleConnectionWithFeedback() async {
    await toggleConnection();
    return _error;
  }

  Future<void> toggleConnection() async {
    if (_connecting) {
      _error = '正在连接，请稍候…';
      notifyListeners();
      return;
    }
    _connecting = true;
    notifyListeners();
    try {
      final willConnect = !_api.isConnected;
      clearError();
      try {
        if (willConnect) {
          if (_mihomo.isSupported) {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              final ok = await VpnBridge.prepare();
              if (!ok) {
                _error = '需要授予 VPN 权限才能连接';
                notifyListeners();
                return;
              }
            }
            final n = nodeById(_api.selectedNodeId);
            final subText = await _api.fetchSubscribeText();
            await _mihomo.connect(
              clashYaml: subText,
              proxyName: n?.name,
            );
          } else if (!kIsWeb) {
            final ok = await VpnBridge.prepare();
            if (!ok) {
              _error = '需要授予 VPN 权限才能连接';
              notifyListeners();
              return;
            }
          }
        } else {
          if (_mihomo.isSupported) {
            await _mihomo.disconnect();
          } else if (!kIsWeb) {
            await VpnBridge.stop();
          }
        }
        await _api.toggleConnection();
        if (willConnect) {
          await _onVpnConnected();
          clearError();
        } else {
          await _onVpnDisconnected();
        }
        if (!willConnect && !kIsWeb && !_mihomo.isSupported) {
          await VpnBridge.stop();
        } else if (willConnect && !kIsWeb && !_mihomo.isSupported) {
          final n = nodeById(_api.selectedNodeId);
          await VpnBridge.start(nodeName: n?.name ?? '—');
        }
      } on PanelApiException catch (e) {
        _error = e.message;
        notifyListeners();
      } catch (e) {
        _error = UserMessages.networkError(e);
        notifyListeners();
      }
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> _loadReadState() async {
    _readAnnouncementIds = await _readState.readAnnouncementIds();
    _readTicketIds = await _readState.readTicketIds();
    notifyListeners();
  }

  Future<void> markAnnouncementRead(String id) async {
    await _readState.markAnnouncementRead(id);
    _readAnnouncementIds = {..._readAnnouncementIds, id};
    notifyListeners();
  }

  Future<void> markTicketRead(String id) async {
    await _readState.markTicketRead(id);
    _readTicketIds = {..._readTicketIds, id};
    notifyListeners();
  }

  Future<void> loadAnnouncements() async {
    try {
      _announcements = await _api.fetchAnnouncements();
    } on PanelApiException catch (e) {
      _error = e.message;
      _announcements = [];
    } catch (e) {
      _error = UserMessages.networkError(e);
      _announcements = [];
    }
    notifyListeners();
  }

  Future<void> refreshHome() async {
    _error = null;
    try {
      await _api.refreshUser();
    } on PanelApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = UserMessages.networkError(e);
    }

    try {
      _nodes = await _api.fetchNodes();
    } on PanelApiException catch (e) {
      _error = e.message;
      _nodes = [];
    } catch (e) {
      _error = UserMessages.networkError(e);
      _nodes = [];
    }

    try {
      _announcements = await _api.fetchAnnouncements();
    } on PanelApiException catch (e) {
      _error = e.message;
      _announcements = [];
    } catch (e) {
      _error = UserMessages.networkError(e);
      _announcements = [];
    }

    notifyListeners();
  }

  Future<void> speedTestNodes() async {
    if (_speedTesting || _nodes == null || _nodes!.isEmpty) return;
    _speedTesting = true;
    _nodePingMs = {};
    notifyListeners();
    try {
      final sub = await _api.fetchSubscribeText();
      final Map<String, int> results;
      if (_mihomo.isSupported) {
        results = await _mihomo.speedTest(
          nodes: _nodes!,
          clashYaml: sub,
          onProgress: (id, ms) {
            _nodePingMs = {...?_nodePingMs, id: ms};
            notifyListeners();
          },
        );
      } else {
        results = await NodeSpeedTest.run(
          _nodes!,
          sub,
          onProgress: (id, ms) {
            _nodePingMs = {...?_nodePingMs, id: ms};
            notifyListeners();
          },
        );
      }
      _nodePingMs = results;
      if (results.isEmpty) {
        _error = '测速完成，但所有节点均超时或不可达';
      }
    } on UnsupportedError catch (e) {
      _error = e.message?.toString() ?? '当前平台不支持测速';
    } on PanelApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = UserMessages.networkError(e);
    } finally {
      _speedTesting = false;
      notifyListeners();
    }
  }

  Future<void> loadNodes({bool quiet = false}) async {
    Future<void> work() async {
      _error = null;
      _nodes = null;
      notifyListeners();
      try {
        _nodes = await _api.fetchNodes();
        if ((_nodes == null || _nodes!.isEmpty) && isLoggedIn) {
          await _api.refreshUser();
          _nodes = await _api.fetchNodes();
        }
        if ((_nodes == null || _nodes!.isEmpty) && isLoggedIn) {
          _error = '节点接口返回为空，或当前订阅未返回可解析的 Clash 节点';
        }
      } on PanelApiException catch (e) {
        _error = e.message;
        _nodes = [];
      } catch (e) {
        _error = UserMessages.networkError(e);
        _nodes = [];
      }
      notifyListeners();
      await _syncMenuBar();
    }

    if (quiet && _loadingCount > 0) {
      await work();
    } else {
      await runWithLoading('正在加载节点…', work);
    }
  }

  void selectNode(String id) {
    _api.selectNode(id);
    notifyListeners();
    unawaited(_syncNativeVpnIfConnected());
    unawaited(_syncMenuBar());
  }

  Future<void> _syncNativeVpnIfConnected() async {
    if (!_api.isConnected) return;
    final n = nodeById(_api.selectedNodeId);
    try {
      if (_mihomo.isSupported) {
        if (Platform.isIOS && await VpnBridge.isActive()) {
          final subText = await _api.fetchSubscribeText();
          await _mihomo.connect(clashYaml: subText, proxyName: n?.name);
        } else {
          await _mihomo.confirmNodeSelection(n?.name ?? '');
        }
      } else if (!kIsWeb) {
        await VpnBridge.start(nodeName: n?.name ?? '—');
      }
    } catch (_) {}
  }

  VpnNode? nodeById(String? id) {
    if (id == null || _nodes == null) return null;
    try {
      return _nodes!.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<String?> exportIosSubscription({bool openShadowrocket = false}) async {
    if (!IosExportBridge.supported) return '仅 iOS 可用';
    final url = _api.clashSubscribeImportUrl;
    if (url == null || url.isEmpty) {
      return '无可用订阅链接，请先在配置管理中设置订阅';
    }
    if (openShadowrocket) {
      final ok = await IosExportBridge.openUrl(
        IosExportBridge.shadowrocketImportUrl(url),
      );
      return ok ? null : '无法打开 Shadowrocket，请确认已安装';
    }
    final copied = await IosExportBridge.copyText(url);
    return copied ? null : '复制失败';
  }

  Future<void> updateSubscription(String url, String token) async {
    await runWithLoading('正在保存订阅…', () async {
      await _api.updateSubscription(subscribeUrl: url, token: token);
    });
  }

  Future<void> loadPlans({bool force = false, bool quiet = false}) async {
    if (!force && _plans != null && _plans!.isNotEmpty) return;

    Future<void> work() async {
      _error = null;
      _plans = null;
      notifyListeners();
      try {
        _plans = await _api.fetchPlans();
        if ((_plans == null || _plans!.isEmpty) && isLoggedIn) {
          await _api.refreshUser();
          _plans = await _api.fetchPlans();
        }
      } on PanelApiException catch (e) {
        _error = e.message;
        _plans = [];
      } catch (e) {
        _error = UserMessages.networkError(e);
        _plans = [];
      }
      notifyListeners();
    }

    if (quiet && _loadingCount > 0) {
      await work();
    } else {
      await runWithLoading('正在加载商品…', work);
    }
  }

  Future<bool> preparePaymentForInvoice(String invoiceId) async {
    _error = null;
    _beginLoading('正在获取支付方式…');
    try {
      _paymentMethods = await _api.fetchPaymentMethods(invoiceId);
      notifyListeners();
      return true;
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return false;
    } finally {
      _endLoading();
    }
  }

  Future<OrderResult?> createOrder(
    String planId, {
    String? period,
    String coupon = '',
  }) async {
    _error = null;
    if (pendingRecharges.isEmpty) {
      await loadRecharges(quiet: true);
    }
    if (pendingRecharges.isNotEmpty) {
      _error = '您有未支付的订单，请先完成支付或稍后再试';
      notifyListeners();
      return null;
    }
    _beginLoading('正在创建订单…');
    try {
      ShopPlan? matched;
      for (final p in _plans ?? const <ShopPlan>[]) {
        if (p.id == planId) {
          matched = p;
          break;
        }
      }
      final order = await _api.createProductOrder(
        planId,
        period: period ?? matched?.orderPeriod ?? 'month_price',
        coupon: coupon,
      );
      _loadingMessage = '正在获取支付方式…';
      notifyListeners();
      _paymentMethods = await _api.fetchPaymentMethods(order.invoiceId);
      notifyListeners();
      return order;
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return null;
    } finally {
      _endLoading();
    }
  }

  String paymentUrl(String gateway, String invoiceId) =>
      _api.paymentUrl(gateway, invoiceId: invoiceId);

  Future<void> loadRecharges({bool quiet = false}) async {
    Future<void> work() async {
      _recharges = await _api.fetchRecharges();
      notifyListeners();
    }
    if (quiet) {
      await work();
    } else {
      await runWithLoading('正在加载充值记录…', work);
    }
  }

  Future<bool> cancelOrder(String tradeNo) async {
    _error = null;
    _beginLoading('正在取消订单…');
    try {
      final ok = await _api.cancelOrder(tradeNo);
      if (ok) {
        await loadRecharges(quiet: true);
      }
      return ok;
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return false;
    } finally {
      _endLoading();
    }
  }

  Future<void> loadTickets({bool quiet = false}) async {
    Future<void> work() async {
      _tickets = await _api.fetchTickets();
      notifyListeners();
    }

    if (quiet && _loadingCount > 0) {
      await work();
    } else {
      await runWithLoading('正在加载工单…', work);
    }
  }

  Future<bool> createTicket(String subject, String content) async {
    return runWithLoading('正在提交工单…', () async {
      final ok = await _api.createTicket(subject, content);
      if (ok) await loadTickets(quiet: true);
      notifyListeners();
      return ok;
    });
  }

  Future<SupportTicket> fetchTicketDetail(String id) async {
    return _api.fetchTicketDetail(id);
  }

  Future<bool> replyTicket(String id, String message) async {
    return runWithLoading('正在发送回复…', () async {
      try {
        final ok = await _api.replyTicket(id, message);
        if (ok) await loadTickets(quiet: true);
        notifyListeners();
        return ok;
      } on PanelApiException catch (e) {
        _error = e.message;
        notifyListeners();
        return false;
      } catch (e) {
        _error = UserMessages.networkError(e);
        notifyListeners();
        return false;
      }
    });
  }

  Future<bool> closeTicket(String id) async {
    return runWithLoading('正在关闭工单…', () async {
      final ok = await _api.closeTicket(id);
      if (ok) await loadTickets(quiet: true);
      notifyListeners();
      return ok;
    });
  }

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _error = null;
    try {
      await runWithLoading('正在修改密码…', () async {
        await _api.changePassword(
          oldPassword: oldPassword,
          newPassword: newPassword,
        );
      });
      _sessionPassword = newPassword;
      notifyListeners();
      return true;
    } on PanelApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
      return false;
    }
  }

  Future<String> telegramSupportUrl() async {
    if (_telegramUrl != null) return _telegramUrl!;
    await _loadTelegramUrl();
    return _telegramUrl ?? AppConfig.telegramSupportUrl;
  }

  Future<void> _loadTelegramUrl() async {
    try {
      _telegramUrl = await _api.fetchTelegramUrl();
      notifyListeners();
    } catch (_) {
      _telegramUrl ??= AppConfig.telegramSupportUrl;
    }
  }

  String importUrl(ImportClient client) => _api.importUrl(client);

  @visibleForTesting
  void debugMarkReady() {
    _initialized = true;
    notifyListeners();
  }
}
