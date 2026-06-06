import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../settings/settings_screen.dart';
import '../store/store_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _pages = [HomeScreen(), StoreScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    final index = context.watch<AppState>().shellTabIndex;
    final busy = context.watch<AppState>().loading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.card.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                active: index == 0,
                enabled: !busy,
                onTap: () => context.read<AppState>().goToShellTab(0),
              ),
              _NavItem(
                icon: Icons.shopping_cart_outlined,
                active: index == 1,
                enabled: !busy,
                onTap: () => context.read<AppState>().goToShellTab(1),
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                active: index == 2,
                enabled: !busy,
                onTap: () => context.read<AppState>().goToShellTab(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 28,
        color: active ? AppColors.primary : AppColors.textMuted,
      ),
    );
  }
}
