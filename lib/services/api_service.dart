import '../models/models.dart';
import 'xboard_api.dart';

/// 面向 UI 的 API 门面，对接 Xboard 面板 https://user.panlink.site
class ApiService {
  ApiService({XboardApi? api}) : _api = api ?? XboardApi();

  final XboardApi _api;

  Future<void> init() => _api.init();

  Future<bool> tryRestoreSession() => _api.tryRestoreSession();

  bool get isLoggedIn => _api.isLoggedIn;

  UserProfile get profile => _api.profile;

  bool get isConnected => _api.isConnected;

  String? get selectedNodeId => _api.selectedNodeId;

  SubscriptionConfig get config => _api.config;

  Future<bool> login(String email, String password, {String? code}) =>
      _api.login(email, password, code: code);

  Future<bool> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
  }) =>
      _api.register(email, password, inviteCode: inviteCode, emailCode: emailCode);

  Future<void> sendEmailCode(String email, {String context = 'register'}) =>
      _api.sendEmailCode(email, context: context);

  void logout() => _api.logout();

  Future<void> refreshUser() => _api.refreshUser();

  Future<void> toggleConnection() => _api.toggleConnection();

  void selectNode(String nodeId) => _api.selectNode(nodeId);

  Future<List<VpnNode>> fetchNodes() => _api.fetchNodes();

  Future<void> updateSubscription({
    required String subscribeUrl,
    required String token,
  }) =>
      _api.updateSubscription(subscribeUrl: subscribeUrl, token: token);

  Future<List<ShopPlan>> fetchPlans() => _api.fetchPlans();

  Future<OrderResult> createProductOrder(
    String productId, {
    String period = 'month_price',
    String coupon = '',
  }) =>
      _api.createProductOrder(productId, period: period, coupon: coupon);

  Future<List<PaymentMethod>> fetchPaymentMethods(String invoiceId) =>
      _api.fetchPaymentMethods(invoiceId);

  String paymentUrl(String gateway, {String? invoiceId}) =>
      _api.paymentUrl(gateway, invoiceId: invoiceId);

  Future<bool> purchasePlan(String planId) => _api.purchasePlan(planId);

  Future<List<RechargeRecord>> fetchRecharges() => _api.fetchRecharges();

  Future<bool> cancelOrder(String tradeNo) => _api.cancelOrder(tradeNo);

  Future<List<SupportTicket>> fetchTickets() => _api.fetchTickets();

  Future<List<Announcement>> fetchAnnouncements() => _api.fetchAnnouncements();

  Future<String> fetchSubscribeText() => _api.fetchSubscribeText();

  String? get clashSubscribeImportUrl => _api.clashSubscribeImportUrl;

  Future<bool> createTicket(String subject, String content) =>
      _api.createTicket(subject, content);

  Future<SupportTicket> fetchTicketDetail(String id) =>
      _api.fetchTicketDetail(id);

  Future<bool> replyTicket(String id, String message) =>
      _api.replyTicket(id, message);

  Future<bool> closeTicket(String id) => _api.closeTicket(id);

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) =>
      _api.changePassword(oldPassword: oldPassword, newPassword: newPassword);

  Future<String?> fetchTelegramUrl() => _api.fetchTelegramUrl();

  String importUrl(ImportClient client) => _api.importUrl(client);

  String get clashSubscribeUrl => _api.clashSubscribeUrl;
}
