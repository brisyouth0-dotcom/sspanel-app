import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key, required this.title, this.logoSize = 72});

  final String title;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/app_icon.png',
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          semanticLabel: title,
        ),
        const SizedBox(height: 12),
        Text(title, style: AppTheme.titleLarge, textAlign: TextAlign.center),
      ],
    );
  }
}
