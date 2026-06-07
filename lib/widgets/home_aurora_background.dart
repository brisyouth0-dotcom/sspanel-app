import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 首页暗色地图风格背景
class HomeAuroraBackground extends StatefulWidget {
  const HomeAuroraBackground({super.key, required this.connected});

  final bool connected;

  @override
  State<HomeAuroraBackground> createState() => _HomeAuroraBackgroundState();
}

class _HomeAuroraBackgroundState extends State<HomeAuroraBackground>
    with SingleTickerProviderStateMixin {
  static const _backdrop = Color(0xFF0B1018);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    if (widget.connected) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(HomeAuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.connected && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _backdrop),
          CustomPaint(
            painter: _DarkMapPainter(),
            size: Size.infinite,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.transparent,
                  AppColors.bg.withValues(alpha: 0.08),
                  AppColors.bg.withValues(alpha: 0.42),
                ],
                stops: const [0, 0.35, 0.68, 1],
              ),
            ),
          ),
          if (widget.connected)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _AtmospherePainter(
                    t: _controller.value,
                    connected: widget.connected,
                  ),
                  size: Size.infinite,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DarkMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1420), Color(0xFF111827), Color(0xFF0A1018)],
        ).createShader(rect),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    const step = 28.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final landPaint = Paint()..color = const Color(0xFF1F2937).withValues(alpha: 0.55);
    final landStroke = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    void drawLand(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, landPaint);
      canvas.drawPath(path, landStroke);
    }

    drawLand([
      Offset(size.width * 0.08, size.height * 0.28),
      Offset(size.width * 0.22, size.height * 0.18),
      Offset(size.width * 0.34, size.height * 0.24),
      Offset(size.width * 0.30, size.height * 0.42),
      Offset(size.width * 0.14, size.height * 0.46),
    ]);
    drawLand([
      Offset(size.width * 0.52, size.height * 0.20),
      Offset(size.width * 0.72, size.height * 0.16),
      Offset(size.width * 0.88, size.height * 0.30),
      Offset(size.width * 0.80, size.height * 0.48),
      Offset(size.width * 0.58, size.height * 0.44),
    ]);
    drawLand([
      Offset(size.width * 0.18, size.height * 0.58),
      Offset(size.width * 0.42, size.height * 0.54),
      Offset(size.width * 0.48, size.height * 0.72),
      Offset(size.width * 0.26, size.height * 0.82),
    ]);

    final roadPaint = Paint()
      ..color = const Color(0xFF475569).withValues(alpha: 0.28)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.05, size.height * 0.62),
      Offset(size.width * 0.95, size.height * 0.38),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.08),
      Offset(size.width * 0.55, size.height * 0.92),
      roadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter({required this.t, required this.connected});

  final double t;
  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final phase = t * math.pi * 2;
    const glow = 1.0;

    final sweep = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36)
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AppColors.primary.withValues(alpha: 0),
          AppColors.primary.withValues(alpha: 0.08 * glow),
          const Color(0xFF38BDF8).withValues(alpha: 0.055 * glow),
          const Color(0xFF38BDF8).withValues(alpha: 0),
        ],
        stops: const [0, 0.34, 0.68, 1],
      ).createShader(rect);
    final y = size.height * (0.54 + 0.018 * math.sin(phase));
    final path = Path()
      ..moveTo(-size.width * 0.1, y)
      ..cubicTo(
        size.width * 0.24,
        y - 34,
        size.width * 0.72,
        y + 26,
        size.width * 1.1,
        y - 8,
      )
      ..lineTo(size.width * 1.1, y + size.height * 0.22)
      ..cubicTo(
        size.width * 0.7,
        y + size.height * 0.16,
        size.width * 0.26,
        y + size.height * 0.22,
        -size.width * 0.1,
        y + size.height * 0.14,
      )
      ..close();
    canvas.drawPath(path, sweep);

    final vignette = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x08000000), Color(0x00000000), Color(0x44000000)],
        stops: [0, 0.38, 1],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.connected != connected;
}
