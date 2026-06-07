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
  static const _pageSize = 10;

  final _scrollCtrl = ScrollController();
  int _visibleCount = _pageSize;
  String? _cancellingId;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadRecharges(refresh: true, quiet: true);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (_scrollCtrl.position.pixels >= max - 120) {
      final total = context.read<AppState>().visibleRecharges.length;
      if (_visibleCount < total) {
        setState(() => _visibleCount += _pageSize);
      }
    }
  }

  Future<void> _cancelOrder(RechargeRecord record) async {
    if (_cancellingId != null) return;
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

    setState(() => _cancellingId = record.id);
    final state = context.read<AppState>();
    try {
      final ok = await state.cancelOrder(record.id, quiet: true);
      if (!mounted) return;
      if (ok) {
        showAppSnackBar(context, '订单已取消');
      } else if (state.error != null) {
        showAppErrorSnackBar(context, state.error!);
      }
    } finally {
      if (mounted) setState(() => _cancellingId = null);
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
    final allRecords = context.watch<AppState>().recharges;
    final records = context.watch<AppState>().visibleRecharges;
    final pending = context.watch<AppState>().firstPendingRecharge;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final visible = records.take(_visibleCount).toList();
    final hasMore = records.length > _visibleCount;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('充值记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AppState>().loadRecharges(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: allRecords == null
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : records.isEmpty
                ? const Center(child: Text('暂无充值记录'))
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      setState(() => _visibleCount = _pageSize);
                      await context.read<AppState>().loadRecharges(refresh: true);
                    },
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: visible.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (hasMore && i == visible.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          );
                        }
                        final r = visible[i];
                        final isPending = r.status == '待支付';
                        final cancelling = _cancellingId == r.id;
                        return Material(
                          color: isPending
                              ? const Color(0xFF3B1F1F)
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isPending
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
                                              color: isPending
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
                                        color: isPending
                                            ? AppColors.danger
                                            : AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isPending) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: cancelling
                                              ? null
                                              : () => _cancelOrder(r),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFFE2E8F0),
                                            side: BorderSide(
                                              color: AppColors.border
                                                  .withValues(alpha: 0.9),
                                            ),
                                          ),
                                          child: cancelling
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Color(0xFFE2E8F0),
                                                  ),
                                                )
                                              : const Text('取消订单'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: cancelling
                                              ? null
                                              : () => _openPendingPayment(r),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text(
                                            '继续支付',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
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
                  ),
          ),
          if (pending != null)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B1F1F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '您有未支付的订单，请先完成支付',
                        style: TextStyle(
                          color: AppColors.danger.withValues(alpha: 0.95),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openPendingPayment(pending),
                      child: const Text(
                        '去支付',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
