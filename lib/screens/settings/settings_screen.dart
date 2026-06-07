import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_disguise_bridge.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo_avatar.dart';
import '../../widgets/settings_tile.dart';
import 'about_screen.dart';
import 'app_disguise_screen.dart';
import 'change_password_screen.dart';
import 'support_hub_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadTickets(quiet: true);
    });
  }

  String _trafficLabel(double gb) {
    if (gb >= 1024) {
      final tb = gb / 1024;
      return '${tb.toStringAsFixed(tb >= 10 ? 0 : 1)} TB';
    }
    return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    final s = state.strings;
    final unreadTickets = state.unreadTicketCount;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Text(s.settings, style: AppTheme.titleLarge),
          const SizedBox(height: 16),
          if (profile != null)
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const AppLogoAvatar(radius: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.email,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.22),
                                const Color(0xFF34D399).withValues(alpha: 0.14),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.workspace_premium_outlined,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  profile.planName,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SettingsSection(
            title: s.subscription,
            children: [
              SettingsTile(
                icon: Icons.calendar_today_outlined,
                iconColor: AppColors.textPrimary,
                title: s.expiry,
                trailing: _ValueChip(
                  label: profile != null && profile.remainingTrafficGb > 500
                      ? '∞'
                      : profile != null && profile.hasActiveSubscription
                      ? profile.expireAt!.toString().split(' ').first
                      : s.noExpiry,
                  color: const Color(0xFF60A5FA),
                ),
                showChevron: false,
              ),
              SettingsTile(
                icon: Icons.data_usage_outlined,
                iconColor: AppColors.textPrimary,
                title: s.remainingTraffic,
                subtitle: profile == null
                    ? null
                    : '${s.usedTraffic} ${_trafficLabel(profile.usedTrafficGb)} / ${_trafficLabel(profile.totalTrafficGb)}',
                trailing: _ValueChip(
                  label: profile == null
                      ? '-'
                      : _trafficLabel(profile.remainingTrafficGb),
                  color: const Color(0xFF34D399),
                ),
                showChevron: false,
              ),
            ],
          ),
          if (!kIsWeb &&
              !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ...[
            const SizedBox(height: 16),
            SettingsSection(
              title: s.funcSettings,
              children: [
                SettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: s.appDisguise,
                  subtitle: state.appDisguiseOption.subtitle(s),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AppDisguiseScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SettingsSection(
            title: s.others,
            children: [
              SettingsTile(
                icon: Icons.lock_outline,
                title: s.changePassword,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
              ),
              SettingsTile(
                icon: Icons.support_agent_outlined,
                title: s.customerService,
                trailing: unreadTickets > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unreadTickets',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SupportHubScreen(),
                  ),
                ),
              ),
              SettingsTile(
                icon: Icons.info_outline,
                title: s.about,
                subtitle: s.aboutSub('v1.0.0'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: state.loading
                  ? null
                  : () => context.read<AppState>().runWithLoading(
                      '正在退出…',
                      () async {
                        context.read<AppState>().logout();
                      },
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerBg,
                foregroundColor: AppColors.danger,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.logout),
              label: Text(s.logout),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}
