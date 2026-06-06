import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_disguise_bridge.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

class AppDisguiseScreen extends StatelessWidget {
  const AppDisguiseScreen({super.key});

  static const _options = [
    AppDisguiseOption.original,
    AppDisguiseOption.calculator,
    AppDisguiseOption.weather,
    AppDisguiseOption.notes,
    AppDisguiseOption.settings,
    AppDisguiseOption.album,
    AppDisguiseOption.gallery,
    AppDisguiseOption.phone,
  ];

  IconData _iconFor(AppDisguiseOption option) {
    return switch (option) {
      AppDisguiseOption.original => Icons.shield_outlined,
      AppDisguiseOption.calculator => Icons.calculate_rounded,
      AppDisguiseOption.weather => Icons.wb_sunny_rounded,
      AppDisguiseOption.notes => Icons.sticky_note_2_rounded,
      AppDisguiseOption.settings => Icons.settings_rounded,
      AppDisguiseOption.album => Icons.photo_album_rounded,
      AppDisguiseOption.gallery => Icons.collections_rounded,
      AppDisguiseOption.phone => Icons.phone_rounded,
    };
  }

  Color _iconBgFor(AppDisguiseOption option) {
    return switch (option) {
      AppDisguiseOption.original => AppColors.primary.withValues(alpha: 0.18),
      AppDisguiseOption.calculator => const Color(0xFF415C66),
      AppDisguiseOption.weather => const Color(0xFF4FC3F7),
      AppDisguiseOption.notes => const Color(0xFFFFD54F),
      AppDisguiseOption.settings => const Color(0xFF607D8B),
      AppDisguiseOption.album => const Color(0xFFEC407A),
      AppDisguiseOption.gallery => const Color(0xFF26A69A),
      AppDisguiseOption.phone => const Color(0xFF43A047),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.strings;
    final selected = state.appDisguiseOption;

    return Scaffold(
      appBar: AppBar(title: Text(s.appDisguiseTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.appDisguiseIntroTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.appDisguiseIntroBody,
                        style: AppTheme.bodySecondary,
                      ),
                      if (!state.appDisguiseSupported) ...[
                        const SizedBox(height: 10),
                        Text(
                          s.appDisguiseUnsupported,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final option in _options) ...[
            _DisguiseCard(
              icon: _iconFor(option),
              iconBackground: _iconBgFor(option),
              title: option.title(s),
              subtitle: option.subtitle(s),
              selected: selected == option,
              enabled: state.appDisguiseSupported,
              onTap: () async {
                final ok = await context.read<AppState>().setAppDisguiseOption(
                  option,
                );
                if (!context.mounted) return;
                if (ok) {
                  showAppSnackBar(context, s.appDisguiseApplied);
                } else {
                  showAppErrorSnackBar(context, s.appDisguiseFailed);
                }
              },
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _DisguiseCard extends StatelessWidget {
  const _DisguiseCard({
    required this.icon,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTheme.bodySecondary),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.textMuted,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
