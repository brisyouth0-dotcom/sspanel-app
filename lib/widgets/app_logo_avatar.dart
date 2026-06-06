import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 用户头像统一使用应用 Logo。
class AppLogoAvatar extends StatelessWidget {
  const AppLogoAvatar({super.key, this.radius = 26});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.cardElevated,
      backgroundImage: const AssetImage('assets/app_icon.png'),
    );
  }
}
