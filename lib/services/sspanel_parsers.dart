import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

/// 解析 SSPanel-UIM 服务端渲染页面（legacy JSON 不可用时的回退）。
class SspanelParsers {
  static String? universalSubUrl(String html) {
    final m1 = RegExp(r'id="universal-sub-link"[^>]*value="([^"]+)"').firstMatch(html);
    if (m1 != null) return m1.group(1);
    final m2 = RegExp(r'universalSubUrl:\s*"([^"]+)"').firstMatch(html);
    return m2?.group(1);
  }

  static String? extractSubToken(String subUrl) {
    final m = RegExp(r'/sub/([^/]+)').firstMatch(subUrl);
    return m?.group(1);
  }

  static double parseTrafficGb(String text) {
    final t = text.trim().toUpperCase();
    final numMatch = RegExp(r'([\d.]+)').firstMatch(t);
    if (numMatch == null) return 0;
    final n = double.tryParse(numMatch.group(1)!) ?? 0;
    if (t.contains('TB')) return n * 1024;
    if (t.contains('GB')) return n;
    if (t.contains('MB')) return n / 1024;
    if (t.contains('KB')) return n / 1024 / 1024;
    if (t.contains('B')) return n / 1024 / 1024 / 1024;
    return n;
  }

  static UserProfile? userFromDashboardHtml(String html, {required String email}) {
    final remaining = RegExp(r'剩余流量\s*([^<]+)').firstMatch(html)?.group(1)?.trim();
    final lastUsed = RegExp(r'过去用量\s*([^<]+)').firstMatch(html)?.group(1)?.trim();
    final todayUsed = RegExp(r'今日用量\s*([^<]+)').firstMatch(html)?.group(1)?.trim();
    final classMatch = RegExp(r'LV\.\s*(\d+)').firstMatch(html);
    final expireMatch = RegExp(r'会在\s*(\d+)\s*天后到期[（(]([^）)]+)[）)]').firstMatch(html);
    final moneyMatch = RegExp(r'余额[^¥]*¥\s*([\d.]+)').firstMatch(html);

    final remainingGb = remaining != null ? parseTrafficGb(remaining) : 0.0;
    final usedGb =
        parseTrafficGb(lastUsed ?? '0') + parseTrafficGb(todayUsed ?? '0');
    final totalGb = remainingGb + usedGb;

    final checkedInToday = html.contains('暂时还不能签到') ||
        html.contains('今日已签到') ||
        html.contains('已经签到');

    DateTime? expireAt;
    if (expireMatch != null) {
      final days = int.tryParse(expireMatch.group(1)!) ?? 0;
      if (days > 0) {
        expireAt = DateTime.now().add(Duration(days: days));
      }
    }

    return UserProfile(
      email: email,
      planName: classMatch != null ? 'LV.${classMatch.group(1)}' : '用户',
      usedTrafficGb: usedGb,
      totalTrafficGb: totalGb > 0 ? totalGb.toDouble() : remainingGb,
      expireAt: expireAt,
      checkedInToday: checkedInToday,
      balance: double.tryParse(moneyMatch?.group(1) ?? '') ?? 0,
    );
  }

  static bool looksLikeServerPage(String html) {
    return html.contains('status-indicator') ||
        html.contains('节点列表') ||
        html.contains('查看节点在线') ||
        html.contains('/user/node/') ||
        html.contains('ss://') ||
        html.contains('vmess://') ||
        html.contains('vless://') ||
        html.contains('trojan://');
  }

  static bool _isIgnoredNodeTitle(String name) {
    const ignored = {'节点列表', '节点', '加速器', 'SSPanel-UIM'};
    final trimmed = name.trim();
    return ignored.contains(trimmed) ||
        trimmed.length < 2 ||
        trimmed.contains('剩余流量') ||
        trimmed.contains('套餐到期') ||
        trimmed.contains('距离下次重置');
  }

  static NodeStatus _statusFromClass(String statusClass) {
    if (statusClass.contains('status-red')) return NodeStatus.offline;
    if (statusClass.contains('status-green')) return NodeStatus.online;
    // 面板常见橙色/黄色圆点也为可用节点
    if (statusClass.contains('status-orange') ||
        statusClass.contains('status-yellow') ||
        statusClass.contains('status-azure') ||
        statusClass.contains('status-blue')) {
      return NodeStatus.online;
    }
    return NodeStatus.maintenance;
  }

