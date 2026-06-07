import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 首页猫背景（竖版整猫图，铺满且完整显示）。
class HomeAuroraBackground extends StatefulWidget {
  const HomeAuroraBackground({super.key, required this.connected});

  final bool connected;

  @override
  State<HomeAuroraBackground> createState() => _HomeAuroraBackgroundState();
}

class _HomeAuroraBackgroundState extends State<HomeAuroraBackground>
    with SingleTickerProviderStateMixin {
  static const _backgroundImage = 'assets/images/home_bg_cat.png';
  static const _imageBackdrop = Color(0xFF12151C);

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
          const ColoredBox(color: _imageBackdrop),
          ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.45, 0, 0, 0, 0,
              0, 0.45, 0, 0, 0,
              0, 0, 0.45, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: SizedBox.expand(
              child: Image.asset(
                _backgroundImage,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.0),
                  AppColors.bg.withValues(alpha: 0.05),
                  AppColors.bg.withValues(alpha: 0.32),
                ],
                stops: const [0, 0.32, 0.62, 1],
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
