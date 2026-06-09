import 'dart:async';
import 'dart:io';

import '../config/app_config.dart';
import '../config/mihomo_paths.dart';
import '../models/models.dart';
import '../utils/node_filters.dart';
import '../utils/proxy_name_match.dart';
import 'mihomo_api.dart';
import 'mihomo_bridge.dart';
import 'panel_exceptions.dart';
import 'vpn_bridge.dart';

/// 基于面板节点列表测速后的自动选择结果
class MihomoAutoPickResult {
  const MihomoAutoPickResult({
    required this.proxyName,
    required this.nodeId,
  });

  final String proxyName;
  final String nodeId;
}

/// 管理 mihomo 配置写入、进程生命周期与节点选择
class MihomoService {
  MihomoService({MihomoApi? api}) : _api = api ?? MihomoApi();

  final MihomoApi _api;

  bool _bootstrapped = false;
  Future<void>? _bootstrapFuture;
  Future<void> _lifecycle = Future<void>.value();

  bool get isSupported => MihomoBridge.supported;

  Future<T> _runExclusive<T>(Future<T> Function() action) async {
    final prior = _lifecycle;
    final gate = Completer<void>();
    _lifecycle = gate.future;
    await prior;
    try {
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  int get _aliveMaxAttempts => Platform.isWindows ? 160 : 50;

  Duration get _alivePollGap =>
      Platform.isWindows
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 100);

  Future<bool> _probeAlive() =>
      Platform.isWindows ? _api.isAliveQuick() : _api.isAlive();

  /// 仅 Windows：后台拉起进程，不等待 API（连接时会完整 bootstrap）。
  Future<void> warmStart() async {
    if (!isSupported || !Platform.isWindows) return;
    if (_bootstrapped && await _probeAlive()) return;
    await _runExclusive(() async {
      await _writeBaseConfig();
      final path = await MihomoPaths.configFile();
      await MihomoBridge.start(configPath: path);
    });
  }

  Future<void> bootstrap() async {
    if (!isSupported) return;
    // Android / iOS 在 VPN 连接时由原生层启动 mihomo
    if (Platform.isAndroid || Platform.isIOS) {
      _bootstrapped = true;
      return;
    }
    if (_bootstrapped) {
      if (await _probeAlive()) return;
      _bootstrapped = false;
      _bootstrapFuture = null;
    }
    // Windows 预热可能是空配置实例；连接时会 _restartWithConfig 载入订阅
    if (Platform.isWindows && await _waitUntilAlive(quiet: true)) {
      final data = await _api.proxies();
      final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
      if (realOutboundProxyNames(proxies).isNotEmpty) {
        _bootstrapped = true;
        return;
      }
      await MihomoBridge.stop();
      _bootstrapped = false;
    }
    _bootstrapFuture ??= _runExclusive(_doBootstrap);
    try {
      await _bootstrapFuture!;
    } catch (e) {
      _bootstrapFuture = null;
      rethrow;
    }
  }

  Future<void> _doBootstrap() async {
    await _writeBaseConfig();
    final path = await MihomoPaths.configFile();
    final started = await MihomoBridge.start(configPath: path);
    if (!started) {
      final detail = await MihomoBridge.lastStartError();
      throw PanelApiException(
        detail != null && detail.isNotEmpty
            ? 'mihomo 启动失败：$detail'
            : 'mihomo 启动失败',
      );
    }
    if (!await _waitUntilAlive()) {
      throw PanelApiException('mihomo 启动超时，请检查配置与二进制权限');
    }
    _bootstrapped = true;
  }

  /// 连接并返回自动选择解析出的实际节点名（若有）
  Future<String?> connect({
    String? clashSubscribeUrl,
    String? clashYaml,
    String? proxyName,
    List<VpnNode>? panelNodes,
    Map<String, int>? pingCache,
  }) async {
    if (!isSupported) {
      throw PanelApiException('当前平台不支持内嵌 mihomo');
    }
    final mobileVpn = Platform.isAndroid || Platform.isIOS;
    final androidProfile = Platform.isAndroid
        ? await MihomoBridge.getDeviceVpnProfile()
        : (Platform.isIOS ? AndroidVpnProfile.stock : null);
    var config = clashYaml != null
        ? _prepareConfig(
            clashYaml,
            forVpnTunnel: mobileVpn,
            androidProfile: androidProfile,
          )
        : await _buildConfigFromSubscription(
            clashSubscribeUrl!,
            androidProfile: androidProfile,
            forVpnTunnel: mobileVpn,
          );
    // 手机 VPN 须在启动 TUN 前确定真实叶子节点名（自动选择不能为空）
    var outboundLabel = mobileVpn
        ? _resolveOutboundProxyForConnect(
            config,
            proxyName,
            panelNodes,
            pingCache,
          )
        : null;
    final pinTarget = mobileVpn
        ? outboundLabel
        : (proxyName != null &&
                proxyName.isNotEmpty &&
                !isAutoSelectGroupName(proxyName)
            ? proxyName
            : null);
    if (pinTarget != null && pinTarget.isNotEmpty && !mobileVpn) {
      config = _pinSelectedProxyInConfig(config, pinTarget);
    }
    if (mobileVpn) {
      var label = outboundLabel ?? proxyName;
      if (label == null || label.isEmpty) {
        label = _resolveOutboundProxyForConnect(
          config,
          null,
          panelNodes,
          pingCache,
        );
      }
      if (label == null || label.isEmpty) {
        throw PanelApiException('请先选择可用节点后再连接');
      }
      await _startViaVpnService(
        config,
        nodeLabel: label,
        proxyName: label,
      );
      // 手机端由原生 MihomoRouting API 选路，勿改写 YAML（易破坏 proxy-groups 结构）
      return sanitizeProxyLeaf(label) ?? label;
    }

    if (mobileVpn) {
      await bootstrap();
    }
    await _runExclusive(() async {
      await _restartWithConfig(
        config,
        assertRetries: Platform.isWindows ? 5 : null,
      );
    });

    final wantsAutoPick = proxyName == null ||
        proxyName.isEmpty ||
        isAutoSelectGroupName(proxyName) ||
        (clashYaml != null &&
            resolveAutoSelectGroupFromYaml(clashYaml) == proxyName);

    String? resolvedLeaf;
    if (wantsAutoPick) {
      if (!mobileVpn &&
          panelNodes != null &&
          panelNodes.isNotEmpty &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final pick = await _pickOutboundForConnect(
          panelNodes,
          pingCache: pingCache,
        );
        resolvedLeaf = pick?.proxyName;
        if (resolvedLeaf != null) {
          final data = await _api.proxies();
          final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
          resolvedLeaf = sanitizeProxyLeaf(resolvedLeaf, proxies: proxies);
          if (resolvedLeaf != null) {
            await _applyOutboundPick(proxies, resolvedLeaf);
          }
        }
      }
      if (!mobileVpn && resolvedLeaf == null) {
        resolvedLeaf = sanitizeProxyLeaf(await selectAutoProxy());
        if (resolvedLeaf != null) {
          final data = await _api.proxies();
          final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
          await _applyOutboundPick(proxies, resolvedLeaf);
        }
      }
    } else if (proxyName != null && proxyName.isNotEmpty) {
      if (Platform.isAndroid) {
        // 节点已在 StarVpnService 建 TUN 前由原生层选中
      } else if (mobileVpn && !Platform.isIOS) {
        await _api.setMode('global');
        await _applyNodeSelection(proxyName);
      } else if (!Platform.isIOS) {
        await _api.setMode('global');
        await _applyNodeSelection(proxyName);
      }
    }
    final endData = await _api.proxies();
    final endProxies = endData['proxies'] as Map<String, dynamic>? ?? {};
    return sanitizeProxyLeaf(resolvedLeaf, proxies: endProxies) ??
        sanitizeProxyLeaf(
          await resolveActiveLeaf(),
          proxies: endProxies,
        );
  }

  /// 使用 mihomo 内核对各节点做延迟测试（与 Clash Verge 相同方式）
  Future<Map<String, int>> speedTest({
    required List<VpnNode> nodes,
    required String clashYaml,
    bool connected = false,
    void Function(String nodeId, int ms)? onProgress,
  }) async {
    if (!isSupported) {
      throw PanelApiException('当前平台不支持 mihomo 测速');
    }
    final wasAliveAtStart = await _api.isAlive();
    final vpnActive =
        (Platform.isAndroid || Platform.isIOS) && await VpnBridge.isActive();

    // 桌面端已连接时 mihomo 正在代理，勿重启否则测速全失败
    final shouldReloadConfig =
        !vpnActive && !(connected && wasAliveAtStart);
    if (shouldReloadConfig) {
      final config = _prepareConfig(clashYaml, forVpnTunnel: false);
      await bootstrap();
      await _runExclusive(
        () => _restartWithConfig(config, maxAttempts: 60),
      );
    }

    final proxyData = await _api.proxies();
    final allProxies = proxyData['proxies'] as Map<String, dynamic>? ?? {};
    final leaves = realOutboundProxyNames(allProxies).toSet();
    final autoGroup = resolveAutoSelectGroupName(allProxies);
    if (autoGroup != null) {
      await _api.testProxyDelay(autoGroup);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    final results = <String, int>{};
    for (final node in nodes) {
      if (node.status == NodeStatus.offline) continue;
      final testNames = proxyNamesForPanelNode(node.name, leaves);
      if (testNames.isEmpty) continue;

      int? ms;
      for (final proxy in testNames) {
        ms = await _api.testProxyDelay(proxy);
        if (ms != null) break;
      }
      if (ms != null) {
        results[node.id] = ms;
        onProgress?.call(node.id, ms);
        for (final other in nodes) {
          if (other.id == node.id || results.containsKey(other.id)) continue;
          final otherNames = proxyNamesForPanelNode(other.name, leaves);
          if (otherNames.any(testNames.contains)) {
            results[other.id] = ms;
            onProgress?.call(other.id, ms);
          }
        }
      }
    }

    if (!wasAliveAtStart && !vpnActive && !connected) {
      await MihomoBridge.stop();
      if (!Platform.isAndroid && !Platform.isIOS) {
        await _writeBaseConfig();
        final path = await MihomoPaths.configFile();
        await MihomoBridge.start(configPath: path);
      }
    }
    return results;
  }

  Future<void> disconnect() async {
    if (!isSupported) return;
    try {
      await _api.closeAllConnections();
    } catch (_) {}
    if (Platform.isAndroid || Platform.isIOS) {
      await VpnBridge.stop();
      return;
    }
    await _runExclusive(MihomoBridge.stop);
  }

  String? _resolveOutboundProxyKey(
    String label,
    Map<String, dynamic> proxies,
  ) {
    final realLeaves = realOutboundProxyNames(proxies);
    if (realLeaves.isEmpty) return null;
    final matched =
        matchProxyName(label, realLeaves) ??
        matchProxyNameRelaxed(label, realLeaves);
    if (matched != null) return matched;
    final trimmed = label.trim();
    if (isRealOutboundProxy(trimmed, proxies)) return trimmed;
    return null;
  }

  Future<void> selectNode(String proxyName) async {
    if (!isSupported) return;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final resolved = _resolveOutboundProxyKey(proxyName, proxies);
    if (resolved == null) return;
    await _api.setMode('global');
    await _selectProxyInAllGroups(proxies, resolved);
  }

  List<String> _expandRealLeafMembers(
    Map<String, dynamic> proxies,
    List<String> members,
  ) {
    final realLeaves = realOutboundProxyNames(proxies).toSet();
    final out = <String>[];
    final seen = <String>{};

    void walk(List<String> names) {
      for (final m in names) {
        if (seen.contains(m)) continue;
        seen.add(m);
        if (isRealOutboundProxy(m, proxies) && realLeaves.contains(m)) {
          out.add(m);
          continue;
        }
        final item = proxies[m];
        if (item is Map<String, dynamic> && isProxyGroupEntry(item)) {
          walk(_api.proxyGroupMembers(item));
        }
      }
    }

    walk(members);
    return out;
  }

  bool _isValidPingMs(int? ms) => ms != null && ms > 0 && ms < 10000;

  int _leafPreferenceScore(String name) {
    var score = 0;
    if (hasProxyTierSuffix(name)) score += 20;
    return score;
  }

  int _panelNodeMatchScore(String nodeName, String leaf) {
    if (nodeName == leaf) return 10000;
    if (matchProxyName(nodeName, [leaf]) != null) return 9500;
    if (matchProxyName(leaf, [nodeName]) != null) return 9400;
    if (matchProxyNameRelaxed(nodeName, [leaf]) != null) return 5000;
    if (matchProxyNameRelaxed(leaf, [nodeName]) != null) return 4900;
    return -1;
  }

  MihomoAutoPickResult? _pickBestFromPingCache(
    List<VpnNode> panelNodes,
    Map<String, int> pingCache,
    Set<String> realLeaves,
  ) {
    String? bestProxy;
    String? bestNodeId;
    int? bestMs;
    for (final node in filterConnectableNodes(panelNodes)) {
      if (node.status == NodeStatus.offline) continue;
      final ms = pingCache[node.id];
      if (!_isValidPingMs(ms)) continue;
      final names = _sortLeavesByPreference(
        proxyNamesForPanelNode(node.name, realLeaves),
      );
      if (names.isEmpty) continue;
      if (bestMs == null || ms! < bestMs) {
        bestMs = ms;
        bestProxy = names.first;
        bestNodeId = node.id;
      }
    }
    if (bestProxy == null || bestNodeId == null) return null;
    return MihomoAutoPickResult(proxyName: bestProxy, nodeId: bestNodeId);
  }

  List<String> _sortLeavesByPreference(Iterable<String> leaves) {
    final list = leaves.toList();
    list.sort((a, b) => _leafPreferenceScore(b).compareTo(_leafPreferenceScore(a)));
    return list;
  }

  String? _pickFirstRealLeaf(Map<String, dynamic> proxies) {
    final leaves = _sortLeavesByPreference(realOutboundProxyNames(proxies));
    if (leaves.isEmpty) return null;
    return leaves.first;
  }

  List<String> _leafCandidates(Map<String, dynamic> proxies) {
    final realLeaves = realOutboundProxyNames(proxies).toSet();
    final group = resolveAutoSelectGroupName(proxies);
    var candidates = group == null
        ? <String>[]
        : _expandRealLeafMembers(
            proxies,
            _api.proxyGroupMembers(proxies[group] as Map<String, dynamic>?),
          );
    if (candidates.isEmpty) {
      for (final key in [
        '灵猫加速器',
        '🚀 节点选择',
        '节点选择',
        'Proxy',
        'PROXY',
        'GLOBAL',
      ]) {
        final g = proxies[key] as Map<String, dynamic>?;
        if (g == null) continue;
        candidates = _expandRealLeafMembers(proxies, _api.proxyGroupMembers(g));
        if (candidates.isNotEmpty) break;
      }
    }
    if (candidates.isEmpty) {
      candidates = realLeaves.toList();
    }
    return _sortLeavesByPreference(
      candidates.where(realLeaves.contains),
    );
  }

  Future<String?> _pickFastestLeaf(
    List<String> candidates, {
    int? timeoutMs,
  }) async {
    String? best;
    int? bestMs;
    for (final leaf in candidates) {
      final ms = await _api.testProxyDelay(leaf, timeoutMs: timeoutMs);
      if (ms != null && (bestMs == null || ms < bestMs)) {
        bestMs = ms;
        best = leaf;
      }
    }
    return best;
  }

  /// 连接时并行探测前几个候选，避免串行测速拖慢连接
  Future<String?> _pickFastestLeafParallel(
    List<String> candidates, {
    int maxProbe = 3,
    int? timeoutMs,
  }) async {
    if (candidates.isEmpty) return null;
    final probe = candidates.take(maxProbe).toList();
    final results = await Future.wait(
      probe.map((leaf) async {
        final ms = await _api.testProxyDelay(leaf, timeoutMs: timeoutMs);
        return (leaf: leaf, ms: ms);
      }),
    );
    String? best;
    int? bestMs;
    for (final r in results) {
      if (r.ms != null && (bestMs == null || r.ms! < bestMs)) {
        bestMs = r.ms;
        best = r.leaf;
      }
    }
    return best;
  }

  List<String> _collectPanelOutboundCandidates(
    List<VpnNode> panelNodes,
    Set<String> realLeaves,
    Map<String, dynamic> proxies,
  ) {
    final candidates = <String>[];
    for (final node in filterConnectableNodes(panelNodes)) {
      if (node.status == NodeStatus.offline) continue;
      for (final matched in proxyNamesForPanelNode(node.name, realLeaves)) {
        if (!candidates.contains(matched)) candidates.add(matched);
      }
    }
    if (candidates.isEmpty) {
      candidates.addAll(_leafCandidates(proxies));
    }
    return _sortLeavesByPreference(candidates);
  }

  /// 连接专用：优先测速缓存，否则并行短超时探测，避免重复选路
  Future<MihomoAutoPickResult?> _pickOutboundForConnect(
    List<VpnNode> panelNodes, {
    Map<String, int>? pingCache,
  }) async {
    if (!await _api.isAlive()) return null;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final realLeaves = realOutboundProxyNames(proxies).toSet();
    if (realLeaves.isEmpty) return null;

    if (pingCache != null && pingCache.isNotEmpty) {
      final cached = _pickBestFromPingCache(panelNodes, pingCache, realLeaves);
      if (cached != null) return cached;
    }

    final sorted = _collectPanelOutboundCandidates(
      panelNodes,
      realLeaves,
      proxies,
    );
    if (sorted.isEmpty) return null;

    final timeoutMs = Platform.isWindows ? 8000 : 12000;
    final maxProbe = Platform.isWindows ? 3 : 5;
    final pick = await _pickFastestLeafParallel(
      sorted,
      maxProbe: maxProbe,
      timeoutMs: timeoutMs,
    );
    if (pick == null) return null;
    return _pickResultForPanel(panelNodes, pick) ??
        MihomoAutoPickResult(proxyName: pick, nodeId: '');
  }

  Future<void> _applyOutboundPick(
    Map<String, dynamic> proxies,
    String leaf,
  ) async {
    if (Platform.isIOS) return;
    await _api.setMode('global');
    await _selectProxyInAllGroups(proxies, leaf);
    try {
      await _api.closeAllConnections();
    } catch (_) {}
  }

  /// 测速挑选有延迟的最快节点；有 URLTest 组则走组，否则从主策略组选
  Future<String?> selectAutoProxy() async {
    if (!isSupported) return null;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final candidates = _leafCandidates(proxies);
    if (candidates.isEmpty) return null;

    final group = resolveAutoSelectGroupName(proxies);
    if (group != null) {
      final best = await _pickFastestLeaf(candidates);
      if (best != null) {
        try {
          await _api.selectProxy(group, best);
        } catch (_) {}
        await _selectProxyInAllGroups(proxies, best);
        return best;
      }
      await _api.testProxyDelay(group);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final now = _matchRealOutboundLeaf(await _api.proxyNow(group), proxies);
      if (now != null) {
        final nowMs = await _api.testProxyDelay(now);
        if (nowMs != null) {
          await _selectProxyInAllGroups(proxies, now);
          return now;
        }
      }
    }

    final best = await _pickFastestLeaf(candidates);
    if (best != null) {
      await _selectProxyInAllGroups(proxies, best);
    }
    return best;
  }

  /// 用面板节点列表在已运行的 mihomo 上测速，选最快节点并写入策略组
  Future<MihomoAutoPickResult?> pickBestFromAppNodes(
    List<VpnNode> nodes, {
    Map<String, int>? pingCache,
  }) async {
    if (!isSupported || !await _api.isAlive()) return null;
    final connectable = filterConnectableNodes(nodes);
    if (connectable.isEmpty) return null;

    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final leaves = realOutboundProxyNames(proxies).toSet();
    if (leaves.isEmpty) return null;

    if (pingCache != null && pingCache.isNotEmpty) {
      final cached = _pickBestFromPingCache(connectable, pingCache, leaves);
      if (cached != null) {
        await _api.setMode('global');
        await _selectProxyInAllGroups(proxies, cached.proxyName);
        try {
          await _api.closeAllConnections();
        } catch (_) {}
        return cached;
      }
    }

    String? bestProxy;
    String? bestNodeId;
    int? bestMs;

    for (final node in connectable) {
      if (node.status == NodeStatus.offline) continue;

      final testNames = proxyNamesForPanelNode(node.name, leaves);
      if (testNames.isEmpty) continue;

      for (final proxy in testNames) {
        final ms = await _api.testProxyDelay(proxy);
        if (ms != null && (bestMs == null || ms < bestMs)) {
          bestMs = ms;
          bestProxy = proxy;
          bestNodeId = node.id;
        }
      }
    }

    if (bestProxy == null || bestNodeId == null) return null;

    await _api.setMode('global');
    await _selectProxyInAllGroups(proxies, bestProxy);
    try {
      await _api.closeAllConnections();
    } catch (_) {}

    return MihomoAutoPickResult(proxyName: bestProxy, nodeId: bestNodeId);
  }

  MihomoAutoPickResult? _pickResultForPanel(
    List<VpnNode> panelNodes,
    String leaf,
  ) {
    MihomoAutoPickResult? best;
    var bestScore = -1;
    for (final node in filterConnectableNodes(panelNodes)) {
      final score = _panelNodeMatchScore(node.name, leaf);
      if (score > bestScore) {
        bestScore = score;
        best = MihomoAutoPickResult(proxyName: leaf, nodeId: node.id);
      }
    }
    return best;
  }

  /// 读取当前出站节点（不改动 mihomo 选择）
  Future<MihomoAutoPickResult?> readOutboundForPanel(
    List<VpnNode> panelNodes,
  ) async {
    if (!isSupported || !await _api.isAlive()) return null;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final leaf = sanitizeProxyLeaf(
      await resolveCurrentOutboundLeaf(),
      proxies: proxies,
    );
    if (leaf == null) return null;
    return _pickResultForPanel(panelNodes, leaf);
  }

  /// 确保选中真实出站节点（展开 COMPATIBLE 等嵌套策略组）
  Future<MihomoAutoPickResult?> ensureOutboundForPanel(
    List<VpnNode> panelNodes, {
    Map<String, int>? pingCache,
  }) async {
    if (!isSupported || !await _api.isAlive()) return null;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final realLeaves = realOutboundProxyNames(proxies).toSet();
    if (realLeaves.isEmpty) return null;

    final current = sanitizeProxyLeaf(
      await resolveCurrentOutboundLeaf(),
      proxies: proxies,
    );
    if (current != null && isRealOutboundProxy(current, proxies)) {
      final currentResult = _pickResultForPanel(panelNodes, current);
      int? cachedMs;
      if (currentResult != null && pingCache != null) {
        cachedMs = pingCache[currentResult.nodeId];
      }
      var keepCurrent = _isValidPingMs(cachedMs);
      if (!keepCurrent) {
        keepCurrent = await _api.testProxyDelay(current) != null;
      }
      if (keepCurrent) {
        await _api.setMode('global');
        await _selectProxyInAllGroups(proxies, current);
        try {
          await _api.closeAllConnections();
        } catch (_) {}
        return currentResult ??
            MihomoAutoPickResult(proxyName: current, nodeId: '');
      }
    }

    final candidates = <String>[];
    final idByProxy = <String, String>{};
    for (final node in filterConnectableNodes(panelNodes)) {
      if (node.status == NodeStatus.offline) continue;
      for (final matched in proxyNamesForPanelNode(node.name, realLeaves)) {
        if (candidates.contains(matched)) continue;
        candidates.add(matched);
        idByProxy[matched] = node.id;
      }
    }
    if (candidates.isEmpty) {
      for (final leaf in _leafCandidates(proxies)) {
        candidates.add(leaf);
        final panelMatch = _pickResultForPanel(panelNodes, leaf);
        idByProxy[leaf] = panelMatch?.nodeId ?? '';
      }
    }
    if (candidates.isEmpty) return null;

    final sortedCandidates = _sortLeavesByPreference(candidates);
    var pickResult = pingCache != null && pingCache.isNotEmpty
        ? _pickBestFromPingCache(panelNodes, pingCache, realLeaves)
        : null;
    var pick = pickResult?.proxyName;
    pick ??= await _pickFastestLeaf(sortedCandidates);
    if (pick == null) return null;
    pickResult ??= _pickResultForPanel(panelNodes, pick);

    await _api.setMode('global');
    await _selectProxyInAllGroups(proxies, pick);
    try {
      await _api.closeAllConnections();
    } catch (_) {}

    final nodeId = pickResult != null && pickResult.nodeId.isNotEmpty
        ? pickResult.nodeId
        : (idByProxy[pick]?.isNotEmpty == true
            ? idByProxy[pick]!
            : (_pickResultForPanel(panelNodes, pick)?.nodeId ?? ''));
    return MihomoAutoPickResult(proxyName: pick, nodeId: nodeId);
  }

  String? _matchRealOutboundLeaf(
    String? name,
    Map<String, dynamic> proxies,
  ) {
    if (name == null || name.isEmpty) return null;
    final trimmed = name.trim();
    if (isRealOutboundProxy(trimmed, proxies)) return trimmed;
    final realLeaves = realOutboundProxyNames(proxies).toSet();
    final matched = matchProxyName(trimmed, realLeaves);
    if (matched != null && isRealOutboundProxy(matched, proxies)) return matched;
    return null;
  }

  Future<String?> _followProxyChain(
    String start,
    Map<String, dynamic> proxies,
  ) async {
    var name = start.trim();
    for (var i = 0; i < 12; i++) {
      final leaf = _matchRealOutboundLeaf(name, proxies);
      if (leaf != null) return leaf;

      final item = proxies[name];
      if (item is! Map<String, dynamic>) break;
      if (!isProxyGroupEntry(item)) break;

      var now = item['now']?.toString().trim();
      if (now == null || now.isEmpty) {
        now = await _api.proxyNow(name);
      }
      if (now == null || now.isEmpty) break;
      name = now;
    }
    return _matchRealOutboundLeaf(name, proxies);
  }

  /// 从主策略组 / GLOBAL 链解析当前实际出站节点（不依赖测速）
  Future<String?> resolveCurrentOutboundLeaf() async {
    if (!isSupported || !await _api.isAlive()) return null;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    if (proxies.isEmpty) return null;

    const preferred = [
      '灵猫加速器',
      '🚀 节点选择',
      '节点选择',
      'Proxy',
      'PROXY',
      'GLOBAL',
    ];
    for (final group in preferred) {
      if (!proxies.containsKey(group)) continue;
      final leaf = await _followProxyChain(group, proxies);
      if (leaf != null) return leaf;
    }
    return null;
  }

  /// 从 GLOBAL 策略链解析当前实际出站节点
  Future<String?> resolveActiveLeaf() => resolveCurrentOutboundLeaf();

  /// 查询当前自动选择组实际使用的节点
  Future<String?> currentAutoSelectedLeaf() async {
    if (!isSupported || !await _api.isAlive()) return null;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final group = resolveAutoSelectGroupName(proxies);
    if (group == null) return null;
    final now = await _api.proxyNow(group);
    return _matchRealOutboundLeaf(now, proxies);
  }

  /// 载入订阅并执行自动选节点（未连接时用于预览；测完可按需还原 mihomo）
  Future<String?> runAutoPick({
    required String clashYaml,
    bool keepAlive = false,
  }) async {
    if (!isSupported) return null;
    final wasAliveAtStart = await _api.isAlive();
    final vpnActive =
        (Platform.isAndroid || Platform.isIOS) && await VpnBridge.isActive();

    if (!vpnActive) {
      final config = _prepareConfig(clashYaml, forVpnTunnel: false);
      await _restartWithConfig(config, maxAttempts: 60);
    }

    String? leaf;
    try {
      leaf = await selectAutoProxy();
    } finally {
      if (!keepAlive && !wasAliveAtStart && !vpnActive) {
        await MihomoBridge.stop();
        if (!Platform.isAndroid && !Platform.isIOS) {
          await _writeBaseConfig();
          final path = await MihomoPaths.configFile();
          await MihomoBridge.start(configPath: path);
        }
      }
    }
    return leaf;
  }

  Future<void> _selectProxyInAllGroups(
    Map<String, dynamic> proxies,
    String target,
  ) async {
    if (!isRealOutboundProxy(target, proxies)) return;
    if (isBuiltinPolicyProxyName(target)) return;
    final selectors = <String>[];
    for (final entry in proxies.entries) {
      final val = entry.value;
      if (val is Map && val['type'] == 'Selector') {
        selectors.add(entry.key);
      }
    }

    const preferred = [
      '灵猫加速器',
      '🚀 节点选择',
      '节点选择',
      'Proxy',
      'PROXY',
      'GLOBAL',
    ];
    final ordered = <String>[];
    for (final g in preferred) {
      if (proxies.containsKey(g)) ordered.add(g);
    }
    for (final g in selectors) {
      if (!ordered.contains(g)) ordered.add(g);
    }

    const mainGroups = {'灵猫加速器', '🚀 节点选择', '节点选择', 'Proxy', 'PROXY'};
    String? mainGroup;
    for (final g in mainGroups) {
      if (proxies.containsKey(g)) {
        mainGroup = g;
        break;
      }
    }

    for (final g in ordered) {
      try {
        final members = _api.proxyGroupMembers(
          proxies[g] as Map<String, dynamic>?,
        );
        if (g == 'GLOBAL') {
          if (members.contains(target)) {
            await _api.selectProxy(g, target);
          } else if (mainGroup != null && members.contains(mainGroup)) {
            await _api.selectProxy(g, mainGroup);
          }
          continue;
        }
        if (members.isEmpty || members.contains(target)) {
          await _api.selectProxy(g, target);
        }
      } catch (_) {}
    }
  }

  /// 切换节点时确保 Android 全局模式并刷新连接
  Future<void> confirmNodeSelection(String proxyName) async {
    if (!isSupported || proxyName.isEmpty) return;
    if (Platform.isIOS) return;
    if (Platform.isAndroid) {
      await MihomoBridge.applyNode(proxyName: proxyName);
      return;
    }
    await _api.setMode('global');
    await _applyNodeSelection(proxyName);
  }

  /// 连接后多次确认节点生效，并清理旧连接避免半开状态
  Future<void> _applyNodeSelection(String proxyName) async {
    if (!Platform.isIOS) {
      await _api.setMode('global');
    }
    final passes = Platform.isWindows ? 1 : 3;
    for (var i = 0; i < passes; i++) {
      await selectNode(proxyName);
      if (i < passes - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    try {
      await _api.closeAllConnections();
    } catch (_) {}
  }

  Future<bool> get isRunning => _api.isAlive();

  Future<String> getMode() => _api.getMode();

  Future<void> setMode(String mode) => _api.setMode(mode);

  /// [quiet] 为 true 时不抛错，仅返回是否就绪（Windows 预热探测用）。
  Future<bool> _waitUntilAlive({int? maxAttempts, bool quiet = false}) async {
    final attempts = maxAttempts ?? _aliveMaxAttempts;
    for (var i = 0; i < attempts; i++) {
      if (await _probeAlive()) return true;
      if (Platform.isWindows && i > 0 && i % 4 == 0) {
        final running = await MihomoBridge.isProcessRunning();
        if (running == false) {
          if (quiet) return false;
          final detail = await MihomoBridge.lastStartError();
          throw PanelApiException(
            detail != null && detail.isNotEmpty
                ? 'mihomo 启动失败：$detail'
                : 'mihomo 进程意外退出',
          );
        }
      }
      await Future<void>.delayed(_alivePollGap);
    }
    if (quiet) return false;
    final bin = await MihomoBridge.resolveBinary();
    if (bin == null) {
      throw PanelApiException(
        '未找到 mihomo 可执行文件。请安装：brew install mihomo，'
        '或将 mihomo 放入应用 Resources 目录。',
      );
    }
    final detail = await MihomoBridge.lastStartError();
    if (detail != null && detail.isNotEmpty) {
      throw PanelApiException('mihomo 启动失败：$detail');
    }
    throw PanelApiException('mihomo 启动超时，请检查配置与二进制权限');
  }

  Future<void> _writeBaseConfig() async {
    final dir = await MihomoPaths.workDir();
    await Directory(dir).create(recursive: true);
    final path = await MihomoPaths.configFile();
    await File(path).writeAsString(_minimalYaml());
  }

  String _minimalYaml() =>
      '''
mixed-port: ${AppConfig.mihomoMixedPort}
allow-lan: false
mode: rule
log-level: info
external-controller: ${AppConfig.mihomoControllerHost}:${AppConfig.mihomoControllerPort}
secret: ${AppConfig.mihomoSecret}
dns:
  enable: true
  enhanced-mode: fake-ip
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
''';

  Future<String> _buildConfigFromSubscription(
    String subscribeUrl, {
    AndroidVpnProfile? androidProfile,
    bool forVpnTunnel = false,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(subscribeUrl));
      req.headers.set('User-Agent', AppConfig.userAgent);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw PanelApiException('拉取 Clash 订阅失败：HTTP ${res.statusCode}');
      }
      final body = await res.transform(const SystemEncoding().decoder).join();
      return _prepareConfig(
        body,
        forVpnTunnel: forVpnTunnel,
        androidProfile: androidProfile,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _startViaVpnService(
    String config, {
    required String nodeLabel,
    String? proxyName,
  }) async {
    // ignore: avoid_print
    print('[VPN] stopping previous session…');
    if (await VpnBridge.isActive()) {
      await VpnBridge.stop();
    }
    if (await _api.isAlive()) {
      await MihomoBridge.stop();
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final path = await MihomoPaths.configFile();
    await Directory(await MihomoPaths.workDir()).create(recursive: true);
    await File(path).writeAsString(config);
    try {
      // ignore: avoid_print
      print('[VPN] native start…');
      await VpnBridge.start(
        nodeName: nodeLabel,
        configPath: path,
        proxyName: proxyName ?? nodeLabel,
      );
      // ignore: avoid_print
      print('[VPN] native start returned, waiting tunnel…');
    } catch (e) {
      await MihomoBridge.stop();
      rethrow;
    }

    final waitSeconds = Platform.isAndroid ? 60 : 25;
    final startedAt = DateTime.now();
    final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
    while (DateTime.now().isBefore(deadline)) {
      if (await VpnBridge.isActive()) {
        return;
      }
      if (DateTime.now().difference(startedAt) >
          const Duration(milliseconds: 1500)) {
        final detail = await MihomoBridge.lastStartError();
        if (detail != null && detail.isNotEmpty) {
          throw PanelApiException('VPN 启动失败：$detail');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    final detail = await MihomoBridge.lastStartError();
    throw PanelApiException(
      detail != null && detail.isNotEmpty
          ? 'VPN 启动失败：$detail'
          : 'VPN 隧道未建立，请确认已授予 VPN 权限后重试',
    );
  }

  Future<void> _restartWithConfig(
    String config, {
    int? maxAttempts,
    int? assertRetries,
  }) async {
    final attempts = maxAttempts ?? (Platform.isWindows ? 80 : 60);
    Future<void> once() async {
      final path = await MihomoPaths.configFile();
      await Directory(await MihomoPaths.workDir()).create(recursive: true);
      await File(path).writeAsString(config);
      await MihomoBridge.stop();
      await Future<void>.delayed(
        Duration(milliseconds: Platform.isWindows ? 900 : 400),
      );
      final started = await MihomoBridge.start(configPath: path);
      if (!started) {
        final detail = await MihomoBridge.lastStartError();
        throw PanelApiException(
          detail != null && detail.isNotEmpty
              ? 'mihomo 启动失败：$detail'
              : 'mihomo 启动失败',
        );
      }
      if (!await _waitUntilAlive(maxAttempts: attempts)) {
        throw PanelApiException('mihomo 启动超时，请检查配置与二进制权限');
      }
      if (!await _probeAlive()) {
        throw PanelApiException('mihomo 启动后无响应，请重试');
      }
      await _assertOutboundProxiesLoaded(retries: assertRetries);
    }

    try {
      await once();
    } on PanelApiException catch (e) {
      if (!Platform.isWindows) rethrow;
      final retriable = e.message.contains('启动超时') ||
          e.message.contains('未加载订阅节点');
      if (!retriable) rethrow;
      await MihomoBridge.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      await once();
    }
  }

  Future<void> _assertOutboundProxiesLoaded({int? retries}) async {
    final maxRetries = retries ?? (Platform.isWindows ? 8 : 6);
    final gap = Platform.isWindows
        ? const Duration(milliseconds: 200)
        : const Duration(milliseconds: 200);
    for (var i = 0; i < maxRetries; i++) {
      final data = await _api.proxies();
      final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
      final real = realOutboundProxyNames(proxies);
      if (real.isNotEmpty) return;
      if (i < maxRetries - 1) await Future<void>.delayed(gap);
    }
    await MihomoBridge.stop();
    throw PanelApiException(
      'mihomo 未加载订阅节点：9090 端口可能被其他 mihomo 进程占用。'
      '请完全退出应用，在任务管理器中结束所有 mihomo 相关进程后重试',
    );
  }

  String _prepareConfig(
    String body, {
    bool forVpnTunnel = false,
    AndroidVpnProfile? androidProfile,
  }) {
    _ensureClashYaml(body);
    return _mergeControllerBlock(
      body,
      forVpnTunnel: forVpnTunnel,
      androidProfile: androidProfile,
    );
  }

  void _ensureClashYaml(String body) {
    final text = body.trimLeft();
    final lower = text.toLowerCase();
    if (lower.startsWith('<!doctype html') ||
        lower.startsWith('<html') ||
        lower.contains('<div id="root"')) {
      throw PanelApiException('订阅链接返回的是网页，不是 Clash 配置，请检查订阅地址');
    }
    if (!text.contains('proxies:') && !text.contains('proxy-groups:')) {
      throw PanelApiException('订阅内容不是有效的 Clash 配置');
    }
    _ensureProxiesPresent(text);
  }

  void _ensureProxiesPresent(String text) {
    final proxiesStart = text.indexOf(RegExp(r'^proxies:\s*$', multiLine: true));
    if (proxiesStart < 0) {
      throw PanelApiException('订阅配置缺少 proxies 节点列表');
    }
    final tail = text.substring(proxiesStart);
    final endMatch = RegExp(
      r'^(proxy-groups|rules|rule-providers|listeners):\s*$',
      multiLine: true,
    ).firstMatch(tail.substring('proxies:'.length));
    final proxiesText = endMatch == null
        ? tail
        : tail.substring(0, endMatch.start + 'proxies:'.length);
    final hasProxyEntry = RegExp(
      r'-\s*(?:name\s*:|(?:\{[^}]*\bname\s*:))',
      multiLine: true,
    ).hasMatch(proxiesText);
    if (!hasProxyEntry) {
      throw PanelApiException(
        '订阅中没有可用节点（proxies 为空）。请在面板重置订阅后重试，'
        '或确认套餐未过期。',
      );
    }
  }

  String _mergeControllerBlock(
    String clashYaml, {
    bool forVpnTunnel = false,
    AndroidVpnProfile? androidProfile,
  }) {
    if (forVpnTunnel) {
      return _mergeVpnMinimalBlock(
        clashYaml,
        androidProfile: androidProfile,
      );
    }
    // 桌面端替换 DNS、注入 GLOBAL、精简规则
    final dnsBlock = '''
dns:
  enable: true
  enhanced-mode: redir-host
  nameserver:
    - 223.5.5.5
    - 8.8.8.8
  default-nameserver:
    - 223.5.5.5
    - 114.114.114.114
''';
    const useGlobalMode = true;
    final header =
        '''
mixed-port: ${AppConfig.mihomoMixedPort}
allow-lan: false
mode: global
log-level: info
external-controller: ${AppConfig.mihomoControllerHost}:${AppConfig.mihomoControllerPort}
secret: ${AppConfig.mihomoSecret}
$dnsBlock''';
    var body = clashYaml.trimLeft();
    for (final key in [
      'mixed-port:',
      'external-controller:',
      'secret:',
      'port:',
      'socks-port:',
      'allow-lan:',
      'bind-address:',
      'mode:',
      'log-level:',
      'unified-delay:',
      'tcp-concurrent:',
      'sniffer:',
    ]) {
      body = body.replaceAll(RegExp('^$key.*\n', multiLine: true), '');
    }
    body = body.replaceFirst(
      RegExp(r'^dns:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    body = body.replaceFirst(
      RegExp(r'^sniffer:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    // 订阅已有 GLOBAL；桌面端重复注入会破坏 4 空格 flow 列表（macOS line 23 YAML 错误）
    body = _simplifyRules(
      body,
      forVpnTunnel: false,
      useGlobalMode: useGlobalMode,
      androidProfile: androidProfile,
    );
    return '$header\n$body';
  }

  /// 手机 VPN：hev 负责 TUN；rule + 精简 rules（拦截 DoT）；fake-ip 对齐 mapdns
  String _mergeVpnMinimalBlock(
    String clashYaml, {
    AndroidVpnProfile? androidProfile,
  }) {
    final header =
        '''
mixed-port: ${AppConfig.mihomoMixedPort}
allow-lan: false
mode: rule
external-controller: ${AppConfig.mihomoControllerHost}:${AppConfig.mihomoControllerPort}
secret: ${AppConfig.mihomoSecret}
''';
    var body = clashYaml.trimLeft();
    for (final key in [
      'mixed-port:',
      'external-controller:',
      'secret:',
      'port:',
      'socks-port:',
      'allow-lan:',
      'mode:',
    ]) {
      body = body.replaceAll(RegExp('^$key.*\n', multiLine: true), '');
    }
    body = body.replaceFirst(
      RegExp(r'^sniffer:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    body = body.replaceFirst(
      RegExp(r'^tun:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    body = body.replaceFirst(
      RegExp(r'^rule-providers:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    body = _configureVpnTunnelStack(body, androidProfile: androidProfile);
    // 订阅通常已有 GLOBAL；重复注入会与 4 空格 flow 列表混排导致 line 29 YAML 错误
    body = _simplifyRules(
      body,
      forVpnTunnel: true,
      useGlobalMode: true,
      androidProfile: androidProfile,
    );
    return '$header\n$body';
  }

  /// hev mapdns 负责 DNS 并经 SOCKS 传域名；鸿蒙额外开 fake-ip 兜底
  String _configureVpnTunnelStack(
    String body, {
    AndroidVpnProfile? androidProfile,
  }) {
    body = body.replaceFirst(
      RegExp(r'^dns:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    body = body.replaceFirst(
      RegExp(r'^sniffer:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    final harmony = androidProfile?.kind == 'HARMONY';
    final dnsBlock = harmony
        ? '''dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 240.0.0.0/4
  fake-ip-filter:
    - '+.lan'
    - '+.local'
  default-nameserver:
    - 223.5.5.5
    - 114.114.114.114
  nameserver:
    - 223.5.5.5
    - 8.8.8.8
'''
        : '''dns:
  enable: false
''';
    const snifferBlock = '''sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]
''';
    return '$dnsBlock$snifferBlock$body';
  }

  /// 注入 GLOBAL 组指向主策略组，global 模式下流量才能进入订阅节点
  String _ensureGlobalGroup(String body) {
    var main = _resolveMatchGroup(body);
    if (main == 'GLOBAL') main = '灵猫加速器';
    // 移除错误/旧的 GLOBAL 定义（含自引用 proxies: [GLOBAL]）
    body = body.replaceAll(
      RegExp(r'^\s*-\s*\{ name: GLOBAL,[^\n]*\}\s*\n', multiLine: true),
      '',
    );
    body = body.replaceAll(
      RegExp(
        r'^\s*-\s*name:\s*GLOBAL\s*\n(?:\s+.+\n)*',
        multiLine: true,
      ),
      '',
    );
    final pgStart = body.indexOf(RegExp(r'^proxy-groups:\s*$', multiLine: true));
    if (pgStart < 0) return body;
    final insertAt = body.indexOf('\n', pgStart);
    if (insertAt < 0) return body;
    final needsQuote = RegExp(r'''[\s,\[\]'"]|[^\x00-\x7F]''').hasMatch(main);
    final mainRef = needsQuote ? "'$main'" : main;
    final entry =
        '  - { name: GLOBAL, type: select, proxies: [$mainRef] }\n';
    return body.substring(0, insertAt + 1) + entry + body.substring(insertAt + 1);
  }

  /// 内嵌 mihomo 不下载 GEOIP 库；用精简规则保证秒级启动
  String _simplifyRules(
    String body, {
    bool forVpnTunnel = false,
    bool useGlobalMode = false,
    AndroidVpnProfile? androidProfile,
  }) {
    final rulesStart = body.indexOf(RegExp(r'^rules:', multiLine: true));
    if (rulesStart < 0) return body;
    final matchGroup = _resolveMatchGroup(body);
    final profile = androidProfile ?? AndroidVpnProfile.stock;
    final quicRule = profile.blockQuic
        ? '  - AND,((NETWORK,UDP),(DST-PORT,443)),REJECT\n'
        : '';
    final dotRules = profile.blockDoT
        ? '  - AND,((NETWORK,UDP),(DST-PORT,853)),REJECT\n'
            '  - AND,((NETWORK,TCP),(DST-PORT,853)),REJECT\n'
        : '';
    final matchTarget = useGlobalMode ? 'GLOBAL' : matchGroup;
    final minimalRules = '''
rules:
  - DOMAIN,user.panlink.site,DIRECT
$quicRule$dotRules  - MATCH,$matchTarget
''';
    return '${body.substring(0, rulesStart).trimRight()}\n$minimalRules';
  }

  List<String> _extractLeafNames(String yaml) {
    final proxiesStart = yaml.indexOf(RegExp(r'^proxies:\s*$', multiLine: true));
    final pgStart = yaml.indexOf(RegExp(r'^proxy-groups:\s*$', multiLine: true));
    if (proxiesStart < 0) return const [];
    final end = pgStart > proxiesStart ? pgStart : yaml.length;
    final section = yaml.substring(proxiesStart, end);
    final names = <String>[];
    for (final m in RegExp(
      r'^\s*-\s*name:\s*(.+)$',
      multiLine: true,
    ).allMatches(section)) {
      names.add(m.group(1)!.trim().replaceAll(RegExp(r'''^["']|["']$'''), ''));
    }
    for (final m in RegExp(
      r'\{[^}]*\bname:\s*[''"]?([^,''"\n}]+)[''"]?',
      multiLine: true,
    ).allMatches(section)) {
      names.add(m.group(1)!.trim());
    }
    return names.toSet().toList();
  }

  String? _resolveLeafFromYaml(String yaml, String nodeLabel) {
    return matchProxyName(nodeLabel, _extractLeafNames(yaml));
  }

  /// 手机 VPN 启动前解析 mihomo 内真实叶子名（含 📶 前缀匹配）
  String? _resolveOutboundProxyForConnect(
    String configYaml,
    String? proxyName,
    List<VpnNode>? panelNodes,
    Map<String, int>? pingCache,
  ) {
    final leaves = _extractLeafNames(configYaml)
        .where(isConnectableProxyName)
        .where((n) => !isReservedOutboundName(n))
        .toList();
    if (leaves.isEmpty) return null;

    final wantsAuto = proxyName == null ||
        proxyName.isEmpty ||
        isAutoSelectGroupName(proxyName);

    if (!wantsAuto) {
      return _resolveLeafFromYaml(configYaml, proxyName!) ??
          matchProxyName(proxyName, leaves);
    }

    if (panelNodes != null && pingCache != null && pingCache.isNotEmpty) {
      String? bestLeaf;
      int? bestMs;
      for (final node in filterConnectableNodes(panelNodes)) {
        final ms = pingCache[node.id];
        if (ms == null || ms <= 0 || ms >= 10000) continue;
        final leaf = _resolveLeafFromYaml(configYaml, node.name) ??
            matchProxyName(node.name, leaves);
        if (leaf == null) continue;
        if (bestMs == null || ms < bestMs) {
          bestMs = ms;
          bestLeaf = leaf;
        }
      }
      if (bestLeaf != null) return bestLeaf;
    }

    // 自动选择：优先带倍率后缀的节点（通常更稳定）
    for (final leaf in leaves) {
      if (hasProxyTierSuffix(leaf)) return leaf;
    }
    final real =
        leaves.where((n) => !isSubscriptionInfoNode(n)).toList();
    if (real.isNotEmpty) return real.first;
    return leaves.first;
  }

  /// 把选中节点排到各策略组 proxies 列表首位（mihomo 默认选第一个）
  String _pinSelectedProxyInConfig(String yaml, String nodeLabel) {
    final pgStart = yaml.indexOf(RegExp(r'^proxy-groups:\s*$', multiLine: true));
    if (pgStart < 0) return yaml;
    final resolved = _resolveLeafFromYaml(yaml, nodeLabel);
    if (resolved == null) return yaml;

    final lines = yaml.split('\n');
    final out = <String>[];
    var inProxyGroups = false;
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim() == 'proxy-groups:') {
        inProxyGroups = true;
      }
      if (inProxyGroups && line.trim() == 'proxies:') {
        out.add(line);
        i++;
        final entries = <String>[];
        while (i < lines.length) {
          final entry = lines[i];
          if (entry.trim().startsWith('- ')) {
            entries.add(entry);
            i++;
            continue;
          }
          break;
        }
        String entryName(String e) =>
            e.trim().substring(2).trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
        const sinkNames = {
          'COMPATIBLE',
          '自动选择',
          '🚀 自动选择',
          '♻️ 自动选择',
          '故障转移',
          'Auto',
          'AUTO',
          'DIRECT',
          'REJECT',
          'GLOBAL',
        };
        final selected =
            entries.where((e) => entryName(e) == resolved).toList();
        final sunk =
            entries.where((e) => sinkNames.contains(entryName(e))).toList();
        final rest = entries.where((e) {
          final n = entryName(e);
          return n != resolved && !sinkNames.contains(n);
        }).toList();
        out.addAll(selected);
        out.addAll(rest);
        out.addAll(sunk);
        continue;
      }
      out.add(line);
      i++;
    }
    return out.join('\n');
  }

  String _resolveMatchGroup(String body) {
    final pgStart = body.indexOf('proxy-groups:');
    if (pgStart < 0) return 'GLOBAL';
    var section = body.substring(pgStart);
    final rulesIdx = section.indexOf(RegExp(r'^rules:\s*$', multiLine: true));
    if (rulesIdx > 0) section = section.substring(0, rulesIdx);
    final names = RegExp(r'^\s*-\s*name:\s*(.+)$', multiLine: true)
        .allMatches(section)
        .map((m) => m.group(1)!.trim())
        .toList();
    const preferred = [
      '灵猫加速器',
      '🚀 节点选择',
      '节点选择',
      'Proxy',
      'PROXY',
    ];
    for (final p in preferred) {
      if (names.contains(p)) return p;
    }
    for (final n in names) {
      if (n != 'GLOBAL' && n != 'DIRECT' && n != 'REJECT') return n;
    }
    return '灵猫加速器';
  }
}