  static List<VpnNode> nodesFromServerHtml(String html) {
    if (looksLikeLoginPage(html) && !looksLikeServerPage(html)) return [];

    final doc = html_parser.parse(html);
    final nodes = <VpnNode>[];
    final seen = <String>{};

    void addNode({
      required String name,
      required String statusClass,
      int load = 0,
      String? id,
      String shareLink = '',
    }) {
      final trimmed = _cleanNodeName(name);
      if (_isIgnoredNodeTitle(trimmed) || !seen.add(trimmed)) return;

      nodes.add(
        VpnNode(
          id: id ?? 'node-${nodes.length + 1}',
          name: trimmed,
          region: _guessRegion(trimmed),
          status: _statusFromClass(statusClass),
          latencyMs: null,
          loadPercent: load.clamp(0, 100),
          shareLink: shareLink,
        ),
      );
    }

    // 优先：订阅/节点协议链接，定制主题通常会把所有节点放在链接或 data 字段里。
    for (final el in doc.querySelectorAll('a[href], button[data-clipboard-text], [data-clipboard-text]')) {
      final href = el.attributes['href'] ?? '';
      final clip = el.attributes['data-clipboard-text'] ?? '';
      final link = href.isNotEmpty ? href : clip;
      final lower = link.toLowerCase();
      final isProxyLink = lower.startsWith('ss://') ||
          lower.startsWith('ssr://') ||
          lower.startsWith('vmess://') ||
          lower.startsWith('vless://') ||
          lower.startsWith('trojan://') ||
          lower.startsWith('hysteria://') ||
          lower.startsWith('hy2://') ||
          lower.startsWith('tuic://');
      final isNodePath = lower.contains('/user/node/') || lower.contains('/user/server/');
      if (!isProxyLink && !isNodePath) continue;

      final text = el.text.trim();
      final title = el.attributes['title'] ?? el.attributes['aria-label'] ?? '';
      final name = _nodeNameFromLink(link) ?? _bestNodeText(title.isNotEmpty ? title : text);
      if (name == null) continue;
      addNode(name: name, statusClass: 'status-green', id: _nodeIdFromLink(link), shareLink: isProxyLink ? link : '');
    }

    if (nodes.isNotEmpty) return nodes;

    // 优先：带 status-indicator 的节点卡片（SSPanel-UIM 标准结构）
    for (final statusEl in doc.querySelectorAll('[class*="status-indicator"]')) {
      final cls = statusEl.attributes['class'] ?? '';
      if (!cls.contains('status-')) continue;

      final card = _findAncestorCard(statusEl);
      if (card == null) continue;

      final titleEl = card.querySelector('h2.page-title, .page-title');
      if (titleEl == null) continue;

      final name = titleEl.text.trim().split('\n').first.trim();
      var load = 0;
      for (final b in card.querySelectorAll('.badge')) {
        final text = b.text.trim();
        if (text.contains('倍')) {
          final n = double.tryParse(RegExp(r'([\d.]+)').firstMatch(text)?.group(1) ?? '');
          load = ((n ?? 0) * 20).round();
        }
      }
      addNode(name: name, statusClass: cls, load: load);
    }

    if (nodes.isNotEmpty) return nodes;

    // 回退：匹配 page-title + 邻近 status 类名
    for (final m in RegExp(
      r'status-indicator\s+status-(\w+)[\s\S]{0,1200}?page-title[^>]*>\s*([^<\n]+)',
      multiLine: true,
    ).allMatches(html)) {
      addNode(
        name: m.group(2)!,
        statusClass: 'status-${m.group(1)}',
      );
    }

    if (nodes.isNotEmpty) return nodes;

    // 回退：仅 page-title（部分定制主题）
    for (final titleEl in doc.querySelectorAll('h2.page-title, .card .page-title')) {
      final name = titleEl.text.trim().split('\n').first.trim();
      addNode(name: name, statusClass: 'status-green');
    }

    return nodes;
  }

  static String _cleanNodeName(String name) {
    return name
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^(FREE|VIP|节点|Node)\s*', caseSensitive: false), '')
        .trim();
  }

  static String? _bestNodeText(String text) {
    final lines = text
        .split(RegExp(r'[\n\r]+'))
        .map((line) => _cleanNodeName(line))
        .where((line) => line.isNotEmpty && !_isIgnoredNodeTitle(line))
        .toList();
    if (lines.isEmpty) return null;
    return lines.firstWhere(
      (line) => _guessRegion(line).isNotEmpty,
      orElse: () => lines.first,
    );
  }

