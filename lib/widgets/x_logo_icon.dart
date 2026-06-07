import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// X（原 Twitter）品牌图标
class XLogoIcon extends StatelessWidget {
  const XLogoIcon({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _XLogoPainter(color: color ?? AppColors.textSecondary),
      ),
    );
  }
}

class _XLogoPainter extends CustomPainter {
  _XLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.18, h * 0.08)
      ..lineTo(w * 0.46, h * 0.52)
      ..lineTo(w * 0.18, h * 0.92)
      ..lineTo(w * 0.30, h * 0.92)
      ..lineTo(w * 0.52, h * 0.60)
      ..lineTo(w * 0.72, h * 0.92)
      ..lineTo(w * 0.84, h * 0.92)
      ..lineTo(w * 0.56, h * 0.50)
      ..lineTo(w * 0.82, h * 0.08)
      ..lineTo(w * 0.70, h * 0.08)
      ..lineTo(w * 0.50, h * 0.42)
      ..lineTo(w * 0.32, h * 0.08)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _XLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
