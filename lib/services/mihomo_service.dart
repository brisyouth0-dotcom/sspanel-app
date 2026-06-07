import 'dart:async';
import 'dart:io';

import '../config/app_config.dart';
import '../config/mihomo_paths.dart';
import '../models/models.dart';
import '../utils/proxy_name_match.dart';
import 'mihomo_api.dart';
import 'mihomo_bridge.dart';
import 'panel_exceptions.dart';
import 'vpn_bridge.dart';

/// 管理 mihomo 配置写入、进程生命周期与节点选择
class MihomoService {
  MihomoService({MihomoApi? api}) : _api = api ?? MihomoApi();

  final MihomoApi _api;

  bool _bootstrapped = false;

  bool get isSupported => MihomoBridge.supported;

  Future<void> bootstrap() async {
    if (!isSupported || _bootstrapped) return;
    // Android / iOS 在 VPN 连接时由原生层启动 mihomo
    if (Platform.isAndroid || Platform.isIOS) {
      _bootstrapped = true;
      return;
    }
    _bootstrapped = true;
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
    // 冷启动不阻塞等待，连接/测速时会自行等待就绪
    unawaited(_waitUntilAlive(maxAttempts: 40).catchError((_) {}));
  }

  Future<void> connect({
    String? clashSubscribeUrl,
    String? clashYaml,
    String? proxyName,
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
    if (proxyName != null &&
        proxyName.isNotEmpty &&
        (Platform.isAndroid || Platform.isIOS)) {
      config = _pinSelectedProxyInConfig(config, proxyName);
    }
    if (mobileVpn) {
      await _startViaVpnService(
        config,
        nodeLabel: proxyName ?? '—',
        proxyName: proxyName,
      );
    } else {
      await _restartWithConfig(config);
    }

    if (proxyName != null && proxyName.isNotEmpty) {
      if (Platform.isAndroid) {
        // 节点已在 StarVpnService 建 TUN 前由原生层选中
      } else if (mobileVpn && !Platform.isIOS) {
        await _api.setMode('global');
        await _applyNodeSelection(proxyName);
      } else if (!Platform.isIOS) {
        await _applyNodeSelection(proxyName);
      }
    }
  }

  /// 使用 mihomo 内核对各节点做延迟测试（与 Clash Verge 相同方式）
  Future<Map<String, int>> speedTest({
    required List<VpnNode> nodes,
    required String clashYaml,
    void Function(String nodeId, int ms)? onProgress,
  }) async {
    if (!isSupported) {
      throw PanelApiException('当前平台不支持 mihomo 测速');
    }
    final wasAliveAtStart = await _api.isAlive();
    final vpnActive =
        (Platform.isAndroid || Platform.isIOS) && await VpnBridge.isActive();

    // 已连接 / mihomo 已在跑：直接测延迟，禁止重启（Android 上会打断 VPN 并卡 UI）
    if (!wasAliveAtStart && !vpnActive) {
      final config = _prepareConfig(clashYaml, forVpnTunnel: false);
      await _restartWithConfig(config, maxAttempts: 60);
    }

    final proxyData = await _api.proxies();
    final allProxies = proxyData['proxies'] as Map<String, dynamic>? ?? {};
    final leafNames = leafProxyNames(allProxies);

    final results = <String, int>{};
    for (final node in nodes) {
      if (node.status == NodeStatus.offline) continue;
      final proxyName = matchProxyName(node.name, leafNames);
      if (proxyName == null) continue;
      final ms = await _api.testProxyDelay(proxyName);
      if (ms != null) {
        results[node.id] = ms;
        onProgress?.call(node.id, ms);
      }
    }

    if (!wasAliveAtStart && !vpnActive) {
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
    await MihomoBridge.stop();
    await _writeBaseConfig();
    final path = await MihomoPaths.configFile();
    await MihomoBridge.start(configPath: path);
  }

  Future<void> selectNode(String proxyName) async {
    if (!isSupported) return;
    final data = await _api.proxies();
    final proxies = data['proxies'] as Map<String, dynamic>? ?? {};
    final leafNames = leafProxyNames(proxies);
    final resolved = matchProxyName(proxyName, leafNames) ?? proxyName;

    final selectors = <String>[];
    for (final entry in proxies.entries) {
      final val = entry.value;
      if (val is Map && val['type'] == 'Selector') {
        selectors.add(entry.key);
      }
    }

    // 必须更新所有 Selector（含规则里的「节点选择」），不能只改 GLOBAL 就返回
    const preferred = [
      'GLOBAL',
      '🚀 节点选择',
      '节点选择',
      'Proxy',
      'PROXY',
      '灵猫加速器',
    ];
    final ordered = <String>[];
    for (final g in preferred) {
      if (proxies.containsKey(g)) ordered.add(g);
    }
    for (final g in selectors) {
      if (!ordered.contains(g)) ordered.add(g);
    }
    for (final g in ordered) {
      try {
        await _api.selectProxy(g, resolved);
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
    for (var i = 0; i < 3; i++) {
      await selectNode(proxyName);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    try {
      await _api.closeAllConnections();
    } catch (_) {}
  }

  Future<bool> get isRunning => _api.isAlive();

  Future<String> getMode() => _api.getMode();

  Future<void> setMode(String mode) => _api.setMode(mode);

  Future<void> _waitUntilAlive({int maxAttempts = 50}) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (await _api.isAlive()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
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
    await VpnBridge.stop();
    await MihomoBridge.stop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
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

    final waitSeconds = Platform.isAndroid ? 40 : 25;
    final deadline = DateTime.now().add(Duration(seconds: waitSeconds));
    while (DateTime.now().isBefore(deadline)) {
      final tunnelUp = await VpnBridge.isActive();
      final controllerUp = await _api.isAlive();
      if (Platform.isIOS) {
        if (tunnelUp) return;
      } else if (Platform.isAndroid) {
        if (tunnelUp) {
          // ignore: avoid_print
          print('[VPN] tunnel flag active');
          return;
        }
      } else if (tunnelUp && controllerUp) {
        return;
      } else if (controllerUp) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final detail = await MihomoBridge.lastStartError();
    throw PanelApiException(
      detail != null && detail.isNotEmpty
          ? 'VPN 启动失败：$detail'
          : 'VPN 隧道未建立，请确认已授予 VPN 权限后重试',
    );
  }

  Future<void> _restartWithConfig(String config, {int maxAttempts = 60}) async {
    final path = await MihomoPaths.configFile();
    await Directory(await MihomoPaths.workDir()).create(recursive: true);
    await File(path).writeAsString(config);
    await MihomoBridge.stop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final started = await MihomoBridge.start(configPath: path);
    if (!started) {
      final detail = await MihomoBridge.lastStartError();
      throw PanelApiException(
        detail != null && detail.isNotEmpty
            ? 'mihomo 启动失败：$detail'
            : 'mihomo 启动失败',
      );
    }
    await _waitUntilAlive(maxAttempts: maxAttempts);
    if (!await _api.isAlive()) {
      throw PanelApiException('mihomo 启动后无响应，请重试');
    }
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
    final dnsBlock = forVpnTunnel
        ? '''
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
  default-nameserver:
    - 223.5.5.5
    - 114.114.114.114
'''
        : '''
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 8.8.8.8
''';
    // VPN 用 global + GLOBAL 组；节点由 ConfigYamlPinner / 原生路由选定（规则里不能写含 [] 的节点名）
    final modeLine = forVpnTunnel ? 'global' : 'rule';
    final tunTuning = forVpnTunnel
        ? '''
tcp-concurrent: true
unified-delay: true
'''
        : '';
    final header =
        '''
mixed-port: ${AppConfig.mihomoMixedPort}
allow-lan: false
mode: $modeLine
log-level: info
external-controller: ${AppConfig.mihomoControllerHost}:${AppConfig.mihomoControllerPort}
secret: ${AppConfig.mihomoSecret}
$tunTuning$dnsBlock''';
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
    // 移除订阅里整块 dns / sniffer 配置，避免与后续扩展冲突
    body = body.replaceFirst(
      RegExp(r'^dns:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    body = body.replaceFirst(
      RegExp(r'^sniffer:\s*\n(?:[ \t].*\n)*', multiLine: true),
      '',
    );
    if (forVpnTunnel) {
      body = body.replaceFirst(
        RegExp(r'^tun:\s*\n(?:[ \t].*\n)*', multiLine: true),
        '',
      );
    }
    body = _simplifyRules(
      body,
      forVpnTunnel: forVpnTunnel,
      androidProfile: androidProfile,
    );
    return '$header\n$body';
  }

  /// 内嵌 mihomo 不下载 GEOIP 库；用精简规则保证秒级启动
  String _simplifyRules(
    String body, {
    bool forVpnTunnel = false,
    AndroidVpnProfile? androidProfile,
  }) {
    final rulesStart = body.indexOf(RegExp(r'^rules:\s*$', multiLine: true));
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
    final minimalRules = forVpnTunnel
        ? '''
rules:
  - DOMAIN,user.panlink.site,DIRECT
$quicRule$dotRules  - MATCH,GLOBAL
'''
        : '''
rules:
  - DOMAIN,user.panlink.site,DIRECT
  - MATCH,$matchGroup
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
        final selected =
            entries.where((e) => entryName(e) == resolved).toList();
        final directReject = entries
            .where((e) {
              final n = entryName(e);
              return n == 'DIRECT' || n == 'REJECT';
            })
            .toList();
        final rest = entries.where((e) {
          final n = entryName(e);
          return n != resolved && n != 'DIRECT' && n != 'REJECT';
        }).toList();
        out.addAll(selected);
        out.addAll(rest);
        out.addAll(directReject);
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
      '🚀 节点选择',
      '节点选择',
      'Proxy',
      'PROXY',
      'GLOBAL',
      '灵猫加速器',
    ];
    for (final p in preferred) {
      if (names.contains(p)) return p;
    }
    return names.isNotEmpty ? names.first : 'GLOBAL';
  }
}
