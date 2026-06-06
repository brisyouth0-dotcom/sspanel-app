import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// 全局加载遮罩：请求进行中时拦截点击，转圈交给当前页面/按钮显示。
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.loading) return const SizedBox.shrink();

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.16)),
      ),
    );
  }
}
