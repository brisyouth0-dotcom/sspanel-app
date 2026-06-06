import 'package:flutter/material.dart';

class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key, this.title = '灵猫加速器'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(color: Color(0xFFFF5F57)),
                SizedBox(width: 8),
                _Dot(color: Color(0xFFFFBD2E)),
                SizedBox(width: 8),
                _Dot(color: Color(0xFF28C840)),
              ],
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
