import 'package:flutter/material.dart';

import '../utils/ping_style.dart';

class PingBadge extends StatelessWidget {
  const PingBadge({super.key, required this.ms});

  final int? ms;

  @override
  Widget build(BuildContext context) {
    final color = PingStyle.colorFor(ms);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        PingStyle.labelFor(ms),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
