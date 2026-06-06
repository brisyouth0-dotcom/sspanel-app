import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AuthCatBackdrop extends StatelessWidget {
  const AuthCatBackdrop({super.key});

  static const _image = 'assets/images/home_bg_cat_cutout.png';

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth * 0.72).clamp(300.0, 560.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  right: -width * 0.12,
                  bottom: -width * 0.06,
                  child: Opacity(
                    opacity: 0.24,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Image.asset(
                        _image,
                        width: width,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomRight,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
