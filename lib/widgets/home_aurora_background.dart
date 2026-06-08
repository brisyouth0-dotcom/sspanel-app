import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 首页高级深色背景（动态点阵 + 流光粒子）
class HomeAuroraBackground extends StatefulWidget {
  const HomeAuroraBackground({super.key, required this.connected});

  final bool connected;

  @override
  State<HomeAuroraBackground> createState() => _HomeAuroraBackgroundState();
}

class _HomeAuroraBackgroundState extends State<HomeAuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _LuxuryDarkPainter(
              t: _controller.value,
              connected: widget.connected,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _LuxuryDarkPainter extends CustomPainter {
  _LuxuryDarkPainter({required this.t, required this.connected});

  final double t;
  final bool connected;

  static const _landDots = <Offset>[
    Offset(0.18, 0.28), Offset(0.22, 0.24), Offset(0.26, 0.22),
    Offset(0.30, 0.24), Offset(0.28, 0.30), Offset(0.24, 0.34),
    Offset(0.20, 0.32), Offset(0.16, 0.30), Offset(0.14, 0.26),
    Offset(0.32, 0.26), Offset(0.34, 0.32), Offset(0.30, 0.36),
    Offset(0.22, 0.38), Offset(0.18, 0.36),
    Offset(0.36, 0.52), Offset(0.34, 0.58), Offset(0.30, 0.64),
    Offset(0.28, 0.70), Offset(0.26, 0.76), Offset(0.24, 0.68),
    Offset(0.32, 0.56), Offset(0.30, 0.48),
    Offset(0.46, 0.22), Offset(0.50, 0.20), Offset(0.54, 0.22),
    Offset(0.58, 0.26), Offset(0.56, 0.30), Offset(0.52, 0.32),
    Offset(0.48, 0.28), Offset(0.44, 0.26),
    Offset(0.50, 0.36), Offset(0.54, 0.38), Offset(0.58, 0.42),
    Offset(0.56, 0.48), Offset(0.52, 0.52), Offset(0.48, 0.50),
    Offset(0.46, 0.44), Offset(0.48, 0.40),
    Offset(0.62, 0.24), Offset(0.66, 0.22), Offset(0.70, 0.24),
    Offset(0.74, 0.28), Offset(0.78, 0.30), Offset(0.82, 0.28),
    Offset(0.84, 0.32), Offset(0.80, 0.36), Offset(0.76, 0.38),
    Offset(0.72, 0.36), Offset(0.68, 0.34), Offset(0.64, 0.30),
    Offset(0.70, 0.42), Offset(0.74, 0.44), Offset(0.78, 0.42),
    Offset(0.76, 0.48), Offset(0.72, 0.50), Offset(0.68, 0.48),
    Offset(0.64, 0.44), Offset(0.66, 0.40),
    Offset(0.76, 0.58), Offset(0.78, 0.62), Offset(0.76, 0.66),
    Offset(0.72, 0.68), Offset(0.68, 0.64),
  ];

  Offset _globePoint(Offset p, double globeR, double cx, double cy, double rot) {
    final dx0 = (p.dx - 0.5) * globeR * 1.65;
    final dy0 = (p.dy - 0.44) * globeR * 1.65;
    final c = math.cos(rot);
    final s = math.sin(rot);
    return Offset(cx + dx0 * c - dy0 * s, cy + dx0 * s + dy0 * c);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final phase = t * math.pi * 2;
    final speed = connected ? 1.35 : 1.0;
    final cx = size.width * 0.5;
    final cy = size.height * 0.44;
    final globeR = size.width * 0.36;
    final rotation = t * math.pi * 2 * 0.12 * speed;

    _paintBase(canvas, size, rect, phase, cx, cy);

    // 轨道环（虚线旋转）
    _paintOrbitRings(canvas, cx, cy, size, phase, speed);

    // 扫描弧
    _paintScanArc(canvas, cx, cy, size, t, speed);

    // 连线底层
    _paintLinks(canvas, globeR, cx, cy, rotation, phase);

    // 流光粒子（沿连线运动）
    _paintFlowParticles(canvas, globeR, cx, cy, rotation, speed);

    // 闪烁点阵
    _paintTwinkleDots(canvas, globeR, cx, cy, rotation, phase, speed);

    // 环境漂浮微粒
    _paintAmbientParticles(canvas, size, phase, speed);

    _paintVignette(canvas, rect);
  }

  void _paintBase(
    Canvas canvas,
    Size size,
    Rect rect,
    double phase,
    double cx,
    double cy,
  ) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.8, 1.2),
          colors: [
            Color(0xFF020304),
            Color(0xFF080E14),
            Color(0xFF0A1218),
            Color(0xFF030506),
          ],
          stops: [0, 0.38, 0.72, 1],
        ).createShader(rect),
    );

    void bloom(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80)
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    bloom(
      Offset(size.width * (0.22 + 0.02 * math.sin(phase * 0.5)),
          size.height * 0.08),
      size.width * 0.52,
      const Color(0xFF1A3A4A).withValues(alpha: 0.20),
    );

    final pulse = 0.90 + 0.10 * math.sin(phase);
    bloom(
      Offset(cx, cy),
      size.width * 0.58 * pulse,
      AppColors.primary.withValues(alpha: connected ? 0.24 : 0.11),
    );
    bloom(
      Offset(cx, cy),
      size.width * 0.30 * pulse,
      Colors.white.withValues(alpha: connected ? 0.05 : 0.025),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.35),
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  void _paintOrbitRings(
    Canvas canvas,
    double cx,
    double cy,
    Size size,
    double phase,
    double speed,
  ) {
    for (var i = 0; i < 3; i++) {
      final rx = size.width * (0.34 + i * 0.10);
      final ry = size.width * (0.22 + i * 0.06);
      final ringRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2 * (1 + 0.02 * math.sin(phase + i)),
        height: ry * 2,
      );

      final path = Path()..addOval(ringRect);
      final metrics = path.computeMetrics().first;
      const dash = 10.0;
      const gap = 18.0;
      final offset = (t * (60 + i * 20) * speed) % (dash + gap);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = AppColors.primary
            .withValues(alpha: 0.07 + (connected ? 0.04 : 0) - i * 0.015);

      var dist = offset;
      while (dist < metrics.length) {
        final len = math.min(dash, metrics.length - dist);
        canvas.drawPath(metrics.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  void _paintScanArc(
    Canvas canvas,
    double cx,
    double cy,
    Size size,
    double time,
    double speed,
  ) {
    final sweep = 0.55;
    final start = time * math.pi * 2 * speed;
    final r = size.width * 0.40;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [
          Colors.transparent,
          AppColors.primary.withValues(alpha: connected ? 0.22 : 0.10),
          Colors.transparent,
        ],
        stops: const [0, 0.5, 1],
        transform: GradientRotation(start),
      ).createShader(rect);

    canvas.drawArc(rect, start, sweep, false, paint);
  }

  void _paintLinks(
    Canvas canvas,
    double globeR,
    double cx,
    double cy,
    double rotation,
    double phase,
  ) {
    final link = Paint()
      ..color = AppColors.primary.withValues(
        alpha: (connected ? 0.12 : 0.06) * (0.7 + 0.3 * math.sin(phase * 0.5)),
      )
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < _landDots.length - 1; i += 3) {
      final a = _globePoint(_landDots[i], globeR, cx, cy, rotation);
      final b = _globePoint(
        _landDots[(i + 2) % _landDots.length],
        globeR,
        cx,
        cy,
        rotation,
      );
      canvas.drawLine(a, b, link);
    }
  }

  void _paintFlowParticles(
    Canvas canvas,
    double globeR,
    double cx,
    double cy,
    double rotation,
    double speed,
  ) {
    final particleCount = connected ? 10 : 6;
    for (var i = 0; i < particleCount; i++) {
      final linkIndex = (i * 3) % (_landDots.length - 1);
      final a = _globePoint(_landDots[linkIndex], globeR, cx, cy, rotation);
      final b = _globePoint(
        _landDots[(linkIndex + 2) % _landDots.length],
        globeR,
        cx,
        cy,
        rotation,
      );

      final progress = (t * speed + i * 0.13) % 1.0;
      final pos = Offset.lerp(a, b, progress)!;

      // 尾迹
      final tail = Offset.lerp(a, b, (progress - 0.08).clamp(0.0, 1.0))!;
      final trail = Paint()
        ..shader = ui.Gradient.linear(
          tail,
          pos,
          [
            Colors.transparent,
            AppColors.primary.withValues(alpha: connected ? 0.35 : 0.18),
          ],
        )
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tail, pos, trail);

      // 粒子头
      canvas.drawCircle(
        pos,
        connected ? 2.2 : 1.6,
        Paint()
          ..color = Colors.white.withValues(alpha: connected ? 0.85 : 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        pos,
        connected ? 1.0 : 0.7,
        Paint()..color = AppColors.primary,
      );
    }
  }

  void _paintTwinkleDots(
    Canvas canvas,
    double globeR,
    double cx,
    double cy,
    double rotation,
    double phase,
    double speed,
  ) {
    for (var i = 0; i < _landDots.length; i++) {
      final p = _landDots[i];
      final dx0 = (p.dx - 0.5) * globeR * 1.65;
      final dy0 = (p.dy - 0.44) * globeR * 1.65;
      final dist = math.sqrt(dx0 * dx0 + dy0 * dy0) / globeR;
      if (dist > 1.05) continue;

      final pos = _globePoint(p, globeR, cx, cy, rotation);
      final edgeFade = (1 - dist).clamp(0.0, 1.0);

      // 每点独立闪烁相位
      final twinkle = 0.35 + 0.65 * math.sin(phase * 2.8 * speed + i * 0.85);
      final breathe = 0.5 + 0.5 * math.sin(phase * 1.6 + i * 1.1);
      final alpha =
          edgeFade * (connected ? 0.14 : 0.08) * (0.45 + 0.55 * twinkle);
      final radius = (1.0 + breathe * 0.9) * (connected ? 1.15 : 1.0);

      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, radius, dotPaint);

      // 高亮闪点光晕
      if (twinkle > 0.88) {
        canvas.drawCircle(
          pos,
          radius * 3.5,
          Paint()
            ..color = AppColors.primary
                .withValues(alpha: connected ? 0.22 : 0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }
  }

  void _paintAmbientParticles(Canvas canvas, Size size, double phase, double speed) {
    const count = 18;
    for (var i = 0; i < count; i++) {
      final seed = i * 1.618;
      final x = (size.width * ((seed * 0.17) % 1.0) +
          math.sin(phase * 0.4 * speed + seed) * 12);
      final y = (size.height * ((seed * 0.23 + 0.1) % 0.75) +
          math.cos(phase * 0.35 * speed + seed * 1.3) * 10);
      final flicker = 0.3 + 0.7 * math.sin(phase * 3.2 + seed * 2.1);
      canvas.drawCircle(
        Offset(x, y),
        0.6 + flicker * 0.5,
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.04 + flicker * 0.06),
      );
    }
  }

  void _paintVignette(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0.72),
          ],
          stops: const [0.45, 0.82, 1],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(0, 0.55),
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.bg.withValues(alpha: 0.65),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _LuxuryDarkPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.connected != connected;
}
