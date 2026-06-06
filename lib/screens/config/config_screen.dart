import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pill_button.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppState>().config;
    _urlCtrl = TextEditingController(text: config?.subscribeUrl ?? '');
    _tokenCtrl = TextEditingController(text: config?.token ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    await state.updateSubscription(
      _urlCtrl.text.trim(),
      _tokenCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('订阅信息已更新')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.config;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('配置管理')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '在线修改订阅',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (config != null) ...[
            const SizedBox(height: 12),
            Text(
              '上次更新：${fmt.format(config.lastUpdated)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('订阅链接', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText:
                  'https://panel.example.com/api/v1/client/subscribe?token=...',
            ),
          ),
          const SizedBox(height: 16),
          const Text('订阅 Token', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(hintText: 'your_token'),
          ),
          const SizedBox(height: 28),
          PillButton(
            label: '保存并刷新',
            loading: state.loading,
            onPressed: state.loading ? null : _save,
          ),
        ],
      ),
    );
  }
}
