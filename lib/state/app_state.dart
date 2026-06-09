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
import '../utils/node_filters.dart';
import '../utils/proxy_name_match.dart';
import '../utils/user_messages.dart';

class AppState extends ChangeNotifier {
  static const _prefUiLangKey = 'ui_lang';
  static const _prefAppDisguiseKey = 'app_disguise';

  /// 菜单栏 / 节点列表「自动选择」占位 ID
  static const autoSelectNodeId = '__auto_select__';

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
  bool _ordering = false;
  String? _nodeSearch;
  String? _autoResolvedLeafName;
  String? _autoResolvedNodeId;
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
  bool get ordering => _ordering;
  String get loadingMessage => _loadingMessage ?? '请稍候…';
  String? get error => _error;
  UserProfile? get profile => _api.isLoggedIn ? _api.profile : null;
  bool get isConnected => _api.isConnected;
  String? get selectedNodeId => _api.selectedNodeId;
  bool get isAutoSelect => _api.selectedNodeId == autoSelectNodeId;
  String? get autoResolvedLeafName => _autoResolvedLeafName;
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

  /// 充值记录（不含已取消）
  List<RechargeRecord> get visibleRecharges =>
      _recharges?.where((r) => r.status != '已取消').toList() ?? const [];

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
      if (!_systemProxyEnabled) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await setSystemProxy(true);
      }
    }
    if (mihomoSupported) {
      try {
        _proxyMode = await _mihomo.getMode();
      } catch (_) {}
    }
    if (isAutoSelect && _autoResolvedLeafName == null) {
      await _syncAutoResolvedFromMihomo();
      if (_autoResolvedLeafName == null) {
        await _refreshAutoResolvedLeaf();
      }
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

  String? get effectiveSelectedNodeId {
    if (isAutoSelect) {
      if (_autoResolvedNodeId != null) return _autoResolvedNodeId;
      final leaf = sanitizeProxyLeaf(_autoResolvedLeafName);
      if (leaf == null) return null;
      return nodeIdByProxyName(leaf);
    }
    return _api.selectedNodeId;
  }

  VpnNode? get effectiveNode {
    if (isAutoSelect) {
      if (_autoResolvedNodeId != null) return nodeById(_autoResolvedNodeId);
      final leaf = sanitizeProxyLeaf(_autoResolvedLeafName);
      if (leaf != null) return nodeByProxyName(leaf);
    }
    return nodeById(_api.selectedNodeId);
  }

  /// 首页节点条：自动选择时显示实际节点名
  String connectionDisplayName({String fallback = '选择节点'}) {
    if (isAutoSelect) {
      final node = effectiveNode;
      if (node != null) return node.name;
      final leaf = sanitizeProxyLeaf(_autoResolvedLeafName);
      if (leaf != null && leaf.isNotEmpty) return leaf;
      if (_connecting) return '自动选择中…';
      return '自动选择';
    }
    return nodeById(_api.selectedNodeId)?.name ?? fallback;
  }

  String selectedNodeLabel({String fallback = '选择节点'}) {
    if (isAutoSelect) {
      final node = effectiveNode;
      if (node != null) return '自动选择 · ${node.name}';
      if (_connecting) return '自动选择中…';
      return '自动选择';
    }
    return nodeById(_api.selectedNodeId)?.name ?? fallback;
  }

  String? nodeIdByProxyName(String proxyName) {
    final node = nodeByProxyName(proxyName);
    return node?.id;
  }

  VpnNode? nodeByProxyName(String proxyName) {
    final list = _nodes;
    if (list == null || list.isEmpty) return null;
    final trimmed = proxyName.trim();
    for (final n in list) {
      if (n.name == trimmed) return n;
    }
    final names = list.map((n) => n.name).toList();
    final matched =
        matchProxyName(trimmed, names) ??
        matchProxyNameRelaxed(trimmed, names);
    if (matched == null) return null;
    try {
      return list.firstWhere((n) => n.name == matched);
    } catch (_) {
      return null;
    }
  }

  /// 未手动选节点时默认走自动选择
  void ensureAutoSelectIfNeeded() {
    final id = _api.selectedNodeId;
    final noSelection = id == null || id.isEmpty;
    final manualMissing = id != null &&
        id != autoSelectNodeId &&
        (_nodes == null || nodeById(id) == null);
    if (noSelection || manualMissing) {
      _api.selectNode(autoSelectNodeId);
      if (manualMissing) {
        _autoResolvedLeafName = null;
        _autoResolvedNodeId = null;
      }
    }
  }

  void _applyAutoPickResult(MihomoAutoPickResult? pick) {
    if (pick == null) return;
    _setAutoResolvedLeaf(pick.proxyName);
    _autoResolvedNodeId =
        pick.nodeId.isNotEmpty ? pick.nodeId : nodeIdByProxyName(pick.proxyName);
  }

  /// 连接后基于面板节点列表测速选最快节点（比策略组解析更可靠）
  Future<bool> _autoPickBestNode() async {
    final list = _nodes;
    if (list == null || list.isEmpty || !_mihomo.isSupported) return false;
    if (!await _mihomo.isRunning) return false;
    try {
      final pick = await _mihomo.pickBestFromAppNodes(
        filterConnectableNodes(list),
        pingCache: _nodePingMs,
      );
      if (pick == null) return false;
      _applyAutoPickResult(pick);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _bestLeafFromPingCache() {
    final pings = _nodePingMs;
    final list = _nodes;
    if (pings == null || pings.isEmpty || list == null) return null;
    String? bestId;
    int? bestMs;
    for (final e in pings.entries) {
      if (bestMs == null || e.value < bestMs) {
        bestMs = e.value;
        bestId = e.key;
      }
    }
    return bestId != null ? nodeById(bestId)?.name : null;
  }

  /// 从 mihomo 当前策略状态同步自动选择结果（不依赖测速）
  Future<void> _syncAutoResolvedFromMihomo() async {
    if (!isAutoSelect || !_mihomo.isSupported) return;
    if (!await _mihomo.isRunning) return;
    try {
      final pick = await _mihomo.readOutboundForPanel(
        filterConnectableNodes(_nodes ?? []),
      );
      if (pick != null) {
        _applyAutoPickResult(pick);
        return;
      }
      final leaf = sanitizeProxyLeaf(_bestLeafFromPingCache());
      if (leaf == null) return;
      _autoResolvedLeafName = leaf;
      _autoResolvedNodeId = nodeIdByProxyName(leaf);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _refreshAutoResolvedLeaf({String? clashYaml}) async {
    if (!isAutoSelect || !_mihomo.isSupported) return;
    await _syncAutoResolvedFromMihomo();
    if (_autoResolvedLeafName != null) return;
    if (await _autoPickBestNode()) return;

    String? leaf;
    try {
      if (await _mihomo.isRunning) {
        leaf = await _mihomo.selectAutoProxy();
      } else if (clashYaml != null && clashYaml.isNotEmpty) {
        leaf = await _mihomo.runAutoPick(
          clashYaml: clashYaml,
          keepAlive: isConnected,
        );
      }
    } catch (_) {}

    leaf ??= await _mihomo.resolveActiveLeaf();
    leaf ??= await _mihomo.currentAutoSelectedLeaf();
    leaf ??= _bestLeafFromPingCache();
    leaf = sanitizeProxyLeaf(leaf);

    if (leaf != null) {
      _autoResolvedLeafName = leaf;
      _autoResolvedNodeId = nodeIdByProxyName(leaf);
      notifyListeners();
    }
  }

  void _setAutoResolvedLeaf(String? leaf) {
    final clean = sanitizeProxyLeaf(leaf);
    if (clean != null) {
      _autoResolvedLeafName = clean;
      _autoResolvedNodeId = nodeIdByProxyName(clean);
      return;
    }
    if (leaf != null && leaf.trim().isNotEmpty) {
      _autoResolvedLeafName = null;
      _autoResolvedNodeId = null;
    }
  }

  Future<String> _connectionProxyName(String clashYaml) async {
    final leaves = extractLeafNamesFromYaml(clashYaml);
    if (isAutoSelect) {
      // 断开重连时选择框仍显示上次叶子节点，连接须用同一节点而非重新猜策略组
      final cached =
          sanitizeProxyLeaf(_autoResolvedLeafName) ?? effectiveNode?.name;
      if (cached != null && cached.isNotEmpty) {
        return matchProxyName(cached, leaves) ??
            matchProxyNameRelaxed(cached, leaves) ??
            cached;
      }
      final group = resolveAutoSelectGroupFromYaml(clashYaml);
      if (group != null && group.isNotEmpty) return group;
    } else {
      final panelName = nodeById(_api.selectedNodeId)?.name ?? '';
      if (panelName.isNotEmpty) {
        return matchProxyName(panelName, leaves) ??
            matchProxyNameRelaxed(panelName, leaves) ??
            panelName;
      }
    }
    for (final leaf in leaves) {
      if (hasProxyTierSuffix(leaf)) return leaf;
    }
    return leaves.isNotEmpty ? leaves.first : '';
  }

  Future<void> _syncMenuBar() async {
    final menuNodes = filterConnectableNodes(_nodes ?? [])
        .map((n) => {'id': n.id, 'name': n.name})
        .toList();
    await MenuBarBridge.updateMenu(
      connected: isConnected,
      nodeName: selectedNodeLabel(),
      mode: _proxyMode,
      nodes: menuNodes,
      selectedNodeId:
          isAutoSelect ? effectiveSelectedNodeId : _api.selectedNodeId,
      autoSelectActive: isAutoSelect,
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
        case 'selectAuto':
          await selectAutoNode();
      }
    });
    await loadUiLangPrefs();
    await _loadReadState();
    if (!kIsWeb && Platform.isAndroid) {
      await _reconcileAndroidVpnState();
    }
    if (_mihomo.isSupported &&
        (kIsWeb || (!Platform.isAndroid && !Platform.isIOS))) {
      if (!kIsWeb && Platform.isWindows) {
        // 仅 Windows：后台拉起进程，连接时再等待 API 就绪
        unawaited(_mihomo.warmStart().catchError((_) {}));
      } else {
        try {
          await _mihomo.bootstrap();
        } catch (_) {}
      }
    }
    await _api.init();
    final restored = await _api.tryRestoreSession();
    _initialized = true;
    notifyListeners();
    if (restored) {
      unawaited(
        Future.wait([
          loadPlans(force: true, quiet: true),
          loadNodes(quiet: true),
          _loadTelegramUrl(),
        ]).then((_) => _syncMenuBar()),
      );
    } else {
      await _syncMenuBar();
    }
  }

  void goToShellTab(int index) {
    if (index < 0 || index > 2) return;
    _shellTabIndex = index;
    notifyListeners();
    if (index == 1) {
      loadPlans();
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

  Future<void> logout() async {
    if (!kIsWeb) {
      unawaited(_onVpnDisconnected());
      _mihomo.disconnect();
      VpnBridge.stop();
      unawaited(_syncMenuBar());
    }
    _sessionPassword = null;
    _nodes = null;
    _plans = null;
    _recharges = null;
    _tickets = null;
    _shellTabIndex = 0;
    // 先同步清登录态并刷新 UI，避免持久化失败时卡在已登录页
    _api.signOutLocally();
    notifyListeners();
    try {
      await _api.logout();
    } catch (_) {}
    notifyListeners();
  }

  /// 切换连接并返回本次操作产生的错误（不含历史加载错误）
  Future<String?> toggleConnectionWithFeedback() async {
    await toggleConnection();
    return _error;
  }

  Future<void> toggleConnection() async {
    if (_connecting) return;
    _connecting = true;
    notifyListeners();
    try {
      final willConnect = !_api.isConnected;
      clearError();
      try {
        if (willConnect) {
          ensureAutoSelectIfNeeded();
          if (_mihomo.isSupported) {
            final mobileVpn =
                !kIsWeb && (Platform.isAndroid || Platform.isIOS);
            final nodesFuture = (_nodes == null || _nodes!.isEmpty)
                ? loadNodes(quiet: true)
                : Future<void>.value();
            final subFuture = _api.fetchSubscribeText();
            final prepareFuture = mobileVpn ? VpnBridge.prepare() : null;
            await nodesFuture;
            if (mobileVpn) {
              final ok = await prepareFuture!;
              if (!ok) {
                _error = '需要授予 VPN 权限才能连接';
                notifyListeners();
                return;
              }
            }
            final subText = await subFuture;
            final proxyName = await _connectionProxyName(subText);
            final resolvedLeaf = await _mihomo.connect(
              clashYaml: subText,
              proxyName: proxyName.isEmpty ? null : proxyName,
              panelNodes: _nodes,
              pingCache: _nodePingMs,
            );
            if (isAutoSelect) {
              if (resolvedLeaf != null) {
                _setAutoResolvedLeaf(resolvedLeaf);
              } else if (!kIsWeb &&
                  !(Platform.isAndroid || Platform.isIOS) &&
                  !await _autoPickBestNode()) {
                await _refreshAutoResolvedLeaf(clashYaml: subText);
              }
              notifyListeners();
            }
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
          if (isAutoSelect) await _syncMenuBar();
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
          connected: isConnected,
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
        if (_nodes != null && _nodes!.isNotEmpty) {
          ensureAutoSelectIfNeeded();
          if (isConnected && isAutoSelect) {
            await _syncAutoResolvedFromMihomo();
          }
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
    if (id != autoSelectNodeId) {
      _autoResolvedLeafName = null;
      _autoResolvedNodeId = null;
    }
    _api.selectNode(id);
    notifyListeners();
    unawaited(_applyNodeSelectionToMihomo());
    unawaited(_syncNativeVpnIfConnected());
    unawaited(_syncMenuBar());
  }

  Future<void> selectAutoNode() async {
    _api.selectNode(autoSelectNodeId);
    _autoResolvedLeafName = null;
    _autoResolvedNodeId = null;
    notifyListeners();
    try {
      if (_mihomo.isSupported) {
        if (isConnected || await _mihomo.isRunning) {
          if (!await _autoPickBestNode()) {
            _setAutoResolvedLeaf(await _mihomo.selectAutoProxy());
            _autoResolvedNodeId =
                nodeIdByProxyName(_autoResolvedLeafName ?? '');
          }
        } else {
          final sub = await _api.fetchSubscribeText();
          final leaf = await _mihomo.runAutoPick(
            clashYaml: sub,
            keepAlive: false,
          );
          _setAutoResolvedLeaf(leaf);
          _autoResolvedNodeId = nodeIdByProxyName(leaf ?? '');
        }
      }
    } catch (_) {}
    notifyListeners();
    unawaited(_syncNativeVpnIfConnected());
    await _syncMenuBar();
  }

  Future<void> _applyNodeSelectionToMihomo() async {
    if (!_mihomo.isSupported) return;
    if (!kIsWeb && Platform.isAndroid && _api.isConnected) {
      return;
    }
    try {
      if (!(await _mihomo.isRunning)) return;
      if (isAutoSelect) {
        if (!await _autoPickBestNode()) {
          _setAutoResolvedLeaf(await _mihomo.selectAutoProxy());
          _autoResolvedNodeId =
              nodeIdByProxyName(_autoResolvedLeafName ?? '');
          notifyListeners();
        }
      } else {
        final n = nodeById(_api.selectedNodeId);
        if (n != null) await _mihomo.selectNode(n.name);
      }
    } catch (_) {}
  }

  Future<void> _syncNativeVpnIfConnected() async {
    if (!_api.isConnected) return;
    try {
      if (_mihomo.isSupported) {
        final subText = await _api.fetchSubscribeText();
        final proxyName = await _connectionProxyName(subText);
        if (proxyName.isEmpty) return;
        if ((Platform.isIOS || Platform.isAndroid) &&
            await VpnBridge.isActive()) {
          await _mihomo.connect(
            clashYaml: subText,
            proxyName: proxyName,
            panelNodes: _nodes,
            pingCache: _nodePingMs,
          );
        } else {
          await _mihomo.confirmNodeSelection(proxyName);
        }
      } else if (!kIsWeb) {
        final label = selectedNodeLabel(fallback: '—');
        await VpnBridge.start(nodeName: label);
      }
    } catch (e) {
      _error = UserMessages.networkError(e);
      notifyListeners();
    }
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

  Future<bool> preparePaymentForInvoice(
    String invoiceId, {
    bool quiet = false,
  }) async {
    _error = null;
    if (!quiet) {
      _beginLoading('正在获取支付方式…');
    }
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
      if (!quiet) {
        _endLoading();
      }
    }
  }

  Future<OrderResult?> createOrder(
    String planId, {
    String? period,
    String coupon = '',
    bool quiet = false,
  }) async {
    if (_ordering) return null;
    _error = null;
    if (_recharges == null) {
      await loadRecharges(quiet: true);
    }
    if (pendingRecharges.isNotEmpty) {
      _error = '您有未支付的订单，请先完成支付或稍后再试';
      notifyListeners();
      return null;
    }
    _ordering = true;
    if (!quiet) {
      _beginLoading('正在创建订单…');
    } else {
      notifyListeners();
    }
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
      unawaited(loadRecharges(refresh: true, quiet: true));
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
      _ordering = false;
      if (!quiet) {
        _endLoading();
      } else {
        notifyListeners();
      }
    }
  }

  Future<CheckoutResult> checkoutOrder(String invoiceId, String methodId) =>
      _api.checkoutOrder(invoiceId, methodId);

  String paymentUrl(String gateway, String invoiceId) =>
      _api.paymentUrl(gateway, invoiceId: invoiceId);

  Future<void> loadRecharges({bool quiet = false, bool refresh = false}) async {
    if (!refresh && _recharges != null) return;

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

  Future<bool> cancelOrder(String tradeNo, {bool quiet = false}) async {
    _error = null;
    Future<bool> work() async {
      try {
        final ok = await _api.cancelOrder(tradeNo);
        if (ok) {
          await loadRecharges(refresh: true, quiet: true);
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
      }
    }

    if (quiet) {
      return work();
    }
    return runWithLoading('正在取消订单…', work);
  }

  Future<void> loadTickets({bool quiet = false, bool refresh = false}) async {
    if (!refresh && _tickets != null) return;

    Future<void> work() async {
      _tickets = await _api.fetchTickets();
      notifyListeners();
    }

    if (quiet) {
      await work();
    } else {
      await runWithLoading('正在加载工单…', work);
    }
  }

  Future<bool> createTicket(
    String subject,
    String content, {
    bool quiet = false,
  }) async {
    Future<bool> work() async {
      try {
        final ok = await _api.createTicket(subject, content);
        if (ok) await loadTickets(refresh: true, quiet: true);
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
    }

    if (quiet) {
      return work();
    }
    return runWithLoading('正在提交工单…', work);
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
