import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.invoiceId,
    required this.planName,
    required this.price,
    this.periods = const [],
    this.initialPeriodId,
  });

  final String invoiceId;
  final String planName;
  final double price;
  final List<PlanPeriod> periods;
  final String? initialPeriodId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _selectedGateway;
  late String _selectedPeriodId;
  final _couponCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPeriodId = widget.initialPeriodId ??
        (widget.periods.isNotEmpty ? widget.periods.first.id : '');
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  PlanPeriod? get _currentPeriod {
    for (final p in widget.periods) {
      if (p.id == _selectedPeriodId) return p;
    }
    return widget.periods.isNotEmpty ? widget.periods.first : null;
  }

  double get _displayPrice => _currentPeriod?.price ?? widget.price;

  String get _displayPlanName {
    final period = _currentPeriod;
    if (period == null) return widget.planName;
    return '${widget.planName} · ${period.label}';
  }

  Future<void> _pay() async {
    final gateway = _selectedGateway;
    if (gateway == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择支付方式')),
      );
      return;
    }
    final url = context.read<AppState>().paymentUrl(gateway, widget.invoiceId);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = context.watch<AppState>().paymentMethods ?? [];

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
          if (widget.periods.length > 1) ...[
            Text('付款周期', style: AppTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.periods.map((period) {
                final selected = period.id == _selectedPeriodId;
                return ChoiceChip(
                  label: Text('${period.label} ¥${period.price.toStringAsFixed(2)}'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedPeriodId = period.id),
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtrl,
                  decoration: const InputDecoration(hintText: '优惠码'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {},
                child: const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('支付方式', style: AppTheme.titleMedium),
          const SizedBox(height: 12),
          if (methods.isEmpty)
            AppCard(
              child: Text('未获取到支付方式，请先在面板配置支付网关', style: AppTheme.bodySecondary),
            )
          else
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: methods.map((m) {
                final selected = _selectedGateway == m.id;
                return AppCard(
                  borderColor: selected ? AppColors.primary : AppColors.border,
                  onTap: () => setState(() => _selectedGateway = m.id),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(_iconFor(m.type), color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.name)),
                    ],
                  ),
                );
              }).toList(),
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
                      _displayPlanName,
                      style: AppTheme.bodySecondary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '¥ ${_displayPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.cardElevated,
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size(double.infinity, 52),
                  shape: const StadiumBorder(),
                ),
                child: const Text('立即支付  >'),
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
