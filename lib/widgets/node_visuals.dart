import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class NodeFlag extends StatelessWidget {
  const NodeFlag({
    super.key,
    required this.region,
    required this.name,
    this.size = 42,
  });

  final String region;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.cardElevated,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        flagEmoji('$region $name'),
        style: TextStyle(fontSize: size * 0.62, height: 1),
      ),
    );
  }
}

class NodeSignal extends StatelessWidget {
  const NodeSignal({
    super.key,
    required this.status,
    this.active = true,
  });

  final NodeStatus status;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final strength = status == NodeStatus.online ? 4 : 1;
    final color = active
        ? (status == NodeStatus.online ? AppColors.primary : AppColors.danger)
        : AppColors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ...List.generate(4, (i) {
          final on = i < strength;
          return Container(
            width: 4,
            height: 8.0 + i * 4,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: on ? color : AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active && status == NodeStatus.online
                ? const Color(0xFFB7F26A)
                : AppColors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

String flagEmoji(String text) {
  if (text.contains('香港')) return '🇭🇰';
  if (text.contains('台湾') || text.contains('臺灣')) return '🇹🇼';
  if (text.contains('美国') ||
      text.contains('美國') ||
      text.toLowerCase().contains('us')) {
    return '🇺🇸';
  }
  if (text.contains('日本')) return '🇯🇵';
  if (text.contains('新加坡')) return '🇸🇬';
  if (text.contains('韩国') || text.contains('韓國')) return '🇰🇷';
  if (text.contains('英国') || text.contains('英國')) return '🇬🇧';
  if (text.contains('德国') || text.contains('德國')) return '🇩🇪';
  return '🏳️';
}
