import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 圆形连接按钮：未连接灰色，已连接青柠绿高亮。
class ConnectButton extends StatelessWidget {
  const ConnectButton({
    super.key,
    required this.connected,
    required this.loading,
    required this.onTap,
    this.connectLabel = '点击连接',
    this.disconnectLabel = '点击断开',
    this.connectingLabel = '连接中…',
  });

  final bool connected;
  final bool loading;
  final VoidCallback onTap;
  final String connectLabel;
  final String disconnectLabel;
  final String connectingLabel;

  static const double _size = 112;

  @override
  Widget build(BuildContext context) {
    final label = loading
        ? connectingLabel
        : (connected ? disconnectLabel : connectLabel);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected
                  ? AppColors.primary.withValues(alpha: 0.86)
                  : AppColors.card.withValues(alpha: 0.68),
              border: Border.all(
                color: connected
                    ? AppColors.primary.withValues(alpha: 0.9)
                    : AppColors.border.withValues(alpha: 0.52),
                width: connected ? 2.5 : 1,
              ),
              boxShadow: connected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: connected ? Colors.white : AppColors.primary,
                      ),
                    )
                  : Icon(
                      Icons.power_settings_new_rounded,
                      size: 44,
                      color: connected ? Colors.white : AppColors.textMuted,
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: connected
                    ? const Color(0xFF6EE7B7)
                    : Colors.white.withValues(alpha: 0.88),
                shadows: const [
                  Shadow(
                    color: Color(0xCC000000),
                    blurRadius: 10,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
