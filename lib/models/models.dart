enum NodeStatus { online, offline, maintenance }

enum ImportClient { quantumultX, clash, singBox }

enum TicketStatus { open, replied, closed }

/// periodic=周期套餐（按月重置） permanent=永久套餐（一次性流量）
enum ProductKind { periodic, permanent }

enum PaymentGatewayType { alipay, wechat, usdt, card, other }

class UserProfile {
  const UserProfile({
    required this.email,
    required this.planName,
    required this.usedTrafficGb,
    required this.totalTrafficGb,
    this.expireAt,
    required this.checkedInToday,
    required this.balance,
  });

  final String email;
  final String planName;
  final double usedTrafficGb;
  final double totalTrafficGb;
  final DateTime? expireAt;
  final bool checkedInToday;
  final double balance;

  static const _inactivePlanNames = {'未订阅', 'Free', '用户', '无套餐'};

  bool get hasActiveSubscription {
    final name = planName.trim();
    if (_inactivePlanNames.contains(name) || name == 'LV.0') return false;
    return expireAt != null;
  }

  double get remainingTrafficGb =>
      (totalTrafficGb - usedTrafficGb).clamp(0, totalTrafficGb);

  double get usagePercent =>
      totalTrafficGb <= 0 ? 0 : (usedTrafficGb / totalTrafficGb).clamp(0, 1);
}

class VpnNode {
  const VpnNode({
    required this.id,
    required this.name,
    required this.region,
    required this.status,
    required this.latencyMs,
    required this.loadPercent,
    required this.shareLink,
  });

  final String id;
  final String name;
  final String region;
  final NodeStatus status;
  final int? latencyMs;
  final int loadPercent;
  final String shareLink;
}

class SubscriptionConfig {
  const SubscriptionConfig({
    required this.subscribeUrl,
    required this.token,
    required this.lastUpdated,
  });

  final String subscribeUrl;
  final String token;
  final DateTime lastUpdated;
}

class ShopPlan {
  const ShopPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.trafficGb,
    required this.durationDays,
    required this.description,
    this.kind = ProductKind.periodic,
    this.orderPeriod = 'month_price',
    this.badge,
    this.features = const [],
    this.recommended = false,
    this.periods = const [],
  });

  final String id;
  final String name;
  final double price;
  final int trafficGb;
  final int durationDays;
  final String description;
  final ProductKind kind;

  /// Xboard 下单 period：month_price / onetime_price 等
  final String orderPeriod;
  final String? badge;
  final List<String> features;
  final bool recommended;
  final List<PlanPeriod> periods;

  bool get isPermanent => kind == ProductKind.permanent;

  List<PlanPeriod> get availablePeriods {
    if (periods.isNotEmpty) return periods;
    return [
      PlanPeriod(
        id: orderPeriod,
        label: isPermanent ? '永久' : '月付',
        price: price,
      ),
    ];
  }
}

class PlanPeriod {
  const PlanPeriod({
    required this.id,
    required this.label,
    required this.price,
    this.badge,
  });

  final String id;
  final String label;
  final double price;
  final String? badge;
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final PaymentGatewayType type;
}

class OrderResult {
  const OrderResult({required this.invoiceId, required this.redirectPath});

  final String invoiceId;
  final String redirectPath;
}

/// Xboard checkout 返回：type 0=二维码内容，1=支付链接
class CheckoutResult {
  const CheckoutResult({required this.type, required this.data});

  final int type;
  final String data;

  bool get isPaymentUrl {
    final s = data.trim().toLowerCase();
    return type == 1 ||
        s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('alipays://') ||
        s.startsWith('alipay://') ||
        s.startsWith('weixin://') ||
        s.startsWith('wxp://');
  }
}

class RechargeRecord {
  const RechargeRecord({
    required this.id,
    required this.amount,
    required this.method,
    required this.createdAt,
    required this.status,
    this.planName,
    this.periodLabel,
  });

  final String id;
  final double amount;
  final String method;
  final DateTime createdAt;
  final String status;
  final String? planName;
  final String? periodLabel;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.updatedAt,
    required this.preview,
    this.messages = const [],
    this.closed = false,
  });

  final String id;
  final String subject;
  final TicketStatus status;
  final DateTime updatedAt;
  final String preview;
  final List<TicketMessage> messages;
  final bool closed;
}

class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.message,
    required this.isMe,
    required this.createdAt,
  });

  final String id;
  final String message;
  final bool isMe;
  final DateTime createdAt;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.content,
    this.title,
    this.publishedAt,
  });

  final String id;
  final String content;
  final String? title;
  final DateTime? publishedAt;

  String get listTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final first = content.split('\n').first.trim();
    if (first.isNotEmpty) return first;
    return '公告';
  }

  String get bodyText {
    final t = title?.trim();
    if (t == null || t.isEmpty || !content.startsWith(t)) return content;
    return content.substring(t.length).trim();
  }

  String get summary {
    final source = bodyText.isNotEmpty ? bodyText : content;
    final t = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 60) return t;
    return '${t.substring(0, 60)}…';
  }

  String get preview {
    final t = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 80) return t;
    return '${t.substring(0, 80)}…';
  }
}
