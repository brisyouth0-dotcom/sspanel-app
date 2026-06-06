import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/panel_exceptions.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/auth_brand_header.dart';
import '../../widgets/auth_cat_backdrop.dart';
import '../../widgets/pill_button.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _obscure = true;
  bool _needMfa = false;
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _codeCtrl.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final state = context.read<AppState>();
    state.clearError();
    try {
      await state.login(
        _emailCtrl.text.trim(),
        _pwdCtrl.text,
        code: _needMfa ? _codeCtrl.text.trim() : null,
      );
    } on MfaRequiredException catch (e) {
      setState(() => _needMfa = true);
      if (mounted) {
        showAppErrorSnackBar(context, e.message);
      }
    }
  }

  void _openRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.strings;
    final loading = state.loading;
    final error = state.error;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _bgController,
            builder: (_, _) => CustomPaint(
              painter: _LoginBgPainter(t: _bgController.value),
              size: Size.infinite,
            ),
          ),
          const AuthCatBackdrop(),
          // Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    32,
                    40,
                    32,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 64,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  AuthBrandHeader(title: s.appTitle),
                  const SizedBox(height: 36),
                  Text(
                    s.loginTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s.loginSubtitle, style: AppTheme.bodySecondary),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailCtrl,
                    enabled: !loading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: s.emailHint,
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pwdCtrl,
                    enabled: !loading,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: s.passwordHint,
                      prefixIcon: const Icon(
                        Icons.lock_outlined,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_needMfa) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeCtrl,
                      enabled: !loading,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: s.mfaHint,
                        prefixIcon: const Icon(
                          Icons.security_outlined,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.danger,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              error,
                              style: const TextStyle(
                                color: Color(0xFFFFB4B4),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  PillButton(
                    label: s.loginButton,
                    loading: loading,
                    onPressed: loading ? null : _login,
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        text: s.registerHint,
                        style: AppTheme.bodySecondary,
                        children: [
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: _openRegister,
                              child: Text(
                                s.registerLink,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a subtle animated gradient atmosphere for the login screen.
class _LoginBgPainter extends CustomPainter {
  _LoginBgPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Deep dark base
    canvas.drawRect(rect, Paint()..color = AppColors.bg);

    // Top-center teal glow
    final phase = t * math.pi * 2;
    final topGlow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    final glowY = size.height * 0.12 + math.sin(phase * 0.7) * 18;
    topGlow.shader = RadialGradient(
      center: Alignment(0, -0.62),
      radius: 0.55,
      colors: [
        AppColors.primary.withValues(alpha: 0.14),
        AppColors.primary.withValues(alpha: 0.04),
        Colors.transparent,
      ],
      stops: const [0, 0.55, 1],
    ).createShader(rect);
    canvas.drawCircle(Offset(size.width / 2, glowY), size.width * 0.6, topGlow);

    // Bottom-left subtle accent
    final accentGlow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    accentGlow.shader = RadialGradient(
      center: const Alignment(-0.7, 0.85),
      radius: 0.5,
      colors: [
        const Color(0xFF38BDF8).withValues(alpha: 0.06),
        Colors.transparent,
      ],
    ).createShader(rect);
    canvas.drawCircle(
      Offset(-size.width * 0.1, size.height * 0.88),
      size.width * 0.55,
      accentGlow,
    );

    // Subtle grid/dots pattern for texture
    final dotPaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;
    const spacing = 32.0;
    final offsetX = (t * 4) % spacing;
    for (
      double x = -spacing + offsetX;
      x < size.width + spacing;
      x += spacing
    ) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoginBgPainter oldDelegate) =>
      oldDelegate.t != t;
}