  static String? _nodeNameFromLink(String link) {
    final hashIndex = link.indexOf('#');
    if (hashIndex >= 0 && hashIndex < link.length - 1) {
      return Uri.decodeComponent(link.substring(hashIndex + 1)).trim();
    }
    final name = RegExp(r'[?&](?:remarks|remark|name)=([^&]+)').firstMatch(link)?.group(1);
    if (name != null) return Uri.decodeComponent(name).trim();
    return null;
  }

  static String? _nodeIdFromLink(String link) {
    return RegExp(r'/user/(?:node|server)/(\d+)').firstMatch(link)?.group(1);
  }

  /// 定制主题：从订阅按钮链接解析商品（无 product-id 标记时）
  static List<ShopPlan> _plansFromOrderLinks(String html) {
    final plans = <ShopPlan>[];
    final seen = <String>{};
    final linkRe = RegExp(
      r'href="(/user/order/create\?product_id=(\d+))"[^>]*>[\s\S]{0,120}?(?:订阅|购买)',
      multiLine: true,
    );
    for (final m in linkRe.allMatches(html)) {
      final id = m.group(2)!;
      if (!seen.add(id)) continue;
      final price = _priceForProduct(html, id);
      final features = _featuresForProduct(html, id);
      final kind = _kindForProduct(html, id);
      plans.add(
        ShopPlan(
          id: id,
          name: _nameForProduct(html, id),
          price: price,
          trafficGb: _extractTrafficGb('', features),
          durationDays: _durationDays(features, kind),
          description: features.isNotEmpty ? features.join(' · ') : '套餐 $id',
          kind: kind,
          orderPeriod: kind == ProductKind.permanent ? 'onetime_price' : 'month_price',
          features: features,
        ),
      );
    }
    return plans;
  }

