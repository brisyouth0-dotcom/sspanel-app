import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/node_visuals.dart';
import '../../utils/format_bytes.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/node_picker_sheet.dart';
import '../../widgets/announcement_dialog.dart';
import '../../widgets/app_logo_avatar.dart';
import '../../widgets/connect_button.dart';
import '../../widgets/home_aurora_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.loadNodes();
      state.loadAnnouncements();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AppState, UserProfile?>((s) => s.profile);
    if (profile == null) return const SizedBox.shrink();

    final state = context.watch<AppState>();
    final selected = state.effectiveNode;
    final daysLeft = profile.expireAt?.difference(DateTime.now()).inDays;
    final s = context.read<AppState>().strings;
    final isConnected = context.select<AppState, bool>((s) => s.isConnected);
    final connecting = context.select<AppState, bool>((s) => s.connecting);
    final mihomoSupported =
        context.select<AppState, bool>((s) => s.mihomoSupported);
    final unreadAnnouncements =
        context.select<AppState, int>((s) => s.unreadAnnouncementCount);

    return Stack(
      fit: StackFit.expand,
      children: [
        Selector<AppState, bool>(
          selector: (_, state) => state.isConnected,
          builder: (_, connected, __) =>
              HomeAuroraBackground(connected: connected),
        ),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.welcomeBack,
                      style: AppTheme.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 10,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    _AnnouncementBell(
                      count: unreadAnnouncements,
                      onTap: () => showAnnouncementDialog(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: AppCard(
                  color: AppColors.card.withValues(alpha: 0.82),
                  borderColor: AppColors.border.withValues(alpha: 0.55),
                  child: Row(
                    children: [
                      const AppLogoAvatar(radius: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.planName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (profile.hasActiveSubscription &&
                                daysLeft != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                s.daysLeftLine(daysLeft),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          context.read<AppState>().goToShellTab(1);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              AppColors.badgeOrange.withValues(alpha: 0.16),
                          foregroundColor: AppColors.badgeOrange,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          s.upgradePlan,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isConnected ? s.connected : s.disconnected,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: isConnected
                                ? const Color(0xFF6EE7B7)
                                : Colors.white,
                            shadows: const [
                              Shadow(
                                color: Color(0xCC000000),
                                blurRadius: 12,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ConnectButton(
                          connected: isConnected,
                          loading: connecting,
                          connectLabel: s.tapConnect,
                          disconnectLabel: s.tapDisconnect,
                          onTap: () async {
                            final error = await context
                                .read<AppState>()
                                .toggleConnectionWithFeedback();
                            if (!context.mounted) return;
                            if (error != null) {
                              showAppErrorSnackBar(context, error);
                            }
                          },
                        ),
                        if (Platform.isIOS) ...[
                          const SizedBox(height: 12),
                          _IosExportHint(
                            onCopy: () async {
                              final err = await context
                                  .read<AppState>()
                                  .exportIosSubscription();
                              if (!context.mounted) return;
                              if (err != null) {
                                showAppErrorSnackBar(context, err);
                              } else {
                                showAppSnackBar(context, '订阅链接已复制');
                              }
                            },
                            onOpenShadowrocket: () async {
                              final err = await context
                                  .read<AppState>()
                                  .exportIosSubscription(
                                    openShadowrocket: true,
                                  );
                              if (!context.mounted) return;
                              if (err != null) {
                                showAppErrorSnackBar(context, err);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (isConnected && mihomoSupported)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Selector<AppState, (int, int)>(
                    selector: (_, state) =>
                        (state.trafficUpBps, state.trafficDownBps),
                    builder: (_, traffic, __) => _TrafficPanel(
                      upload: traffic.$1,
                      download: traffic.$2,
                      uploadLabel: s.uploadLabel,
                      downloadLabel: s.downloadLabel,
                      remainingLabel: '剩余流量',
                      remainingValue: _trafficLabel(profile.remainingTrafficGb),
                      usageText:
                          '已用 ${_trafficLabel(profile.usedTrafficGb)} / ${_trafficLabel(profile.totalTrafficGb)}',
                      usagePercent: profile.usagePercent,
                      title: s.realtimeTraffic,
                    ),
                  ),
                ),
              if (isConnected && mihomoSupported)
                const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Builder(
                  builder: (context) {
                    final displayName = state.connectionDisplayName(
                      fallback: s.selectServer,
                    );
                    return _CurrentNodeBar(
                      nodeName: displayName,
                      region: selected?.region ?? displayName,
                      onTap: () => showNodePickerSheet(context),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _trafficLabel(double gb) {
  if (gb >= 1024) {
    final tb = gb / 1024;
    return '${tb.toStringAsFixed(tb >= 10 ? 0 : 1)} TB';
  }
  return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
}

class _CurrentNodeBar extends StatelessWidget {
  const _CurrentNodeBar({
    required this.nodeName,
    required this.region,
    required this.onTap,
  });

  final String nodeName;
  final String region;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.44)),
          ),
          child: Row(
            children: [
              NodeFlag(region: region, name: nodeName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nodeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementBell extends StatelessWidget {
  const _AnnouncementBell({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 9 ? '9+' : '$count'),
          backgroundColor: AppColors.primary,
          child: const Icon(
            Icons.notifications_none,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({
    required this.upload,
    required this.download,
    required this.uploadLabel,
    required this.downloadLabel,
    required this.remainingLabel,
    required this.remainingValue,
    required this.usageText,
    required this.usagePercent,
    required this.title,
  });

  final int upload;
  final int download;
  final String uploadLabel;
  final String downloadLabel;
  final String remainingLabel;
  final String remainingValue;
  final String usageText;
  final double usagePercent;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.44)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const Spacer(),
                _CompactSpeed(
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFF34D399),
                  label: uploadLabel,
                  value: formatSpeed(upload),
                ),
                const SizedBox(width: 12),
                _CompactSpeed(
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFF60A5FA),
                  label: downloadLabel,
                  value: formatSpeed(download),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _TrafficQuotaTile(
              label: remainingLabel,
              value: remainingValue,
              usageText: usageText,
              usagePercent: usagePercent,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSpeed extends StatelessWidget {
  const _CompactSpeed({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.65),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _TrafficQuotaTile extends StatelessWidget {
  const _TrafficQuotaTile({
    required this.label,
    required this.value,
    required this.usageText,
    required this.usagePercent,
  });

  final String label;
  final String value;
  final String usageText;
  final double usagePercent;

  @override
  Widget build(BuildContext context) {
    final percent = usagePercent.clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFF34D399),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.data_usage_rounded,
              color: Color(0xFF6EE7B7),
              size: 14,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$label · $usageText',
                style: AppTheme.bodySecondary.copyWith(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF6EE7B7),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IosExportHint extends StatelessWidget {
  const _IosExportHint({
    required this.onCopy,
    required this.onOpenShadowrocket,
  });

  final VoidCallback onCopy;
  final VoidCallback onOpenShadowrocket;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'iPhone 内置 VPN 需 Network Extension 签名',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '可先复制订阅或导入 Shadowrocket / Stash 使用',
            style: AppTheme.bodySecondary.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCopy,
                  child: const Text('复制订阅', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpenShadowrocket,
                  child: const Text(
                    'Shadowrocket',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
