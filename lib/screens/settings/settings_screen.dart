import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_disguise_bridge.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_logo_avatar.dart';
import '../../widgets/settings_tile.dart';
import 'app_disguise_screen.dart';
import 'change_password_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _openTelegram(AppState state) async {
    final url = await state.telegramSupportUrl();
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showAppErrorSnackBar(context, '无法打开 Telegram');
    }
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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Text(s.settings, style: AppTheme.titleLarge),
          const SizedBox(height: 16),
          if (profile != null)
            AppCard(
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(profile.planName, style: AppTheme.bodySecondary),
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
                icon: Icons.credit_card_outlined,
                title: s.planCurrent,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    profile?.planName ?? 'Free',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                showChevron: false,
              ),
              SettingsTile(
                icon: Icons.calendar_today_outlined,
                title: s.expiry,
                trailing: Text(
                  profile != null && profile.remainingTrafficGb > 500
                      ? '∞'
                      : profile != null && profile.hasActiveSubscription
                      ? profile.expireAt!.toString().split(' ').first
                      : s.noExpiry,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                showChevron: false,
              ),
              SettingsTile(
                icon: Icons.data_usage_outlined,
                title: s.remainingTraffic,
                subtitle: profile == null
                    ? null
                    : '${s.usedTraffic} ${_trafficLabel(profile.usedTrafficGb)} / ${_trafficLabel(profile.totalTrafficGb)}',
                trailing: Text(
                  profile == null
                      ? '-'
                      : _trafficLabel(profile.remainingTrafficGb),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                showChevron: false,
              ),
            ],
          ),
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
          const SizedBox(height: 16),
          SettingsSection(
            title: s.others,
            children: [
              SettingsTile(
                icon: Icons.lock_outline,
                title: s.changePassword,
                onTap: () => showChangePasswordDialog(context),
              ),
              SettingsTile(
                icon: Icons.telegram,
                title: s.customerService,
                onTap: () => _openTelegram(state),
              ),
              SettingsTile(
                icon: Icons.info_outline,
                title: s.about,
                subtitle: s.aboutSub('v1.0.0'),
                onTap: () {},
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
