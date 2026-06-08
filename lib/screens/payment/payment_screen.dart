import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/panel_exceptions.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/open_external_url.dart';
import '../../widgets/app_snackbar.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.invoiceId,
    required this.planName,
    required this.price,
    this.periods = const [],
    this.initialPeriodId,
    this.periodLabel,
  });

  final String invoiceId;
  final String planName;
  final double price;
  final List<PlanPeriod> periods;
  final String? initialPeriodId;
  final String? periodLabel;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const double _couponRowHeight = 44;
  static const double _paymentMethodTileHeight = 44;

  String? _selectedGateway;
  late String _selectedPeriodId;
  final _couponCtrl = TextEditingController();

  bool _loadingMethods = false;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _selectedPeriodId =
        widget.initialPeriodId ??
        (widget.periods.isNotEmpty ? widget.periods.first.id : '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMethods());
  }

  Future<void> _loadMethods() async {
    if (_loadingMethods) return;
    setState(() => _loadingMethods = true);
    final state = context.read<AppState>();
    final ok = await state.preparePaymentForInvoice(
      widget.invoiceId,
      quiet: true,
    );
    if (!mounted) return;
    final methods = state.paymentMethods;
    setState(() {
      _loadingMethods = false;
      if (_selectedGateway == null && methods != null && methods.isNotEmpty) {
        _selectedGateway = methods.first.id;
      }
    });
    if (!ok && state.error != null) {
      showAppErrorSnackBar(context, state.error!);
    }
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  List<PlanPeriod> _resolvePeriods(AppState state) {
    if (widget.periods.isNotEmpty) return widget.periods;
    final planName = widget.planName.toLowerCase();
    for (final plan in state.plans ?? const <ShopPlan>[]) {
      if (planName.contains(plan.name.toLowerCase()) ||
          plan.name.toLowerCase().contains(planName)) {
        return plan.availablePeriods;
      }
    }
    if (widget.periodLabel != null && widget.periodLabel!.isNotEmpty) {
      return [
        PlanPeriod(
          id: widget.initialPeriodId ?? 'current',
          label: widget.periodLabel!,
          price: widget.price,
        ),
      ];
    }
    return const [];
  }

  PlanPeriod? _currentPeriod(List<PlanPeriod> periods) {
    for (final p in periods) {
      if (p.id == _selectedPeriodId) return p;
    }
    return periods.isNotEmpty ? periods.first : null;
  }

  double _displayPrice(List<PlanPeriod> periods) =>
      _currentPeriod(periods)?.price ?? widget.price;

  String? _resolvedPeriodLabel(List<PlanPeriod> periods) =>
      _currentPeriod(periods)?.label ?? widget.periodLabel;

  String _displayPlanName(List<PlanPeriod> periods) {
    final periodLabel = _resolvedPeriodLabel(periods);
    if (periodLabel == null) return widget.planName;
    return '${widget.planName} · $periodLabel';
  }

  Future<void> _pay() async {
    if (_paying) return;
    final gateway = _selectedGateway;
    if (gateway == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择支付方式')));
      return;
    }
    setState(() => _paying = true);
    try {
      final result = await context.read<AppState>().checkoutOrder(
        widget.invoiceId,
        gateway,
      );
      if (!mounted) return;
      final target = result.data.trim();
      if (target.isEmpty) {
        showAppErrorSnackBar(context, '支付网关未返回付款地址');
        return;
      }
      if (result.isPaymentUrl) {
        final opened = await openExternalUrl(target);
        if (!mounted) return;
        if (!opened) {
          showAppErrorSnackBar(context, '无法打开支付页面，请复制链接到浏览器：$target');
        }
      } else {
        showAppSnackBar(context, '请使用支付宝/微信扫码完成支付');
      }
    } on PanelApiException catch (e) {
      if (mounted) showAppErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showAppErrorSnackBar(context, '发起支付失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final methods = state.paymentMethods ?? [];
    final periods = _resolvePeriods(state);
    final canSwitchPeriod = periods.length > 1;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('支付方式'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (periods.isNotEmpty) ...[
            Text('付款周期', style: AppTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < periods.length; index++)
                  _PeriodTile(
                    period: periods[index],
                    selected:
                        periods[index].id == _selectedPeriodId ||
                        (!canSwitchPeriod && index == 0),
                    onTap: canSwitchPeriod
                        ? () => setState(
                            () => _selectedPeriodId = periods[index].id,
                          )
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _CouponInput(
                  height: _couponRowHeight,
                  controller: _couponCtrl,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: _couponRowHeight,
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                    minimumSize: const Size(72, _couponRowHeight),
                    maximumSize: const Size(double.infinity, _couponRowHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '应用',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('支付方式', style: AppTheme.titleMedium),
          const SizedBox(height: 12),
          if (_loadingMethods)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (methods.isEmpty)
            const SizedBox.shrink()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: methods.map((m) {
                    final selected = _selectedGateway == m.id;
                    return _PaymentMethodTile(
                      method: m,
                      selected: selected,
                      icon: _iconFor(m.type),
                      maxWidth: constraints.maxWidth,
                      onTap: () => setState(() => _selectedGateway = m.id),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _displayPlanName(periods),
                      style: AppTheme.bodySecondary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '¥ ${_displayPrice(periods).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_loadingMethods || _paying) ? null : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: const StadiumBorder(),
                ),
                child: _paying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '立即支付',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PaymentGatewayType type) {
    return switch (type) {
      PaymentGatewayType.alipay => Icons.account_balance_wallet_outlined,
      PaymentGatewayType.wechat => Icons.chat_outlined,
      PaymentGatewayType.usdt => Icons.currency_bitcoin,
      PaymentGatewayType.card => Icons.credit_card,
      PaymentGatewayType.other => Icons.payment,
    };
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.icon,
    required this.maxWidth,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final IconData icon;
  final double maxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(
        height: _PaymentScreenState._paymentMethodTileHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        method.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 固定 44px 高度，避免主题 InputDecoration 把输入框撑矮
class _CouponInput extends StatefulWidget {
  const _CouponInput({required this.height, required this.controller});

  final double height;
  final TextEditingController controller;

  @override
  State<_CouponInput> createState() => _CouponInputState();
}

class _CouponInputState extends State<_CouponInput> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? AppColors.primary : AppColors.border,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: 1,
        style: const TextStyle(
          fontSize: 14,
          height: 1.0,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          hintText: '优惠码',
          hintStyle: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.0,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        ),
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.period, required this.selected, this.onTap});

  final PlanPeriod period;
  final bool selected;
  final VoidCallback? onTap;

  static const _sidePad = 10.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.22),
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _sidePad,
              vertical: 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                Text(
                  '${period.label} ¥${period.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: selected ? AppColors.primary : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
