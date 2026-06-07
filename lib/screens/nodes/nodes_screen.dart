import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/ping_style.dart';

class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadNodes();
    });
  }

  void _showImportSheet(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '一键导入订阅',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '将当前订阅链接导入到对应客户端',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              _ImportTile(
                title: 'Quantumult X',
                subtitle: 'iOS 常用',
                onTap: () => _openImport(ctx, state, ImportClient.quantumultX),
              ),
              _ImportTile(
                title: 'Clash',
                subtitle: 'Meta / Verge 等',
                onTap: () => _openImport(ctx, state, ImportClient.clash),
              ),
              _ImportTile(
                title: 'sing-box',
                subtitle: 'SFI / SFA / SFM',
                onTap: () => _openImport(ctx, state, ImportClient.singBox),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  final url = state.config?.subscribeUrl ?? '';
                  Clipboard.setData(ClipboardData(text: url));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('订阅链接已复制')),
                  );
                },
                child: const Text('复制订阅链接'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openImport(
    BuildContext context,
    AppState state,
    ImportClient client,
  ) async {
    final url = state.importUrl(client);
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await Clipboard.setData(ClipboardData(text: state.config?.subscribeUrl ?? ''));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制订阅链接，请在客户端手动导入')),
        );
      }
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final nodes = state.nodes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('节点列表'),
        actions: [
          TextButton.icon(
            onPressed: () => _showImportSheet(context, state),
            icon: const Icon(Icons.download_outlined, size: 20),
            label: const Text('导入'),
          ),
        ],
      ),
      body: nodes == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: state.loadNodes,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: nodes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final node = nodes[i];
                  final selected = state.selectedNodeId == node.id;
                  return _NodeCard(
                    node: node,
                    selected: selected,
                    onSelect: () {
                      state.selectNode(node.id);
                      Navigator.pop(context);
                    },
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: node.shareLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('节点链接已复制')),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onCopy,
  });

  final VpnNode node;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onCopy;

  Color _statusColor() {
    switch (node.status) {
      case NodeStatus.online:
        return Colors.green;
      case NodeStatus.offline:
        return Colors.red;
      case NodeStatus.maintenance:
        return Colors.orange;
    }
  }

  String _statusLabel() {
    switch (node.status) {
      case NodeStatus.online:
        return '在线';
      case NodeStatus.offline:
        return '离线';
      case NodeStatus.maintenance:
        return '维护中';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: node.status != NodeStatus.offline ? onSelect : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${node.region} · 负载 ${node.loadPercent}% · $_statusLabel()',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (node.latencyMs != null)
                Text(
                  '${node.latencyMs} ms',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PingStyle.colorFor(node.latencyMs),
                  ),
                )
              else
                const Text('--', style: TextStyle(color: AppColors.textSecondary)),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportTile extends StatelessWidget {
  const _ImportTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new),
      onTap: onTap,
    );
  }
}
