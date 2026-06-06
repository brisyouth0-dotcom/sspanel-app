import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo_avatar.dart';
import '../store/store_screen.dart';
import 'recharge_screen.dart';
import 'tickets_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    if (profile == null) return const SizedBox.shrink();

    final dateFmt = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: const Text('个人中心')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                const AppLogoAvatar(radius: 44),
                const SizedBox(height: 12),
                Text(
                  profile.email,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.hasActiveSubscription
                      ? '${profile.planName} · 到期 ${dateFmt.format(profile.expireAt!)}'
                      : profile.planName,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _StatRow(label: '账户余额', value: '¥${profile.balance.toStringAsFixed(2)}'),
          _StatRow(
            label: '剩余流量',
            value: '${profile.remainingTrafficGb.toStringAsFixed(1)} GB',
          ),
          const SizedBox(height: 16),
          _MenuButton(
            icon: Icons.shopping_bag_outlined,
            label: '购买套餐',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const MainStoreWrapper(),
              ),
            ),
          ),
          _MenuButton(
            icon: Icons.receipt_long_outlined,
            label: '充值记录',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const RechargeScreen()),
            ),
          ),
          _MenuButton(
            icon: Icons.support_agent_outlined,
            label: '工单系统',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TicketsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class MainStoreWrapper extends StatelessWidget {
  const MainStoreWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('购买套餐')),
      body: const StoreScreen(),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
