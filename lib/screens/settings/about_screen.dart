import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().strings;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(s.about)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.appTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(s.aboutSub('v1.0.0'), style: AppTheme.bodySecondary),
                const SizedBox(height: 20),
                Text(
                  '关于内容稍后补充。',
                  style: AppTheme.bodySecondary.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
