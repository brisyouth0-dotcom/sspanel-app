import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../payment/payment_screen.dart';

class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});

  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadRecharges();
    });
  }

  Future<void> _cancelOrder(RechargeRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('取消订单'),
        content: Text('确定取消 ¥${record.amount.toStringAsFixed(2)} 的未支付订单？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消订单'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final state = context.read<AppState>();
    final ok = await state.cancelOrder(record.id);
    if (!mounted) return;
    if (ok) {
      showAppSnackBar(context, '订单已取消');
    } else if (state.error != null) {
      showAppErrorSnackBar(context, state.error!);
    }
  }

  Future<void> _openPendingPayment(RechargeRecord record) async {
    final state = context.read<AppState>();
    final ok = await state.preparePaymentForInvoice(record.id);
    if (!mounted) return;
    if (!ok) {
      if (state.error != null) showAppErrorSnackBar(context, state.error!);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PaymentScreen(
          invoiceId: record.id,
          planName: record.method,
          price: record.amount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = context.watch<AppState>().recharges;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('充值记录')),
      body: records == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : records.isEmpty
              ? const Center(child: Text('暂无充值记录'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = records[i];
                    final pending = r.status == '待支付';
                    return Material(
                      color: pending
                          ? const Color(0xFF3B1F1F)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: pending
                                ? AppColors.danger.withValues(alpha: 0.55)
                                : AppColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '¥${r.amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: pending
                                              ? const Color(0xFFFFB4B4)
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${r.method} · ${fmt.format(r.createdAt)}',
                                        style: AppTheme.bodySecondary,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  r.status,
                                  style: TextStyle(
                                    color: pending
                                        ? AppColors.danger
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            if (pending) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _cancelOrder(r),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.textSecondary,
                                        side: BorderSide(
                                          color: AppColors.border
                                              .withValues(alpha: 0.8),
                                        ),
                                      ),
                                      child: const Text('取消订单'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _openPendingPayment(r),
                                      child: const Text('继续支付'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
