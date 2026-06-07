import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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

  bool get _useImageFlag => !kIsWeb && Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    final label = '$region $name';
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.cardElevated,
      border: Border.all(color: AppColors.border),
    );

    final countryCode = flagCountryCode(label);
    if (_useImageFlag && countryCode != null) {
      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: decoration,
        child: Image.asset(
          'assets/images/flags/$countryCode.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _codeFallback(countryCode, decoration),
        ),
      );
    }

    return _emojiFlag(label, decoration);
  }

  Widget _codeFallback(String countryCode, BoxDecoration decoration) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: decoration,
      child: Text(
        countryCode.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.28,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          height: 1,
        ),
      ),
    );
  }

  Widget _emojiFlag(String label, BoxDecoration decoration) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: decoration,
      child: Text(
        flagEmoji(label),
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

String? flagCountryCode(String text) {
  final lower = text.toLowerCase();
  if (text.contains('香港') || lower.contains('hong kong') || lower.contains(' hk')) {
    return 'hk';
  }
  if (text.contains('台湾') ||
      text.contains('臺灣') ||
      lower.contains('taiwan') ||
      lower.contains(' tw')) {
    return 'tw';
  }
  if (text.contains('美国') ||
      text.contains('美國') ||
      lower.contains('united states') ||
      RegExp(r'\bus\b').hasMatch(lower)) {
    return 'us';
  }
  if (text.contains('日本') || lower.contains('japan') || lower.contains(' jp')) {
    return 'jp';
  }
  if (text.contains('新加坡') || lower.contains('singapore') || lower.contains(' sg')) {
    return 'sg';
  }
  if (text.contains('韩国') ||
      text.contains('韓國') ||
      lower.contains('korea') ||
      lower.contains(' kr')) {
    return 'kr';
  }
  if (text.contains('英国') ||
      text.contains('英國') ||
      lower.contains('united kingdom') ||
      lower.contains(' gb') ||
      lower.contains(' uk')) {
    return 'gb';
  }
  if (text.contains('德国') ||
      text.contains('德國') ||
      lower.contains('germany') ||
      lower.contains(' de')) {
    return 'de';
  }
  return 'un';
}

String flagEmoji(String text) {
  switch (flagCountryCode(text)) {
    case 'hk':
      return '🇭🇰';
    case 'tw':
      return '🇹🇼';
    case 'us':
      return '🇺🇸';
    case 'jp':
      return '🇯🇵';
    case 'sg':
      return '🇸🇬';
    case 'kr':
      return '🇰🇷';
    case 'gb':
      return '🇬🇧';
    case 'de':
      return '🇩🇪';
    default:
      return '🏳️';
  }
}