  static dom.Element? _findAncestorCard(dom.Element node) {
    var current = node.parent;
    while (current != null) {
      if (current.classes.contains('card')) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  static String _guessRegion(String name) {
    if (RegExp(r'香港|HK|港').hasMatch(name)) return 'HK';
    if (RegExp(r'日本|东京|JP').hasMatch(name)) return 'JP';
    if (RegExp(r'美国|洛杉矶|US').hasMatch(name)) return 'US';
    if (RegExp(r'新加坡|SG').hasMatch(name)) return 'SG';
    if (RegExp(r'台湾|TW').hasMatch(name)) return 'TW';
    return 'OTHER';
  }

  static ProductKind _kindForProduct(String html, String productId) {
    final anchor = html.indexOf('product-$productId');
    if (anchor < 0) return ProductKind.periodic;
    final slice = html.substring(0, anchor);
    final markers = <int, ProductKind>{
      slice.lastIndexOf('id="tabp"'): ProductKind.periodic,
      slice.lastIndexOf('id="bandwidth"'): ProductKind.permanent,
      slice.lastIndexOf('id="time"'): ProductKind.periodic,
      slice.lastIndexOf('href="#tabp"'): ProductKind.periodic,
      slice.lastIndexOf('href="#bandwidth"'): ProductKind.permanent,
      slice.lastIndexOf('href="#time"'): ProductKind.periodic,
    };
    var best = -1;
    var kind = ProductKind.periodic;
    for (final e in markers.entries) {
      if (e.key >= 0 && e.key > best) {
        best = e.key;
        kind = e.value;
      }
    }
    return kind;
  }

  static String _productBlock(String html, String productId) {
    final start = html.indexOf('product-$productId');
    if (start < 0) return '';
    final tail = html.substring(start + 1);
    RegExpMatch? next;
    for (final m in RegExp(r'id="product-(\d+)-(?:name|price)"').allMatches(tail)) {
      if (m.group(1) != productId) {
        next = m;
        break;
      }
    }
    final end = next != null ? start + 1 + next.start : (start + 2500).clamp(0, html.length);
    return html.substring(start, end);
  }

  static List<String> _featuresForProduct(String html, String productId) {
    final block = _productBlock(html, productId);
    if (block.isEmpty) return const [];
    final features = <String>[];
    for (final f in RegExp(r'text-reset d-block">([^<]+)').allMatches(block)) {
      final t = f.group(1)!.trim();
      if (t.isNotEmpty && !RegExp(r'^(等级|等级时长|可用流量|连接速度|同时)').hasMatch(t)) {
        features.add(t);
      }
    }
    if (features.isNotEmpty) return features.take(6).toList();

    for (final f in RegExp(r'>([^<]{1,40})</').allMatches(block)) {
      final t = f.group(1)!.trim();
      if (RegExp(r'Lv\.|天|GB|Mbps|G\b|¥').hasMatch(t)) features.add(t);
    }
    return features.take(6).toList();
  }

  static double _priceForProduct(String html, String productId) {
    final doc = html_parser.parse(html);
    final priceEl = doc.querySelector('#product-$productId-price');
    if (priceEl != null) {
      final n = RegExp(r'([\d.]+)').firstMatch(priceEl.text.replaceAll(',', ''));
      if (n != null) return double.tryParse(n.group(1)!) ?? 0;
    }

    final patterns = [
      RegExp('id=["\']product-$productId-price["\'][\\s\\S]{0,400}?([\\d.]+)'),
      RegExp('product-$productId[\\s\\S]{0,600}?[¥￥]\\s*([\\d.]+)'),
      RegExp('product-$productId[\\s\\S]{0,600}?fw-bold["\']?>\\s*([\\d.]+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(html);
      if (m != null) return double.tryParse(m.group(1)!) ?? 0;
    }
    return 0;
  }

  static String _nameForProduct(String html, String productId) {
    final doc = html_parser.parse(html);
    final nameEl = doc.querySelector('#product-$productId-name');
    if (nameEl != null) {
      final t = nameEl.text.trim();
      if (t.isNotEmpty) return t;
    }
    final m = RegExp(
      'id=["\']product-$productId-name["\'][^>]*>\\s*([^<]+)',
      multiLine: true,
    ).firstMatch(html);
    return m?.group(1)?.trim() ?? '套餐 $productId';
  }

  static int _durationDays(List<String> features, ProductKind kind) {
    if (kind == ProductKind.permanent) return 0;
    for (final f in features) {
      final m = RegExp(r'(\d+)\s*天').firstMatch(f);
      if (m != null) return int.tryParse(m.group(1)!) ?? 30;
    }
    return 30;
  }

  static Set<String> _collectProductIds(String html) {
    final ids = <String>{};
    for (final m in RegExp(r'product-(\d+)-(?:name|price)').allMatches(html)) {
      ids.add(m.group(1)!);
    }
    for (final m in RegExp(r'order/create\?product_id=(\d+)').allMatches(html)) {
      ids.add(m.group(1)!);
    }
    final doc = html_parser.parse(html);
    for (final el in doc.querySelectorAll('[id^="product-"]')) {
      final m = RegExp(r'product-(\d+)-').firstMatch(el.id);
      if (m != null) ids.add(m.group(1)!);
    }
    return ids;
  }

  /// 仅匹配真正的登录页，避免侧栏/页脚「登录」字样误判。
  static bool looksLikeLoginPage(String html) {
    return html.contains('auth-page') ||
        html.contains('hx-post="/auth/login"') ||
        (html.contains('type="password"') && html.contains('/auth/login'));
  }

  /// 已登录用户仪表盘特征（避免页脚含 /auth/login 链接被误判为未登录）
  static bool looksLikeUserDashboard(String html) {
    return html.contains('剩余流量') ||
        html.contains('universal-sub-link') ||
        html.contains('universalSubUrl') ||
        html.contains('今日用量') ||
        html.contains('id="checkin"') ||
        html.contains('user/profile') ||
        html.contains('page-header');
  }

  static bool looksLikeProductPage(String html) {
    return RegExp(r'product-\d+-(?:name|price)').hasMatch(html) ||
        html.contains('order/create?product_id=') ||
        html.contains('id="tabp"') ||
        html.contains('订阅套餐') ||
        html.contains('商品列表') ||
        html.contains('时间流量包') ||
        html.contains('流量包') ||
        (html.contains('¥') && html.contains('订阅'));
  }

  static bool sessionRejected(String html, {int? statusCode, String? location}) {
    if (statusCode == 302 && (location?.contains('auth/login') ?? false)) {
      return true;
    }
    if (looksLikeUserDashboard(html) ||
        looksLikeProductPage(html) ||
        looksLikeServerPage(html)) {
      return false;
    }
    return looksLikeLoginPage(html);
  }

  static List<ShopPlan> productsFromHtml(String html) {
    if (looksLikeLoginPage(html) && !looksLikeProductPage(html)) return [];

    final plans = <ShopPlan>[];
    final ids = _collectProductIds(html).toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    for (final id in ids) {
      final kind = _kindForProduct(html, id);
      final features = _featuresForProduct(html, id);
      final name = _nameForProduct(html, id);
      final price = _priceForProduct(html, id);
      if (price <= 0 && features.isEmpty && name == '套餐 $id') continue;

      plans.add(
        ShopPlan(
          id: id,
          name: name,
          price: price,
          trafficGb: _extractTrafficGb(name, features),
          durationDays: _durationDays(features, kind),
          description: features.isNotEmpty ? features.join(' · ') : name,
          kind: kind,
          orderPeriod: kind == ProductKind.permanent ? 'onetime_price' : 'month_price',
          badge: _badgeForName(name),
          features: features,
        ),
      );
    }
    if (plans.isEmpty) {
      plans.addAll(_plansFromOrderLinks(html));
    }
    return plans;
  }

  static int _extractTrafficGb(String name, List<String> features) {
    final src = '$name ${features.join(' ')}';
    final m = RegExp(r'(\d+)\s*G').firstMatch(src.toUpperCase());
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  static String? _badgeForName(String name) {
    if (name.toLowerCase().contains('max')) return 'Max';
    if (name.toLowerCase().contains('plus')) return 'Plus';
    if (name.toLowerCase().contains('pro')) return 'Pro';
    if (name.toLowerCase().contains('rich')) return 'Rich';
    if (name.toLowerCase().contains('fast')) return 'Fast';
    return null;
  }

  static List<PaymentMethod> paymentMethodsFromHtml(String html) {
    final seen = <String>{};
    final methods = <PaymentMethod>[];
    for (final m in RegExp(r'/user/payment/purchase/([A-Za-z0-9_]+)').allMatches(html)) {
      final id = m.group(1)!;
      if (!seen.add(id)) continue;
      methods.add(
        PaymentMethod(
          id: id,
          name: _paymentName(id),
          type: _paymentType(id),
        ),
      );
    }
    return methods;
  }

  static String _paymentName(String id) {
    return switch (id.toLowerCase()) {
      'alipay' => '支付宝',
      'wxpay' || 'wechat' || 'epay_wechat' => '微信',
      'usdt' || 'trc20' || 'usdt_trc20' => 'USDT-Trc20',
      'stripe' || 'card' || 'credit' => '信用卡',
      _ => id,
    };
  }

  static PaymentGatewayType _paymentType(String id) {
    final l = id.toLowerCase();
    if (l.contains('alipay')) return PaymentGatewayType.alipay;
    if (l.contains('wx') || l.contains('wechat')) return PaymentGatewayType.wechat;
    if (l.contains('usdt') || l.contains('trc')) return PaymentGatewayType.usdt;
    if (l.contains('stripe') || l.contains('card')) return PaymentGatewayType.card;
    return PaymentGatewayType.other;
  }

  static List<SupportTicket> ticketsFromHtml(String html) {
    final doc = html_parser.parse(html);
    final tickets = <SupportTicket>[];
    for (final card in doc.querySelectorAll('.card')) {
      final titleEl = card.querySelector('.card-title');
      if (titleEl == null) continue;
      final title = titleEl.text.trim();
      if (title.contains('没有任何工单')) break;
      if (title.isEmpty) continue;

      TicketStatus status = TicketStatus.open;
      final statusText = card.text;
      if (statusText.contains('已关闭') || statusText.contains('closed')) {
        status = TicketStatus.closed;
      } else if (statusText.contains('回复') || statusText.contains('replied')) {
        status = TicketStatus.replied;
      }

      tickets.add(
        SupportTicket(
          id: '${tickets.length + 1}',
          subject: title.split('\n').first.trim(),
          status: status,
          updatedAt: DateTime.now(),
          preview: statusText.length > 80 ? statusText.substring(0, 80) : statusText,
        ),
      );
    }
    return tickets;
  }

  static List<Announcement> announcementsFromHtml(String html) {
    if (looksLikeLoginPage(html) && !html.contains('站点公告')) return [];

    final doc = html_parser.parse(html);
    final list = <Announcement>[];
    final seen = <String>{};

    for (final row in doc.querySelectorAll('table tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 3) continue;
      final id = cells[0].text.trim();
      if (id.isEmpty || id == '公告ID' || !seen.add(id)) continue;
      final dateStr = cells[1].text.trim();
      final content = cells[2].text.trim();
      if (content.isEmpty) continue;
      list.add(
        Announcement(
          id: id,
          content: content,
          publishedAt: DateTime.tryParse(dateStr),
        ),
      );
    }

    if (list.isNotEmpty) return list;

    for (final card in doc.querySelectorAll('.card')) {
      final title = card.querySelector('.card-title')?.text.trim() ?? '';
      if (!title.contains('公告') && !title.contains('通知')) continue;
      final body = card.querySelector('.card-body, .card-text');
      final content = body?.text.trim() ?? '';
      if (content.isEmpty || content.length < 4) continue;
      final id = 'ann-${list.length + 1}';
      if (!seen.add(id)) continue;
      list.add(Announcement(id: id, content: content));
    }

    return list;
  }
}
