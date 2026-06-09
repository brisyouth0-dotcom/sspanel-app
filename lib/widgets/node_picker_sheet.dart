import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/node_filters.dart';
import 'node_visuals.dart';
import 'ping_badge.dart';

/// 首页点击节点条后弹出的节点选择面板（参考设计图四）。
Future<void> showNodePickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const NodePickerSheet(),
  );
}

class NodePickerSheet extends StatefulWidget {
  const NodePickerSheet({super.key});

  @override
  State<NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<NodePickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      context.read<AppState>().setNodeSearch(_searchCtrl.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      state.setNodeSearch('');
      if (state.nodes == null || state.nodes!.isEmpty) {
        state.loadNodes(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final nodes = state.filteredNodes;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: '搜索',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: '测速',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      onPressed: state.speedTesting || state.nodes == null
                          ? null
                          : () => state.speedTestNodes(),
                      icon: state.speedTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(Icons.speed, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '刷新',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      onPressed: state.loading ? null : () => state.loadNodes(),
                      icon: state.loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(Icons.refresh, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: state.nodes == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : nodes.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    state.nodeSearch.trim().isEmpty ? '暂无可用节点' : '没有匹配的节点',
                                    style: AppTheme.bodySecondary,
                                  ),
                                  if (state.error != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      state.error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                        fontSize: 12,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 16),
                            itemCount: nodes.length + 2,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              if (i == 0) {
                                return _AutoSelectRow(
                                  selected: state.isAutoSelect,
                                  activeLeaf: state.isAutoSelect
                                      ? (state.effectiveNode?.name ??
                                          state.autoResolvedLeafName)
                                      : null,
                                  onTap: () {
                                    state.selectAutoNode();
                                    Navigator.pop(context);
                                  },
                                );
                              }
                              if (i == nodes.length + 1) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    '下滑更多节点',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                );
                              }
                              final node = nodes[i - 1];
                              final pingMs = state.pingMsForNode(node.id);
                              final pingPending = state.speedTesting && pingMs == null;
                              return _NodeRow(
                                node: node,
                                selected: state.effectiveSelectedNodeId == node.id,
                                pingMs: pingMs,
                                pingPending: pingPending,
                                speedTested: state.nodePingMs != null,
                                onTap: () {
                                  state.selectNode(node.id);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AutoSelectRow extends StatelessWidget {
  const _AutoSelectRow({
    required this.selected,
    required this.onTap,
    this.activeLeaf,
  });

  final bool selected;
  final VoidCallback onTap;
  final String? activeLeaf;

  @override
  Widget build(BuildContext context) {
    final leaf = sanitizeProxyLeaf(activeLeaf?.trim());
    final hasLeaf = leaf != null && leaf.isNotEmpty;

    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '自动选择',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (selected && hasLeaf) ...[
                      const SizedBox(height: 2),
                      Text(
                        leaf!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (selected && hasLeaf)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.primary,
                )
              else
                const Icon(Icons.speed, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.selected,
    required this.pingMs,
    required this.pingPending,
    required this.speedTested,
    required this.onTap,
  });

  final VpnNode node;
  final bool selected;
  final int? pingMs;
  final bool pingPending;
  final bool speedTested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: node.status != NodeStatus.offline ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              NodeFlag(region: node.region, name: node.name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            node.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (node.name.contains('Beta') || node.loadPercent > 80) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B9D).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Beta',
                              style: TextStyle(fontSize: 10, color: Color(0xFFFF6B9D)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
              if (pingPending)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                )
              else if (speedTested)
                PingBadge(ms: pingMs)
              else
                NodeSignal(status: node.status, active: selected || node.status == NodeStatus.online),
            ],
          ),
        ),
      ),
    );
  }
}

