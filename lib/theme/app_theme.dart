import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 深色底 + 青绿色强调。
class AppColors {
  static const bg = Color(0xFF0D0D0D);
  static const surface = Color(0xFF141418);
  static const card = Color(0xFF1E1E26);
  static const cardElevated = Color(0xFF26262E);
  static const border = Color(0xFF2C2C34);

  static const primary = Color(0xFF23B79C);
  static const primaryDim = Color(0xFF137C6A);
  static const onPrimary = Color(0xFF0F1014);

  static const textPrimary = Color(0xFFF3F4F6);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);

  static const danger = Color(0xFFF87171);
  static const dangerBg = Color(0xFF3D1F1F);

  static const statGreen = Color(0xFF152318);
  static const statPurple = Color(0xFF1A1528);
  static const statBlue = Color(0xFF121A28);
  static const statOrange = Color(0xFF231A12);

  static const badgeOrange = Color(0xFFF97316);
  static const badgeYellow = Color(0xFFEAB308);
  static const badgePurple = Color(0xFFA855F7);
}

class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme,
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.cardElevated;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.all(AppColors.textPrimary),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.dangerBg,
        behavior: SnackBarBehavior.fixed,
        contentTextStyle: const TextStyle(
          color: Color(0xFFFFB4B4),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.danger),
        ),
      ),
    );
  }

  static TextStyle get titleLarge => const TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleMedium => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodySecondary =>
      const TextStyle(fontSize: 12, color: AppColors.textSecondary);
}
