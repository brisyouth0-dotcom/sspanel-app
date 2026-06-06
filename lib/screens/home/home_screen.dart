import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final state = context.watch<AppState>();
    final profile = state.profile;
    if (profile == null) return const SizedBox.shrink();

    final selected = state.nodeById(state.selectedNodeId);
    final daysLeft = profile.expireAt?.difference(DateTime.now()).inDays;
    final s = state.strings;

    return Stack(
      fit: StackFit.expand,
      children: [
        HomeAuroraBackground(connected: state.isConnected),
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
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Colors.white.withValues(alpha: 0.85),
                            blurRadius: 6,
                          ),
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    _AnnouncementBell(
                      count: state.announcements?.length ?? 0,
                      onTap: () => showAnnouncementDialog(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: AppCard(
                  color: AppColors.card.withValues(alpha: 0.64),
                  borderColor: AppColors.border.withValues(alpha: 0.46),
                  child: Row(
                    children: [
                      const AppLogoAvatar(radius: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: _Tag(profile.planName)),
                                if (profile.hasActiveSubscription &&
                                    daysLeft != null) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      s.daysLeftLine(daysLeft),
                                      style: AppTheme.bodySecondary,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          context.read<AppState>().goToShellTab(1);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          s.upgradePlan,
                          style: const TextStyle(
                            fontSize: 15,
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
                          state.isConnected ? s.connected : s.disconnected,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: state.isConnected
                                ? const Color(0xFF14532D)
                                : const Color(0xFF1E293B),
                            shadows: const [
                              Shadow(color: Color(0xE6FFFFFF), blurRadius: 10),
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ConnectButton(
                          connected: state.isConnected,
                          loading: state.connecting,
                          connectLabel: s.tapConnect,
                          disconnectLabel: s.tapDisconnect,
                          onTap: () async {
                            final error = await state
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
                              final err = await state.exportIosSubscription();
                              if (!context.mounted) return;
                              if (err != null) {
                                showAppErrorSnackBar(context, err);
                              } else {
                                showAppSnackBar(context, '订阅链接已复制');
                              }
                            },
                            onOpenShadowrocket: () async {
                              final err = await state.exportIosSubscription(
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
              if (state.isConnected && state.mihomoSupported)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _TrafficPanel(
                    upload: state.trafficUpBps,
                    download: state.trafficDownBps,
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
              if (state.isConnected && state.mihomoSupported)
                const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _CurrentNodeBar(
                  nodeName: selected?.name ?? s.selectServer,
                  region: selected?.region ?? '--',
                  onTap: () => showNodePickerSheet(context),
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
    return IconButton(
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        backgroundColor: AppColors.primary,
        child: const Icon(
          Icons.notifications_none,
          size: 22,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.44)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SpeedTile(
                    icon: Icons.arrow_upward_rounded,
                    color: const Color(0xFF34D399),
                    label: uploadLabel,
                    value: formatSpeed(upload),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SpeedTile(
                    icon: Icons.arrow_downward_rounded,
                    color: const Color(0xFF60A5FA),
                    label: downloadLabel,
                    value: formatSpeed(download),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label, style: AppTheme.bodySecondary.copyWith(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.data_usage_rounded,
                  color: Color(0xFF10B981),
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTheme.bodySecondary.copyWith(
                        color: const Color(0xFF047857),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      usageText,
                      style: AppTheme.bodySecondary.copyWith(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF064E3B),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.76),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF10B981),
              ),
            ),
          ),
        ],
      ),
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
