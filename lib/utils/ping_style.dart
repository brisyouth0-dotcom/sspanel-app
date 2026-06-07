import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 节点延迟颜色：<300 绿，300–1000 黄，≥1000 橙，超时红。
class PingStyle {
  const PingStyle._();

  static Color colorFor(int? ms) {
    if (ms == null) return const Color(0xFFEF4444);
    if (ms < 300) return AppColors.primary;
    if (ms < 1000) return const Color(0xFFFACC15);
    return const Color(0xFFFB923C);
  }

  static String labelFor(int? ms) => ms == null ? '超时' : '${ms}ms';
}
