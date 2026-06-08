import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../payment/payment_screen.dart';
import '../profile/recharge_screen.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String? _selectedId;
  final Map<String, String> _selectedPeriodByPlan = {};

  static const _kinds = [ProductKind.periodic, ProductKind.permanent];
  static const _tabLabels = ['周期套餐', '永久套餐'];
  static const _tabHints = ['每月重置流量', '一次性买断'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.loadPlans();
      state.loadRecharges(quiet: true);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<ShopPlan> _plansForTab(AppState state) {
    return state.plansByKind(_kinds[_tab.index]);
  }

  ShopPlan? _selectedPlanFor(List<ShopPlan> list) {
    if (list.isEmpty) return null;
    for (final plan in list) {
      if (plan.id == _selectedId) return plan;
    }
    return list.first;
  }

  PlanPeriod _selectedPeriodFor(ShopPlan plan) {
    final periods = plan.availablePeriods;
    final selectedId = _selectedPeriodByPlan[plan.id];
    for (final period in periods) {
      if (period.id == selectedId) return period;
    }
    return periods.first;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plans = state.plans;
    final list = _plansForTab(state);
    final selectedPlan = _selectedPlanFor(list);
    final selectedPeriod = selectedPlan == null
        ? null
        : _selectedPeriodFor(selectedPlan);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 顶部 Tab + 充值记录入口 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TabBar(
                      controller: _tab,
                      onTap: (_) => setState(() => _selectedId = null),
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textPrimary,
                      labelPadding: EdgeInsets.zero,
                      indicatorPadding: const EdgeInsets.all(3),
                      splashFactory: NoSplash.splashFactory,
                      tabs: List.generate(2, (i) {
                        final selected = _tab.index == i;
                        return Tab(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _tabLabels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                _tabHints[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.92)
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 充值记录
                _HeaderAction(
                  icon: Icons.receipt_long_outlined,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const RechargeScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── 套餐列表 ──
          Expanded(
            child: plans == null
                ? _LoadingState()
                : list.isEmpty
                ? _EmptyState(
                    tabLabel: _tabLabels[_tab.index],
                    error: state.error,
                    onReload: state.loading
                        ? null
                        : () => state.loadPlans(force: true),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: state.loading
                        ? () async {}
                        : () => state.loadPlans(force: true),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final plan = list[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PlanCard(
                            plan: plan,
                            selected: selectedPlan?.id == plan.id,
                            selectedPeriod: selectedPlan?.id == plan.id
                                ? selectedPeriod
                                : null,
                            onSelect: () =>
                                setState(() => _selectedId = plan.id),
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // ── 底部购买按钮 ──
          if (selectedPlan != null && selectedPeriod != null)
            _BottomPurchaseBar(
              plan: selectedPlan,
              selectedPeriod: selectedPeriod,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 顶栏小按钮
// ═══════════════════════════════════════════════════════════════

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 22),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 加载中
// ═══════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 空状态
// ═══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tabLabel, this.error, this.onReload});
  final String tabLabel;
  final String? error;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          if (error != null)
            Text(
              error!,
              style: const TextStyle(
                color: Color(0xFFFFB4B4),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            )
          else
            Text('暂无$tabLabel', style: AppTheme.bodySecondary),
          const SizedBox(height: 12),
          TextButton(onPressed: onReload, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 底部购买栏
// ═══════════════════════════════════════════════════════════════

class _BottomPurchaseBar extends StatefulWidget {
  const _BottomPurchaseBar({
    required this.plan,
    required this.selectedPeriod,
  });

  final ShopPlan plan;
  final PlanPeriod selectedPeriod;

  @override
  State<_BottomPurchaseBar> createState() => _BottomPurchaseBarState();
}

class _BottomPurchaseBarState extends State<_BottomPurchaseBar> {

  void _showPendingSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('您有未支付的订单，请先完成支付'),
        action: SnackBarAction(
          label: '去支付',
          textColor: Colors.white,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const RechargeScreen()),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordering = context.select<AppState, bool>((s) => s.ordering);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: ordering
              ? null
              : () async {
                  final state = context.read<AppState>();
                  final order = await state.createOrder(
                    widget.plan.id,
                    period: widget.selectedPeriod.id,
                    quiet: true,
                  );
                  if (!context.mounted) return;
                  if (order == null) {
                    if (state.pendingRecharges.isNotEmpty) {
                      _showPendingSnackBar(context);
                    } else if (state.error != null) {
                      showAppErrorSnackBar(context, state.error!);
                    }
                    return;
                  }
                  if (!context.mounted) return;
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentScreen(
                        invoiceId: order.invoiceId,
                        planName: widget.plan.name,
                        price: widget.selectedPeriod.price,
                        periods: widget.plan.availablePeriods,
                        initialPeriodId: widget.selectedPeriod.id,
                      ),
                    ),
                  );
                },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 46),
            shape: const StadiumBorder(),
          ),
          child: ordering
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '立即支付',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '¥ ${widget.selectedPeriod.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 套餐卡片
// ═══════════════════════════════════════════════════════════════

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    this.selectedPeriod,
    required this.onSelect,
  });

  final ShopPlan plan;
  final bool selected;
  final PlanPeriod? selectedPeriod;
  final VoidCallback onSelect;

  PlanPeriod get _displayPeriod =>
      selectedPeriod ?? plan.availablePeriods.first;

  String get _durationLabel {
    if (plan.isPermanent) return '永久有效';
    if (plan.durationDays > 0) return '${plan.durationDays} 天';
    return '按月重置';
  }

  String get _trafficLabel {
    if (plan.trafficGb <= 0) return '';
    if (plan.trafficGb >= 1024) {
      return '${(plan.trafficGb / 1024).toStringAsFixed(plan.trafficGb % 1024 == 0 ? 0 : 1)} TB';
    }
    return '${plan.trafficGb} GB';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: selected ? AppColors.primary : AppColors.border,
      onTap: onSelect,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 头部：名称 + 推荐标签 + 价格 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (plan.recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '推荐',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _MetaChip(
                          icon: Icons.schedule_outlined,
                          label: _durationLabel,
                        ),
                        if (_trafficLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _MetaChip(
                            icon: Icons.data_usage_outlined,
                            label: _trafficLabel,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '¥ ${_displayPeriod.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (plan.availablePeriods.length > 1)
                    Text(
                      '多种周期可选',
                      style: AppTheme.bodySecondary.copyWith(fontSize: 11),
                    ),
                ],
              ),
            ],
          ),

          // ── 特性标签 ──
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: plan.features
                  .take(6)
                  .map((f) => _SpecChip(f, active: selected))
                  .toList(),
            ),
          ] else if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(plan.description, style: AppTheme.bodySecondary),
          ],

          // ── 选中勾 ──
          if (selected) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  '已选择',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 元信息小标签（时长 / 流量）
// ═══════════════════════════════════════════════════════════════

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final valueMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:GB|TB|天))').firstMatch(label);
    final valueText = valueMatch?.group(1);
    final prefix = valueText == null
        ? label
        : label.substring(0, label.indexOf(valueText)).trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: valueText == null ? AppColors.textSecondary : AppColors.primary,
          ),
          const SizedBox(width: 4),
          if (valueText == null)
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            )
          else ...[
            if (prefix.isNotEmpty)
              Text(
                prefix,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            if (prefix.isNotEmpty) const SizedBox(width: 4),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 特性标签
// ═══════════════════════════════════════════════════════════════

class _SpecChip extends StatelessWidget {
  const _SpecChip(this.text, {this.active = false});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.cardElevated,
        borderRadius: BorderRadius.circular(8),
        border: active
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.25))
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
