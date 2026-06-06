import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/auth_brand_header.dart';
import '../../widgets/auth_cat_backdrop.dart';
import '../../widgets/pill_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _error;
  late final AnimationController _bgController;

  // 验证码状态
  bool _codeLoading = false;
  bool _codeSent = false;
  int _countdown = 0;
  Timer? _countdownTimer;

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
    _codeCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _inviteCtrl.dispose();
    _bgController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = 60;
      _codeSent = true;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() {
          _countdown = 0;
          _codeSent = false;
        });
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请先输入邮箱地址');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }

    setState(() {
      _error = null;
      _codeLoading = true;
    });

    final state = context.read<AppState>();
    try {
      final ok = await state.sendEmailCode(email, context: 'register');
      if (!mounted) return;
      if (ok) {
        _startCountdown();
        showAppSnackBar(context, state.strings.codeSent);
      }
    } finally {
      if (mounted) setState(() => _codeLoading = false);
    }
  }

  String? _validate() {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    final confirm = _confirmPwdCtrl.text;

    if (email.isEmpty || code.isEmpty || pwd.isEmpty || confirm.isEmpty) {
      return 'Please fill in all required fields';
    }
    if (!email.contains('@') || !email.contains('.')) {
      return 'Please enter a valid email address';
    }
    if (code.length < 4) {
      return 'Please enter the verification code';
    }
    if (pwd.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (pwd != confirm) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _register() async {
    setState(() => _error = null);
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    final state = context.read<AppState>();
    final ok = await state.register(
      _emailCtrl.text.trim(),
      _pwdCtrl.text,
      inviteCode: _inviteCtrl.text.trim(),
      emailCode: _codeCtrl.text.trim(),
    );

    if (ok && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  bool get _sendDisabled => _codeLoading || _codeSent;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.strings;
    final loading = state.loading;
    final apiError = state.error;
    final displayError = _error ?? (loading ? null : apiError);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _bgController,
            builder: (_, _) => CustomPaint(
              painter: _RegisterBgPainter(t: _bgController.value),
              size: Size.infinite,
            ),
          ),
          const AuthCatBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              children: [
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AuthBrandHeader(title: s.appTitle, logoSize: 64),
                const SizedBox(height: 28),
                Text(
                  s.registerTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(s.registerSubtitle, style: AppTheme.bodySecondary),
                const SizedBox(height: 32),

                // ── 账号信息 ──
                _SectionLabel(text: '账号信息'),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  enabled: !loading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: s.emailHint,
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 验证码行
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeCtrl,
                          enabled: !loading,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: s.emailCodeHint,
                            prefixIcon: const Icon(
                              Icons.pin_outlined,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SendCodeButton(
                        loading: _codeLoading,
                        disabled: _sendDisabled,
                        countdown: _countdown,
                        label: s.sendCodeButton,
                        countdownLabel: s.sendCodeCountdown(_countdown),
                        onTap: _sendCode,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                // ── 设置密码 ──
                _SectionLabel(text: '设置密码'),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  enabled: !loading,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
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
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPwdCtrl,
                  enabled: !loading,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: s.confirmPasswordHint,
                    prefixIcon: const Icon(
                      Icons.lock_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),

                const SizedBox(height: 28),
                // ── 其他 ──
                _SectionLabel(text: '邀请码（选填）'),
                const SizedBox(height: 12),
                TextField(
                  controller: _inviteCtrl,
                  enabled: !loading,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: s.inviteCodeHint,
                    prefixIcon: const Icon(
                      Icons.card_giftcard_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),

                if (displayError != null) ...[
                  const SizedBox(height: 20),
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
                            displayError,
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
                const SizedBox(height: 28),
                PillButton(
                  label: s.registerButton,
                  loading: loading,
                  onPressed: loading ? null : _register,
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: s.hasAccountHint,
                      style: AppTheme.bodySecondary,
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Text(
                              s.loginButton,
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
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 验证码发送按钮 ──

class _SendCodeButton extends StatelessWidget {
  const _SendCodeButton({
    required this.loading,
    required this.disabled,
    required this.countdown,
    required this.label,
    required this.countdownLabel,
    required this.onTap,
  });

  final bool loading;
  final bool disabled;
  final int countdown;
  final String label;
  final String countdownLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !disabled;

    return FilledButton(
      onPressed: enabled ? onTap : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.card,
        disabledForegroundColor: AppColors.textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.onPrimary,
              ),
            )
          : Text(
              countdown > 0 ? countdownLabel : label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
    );
  }
}

// ── 分组小标题 ──

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── 背景 ──

class _RegisterBgPainter extends CustomPainter {
  _RegisterBgPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = AppColors.bg);

    final phase = t * math.pi * 2;

    final topGlow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);
    topGlow.shader = RadialGradient(
      center: const Alignment(0.5, -0.55),
      radius: 0.5,
      colors: [
        AppColors.primary.withValues(alpha: 0.10),
        AppColors.primary.withValues(alpha: 0.03),
        Colors.transparent,
      ],
      stops: const [0, 0.5, 1],
    ).createShader(rect);
    final glowX = size.width * 0.6 + math.sin(phase * 0.6) * 22;
    final glowY = size.height * 0.10 + math.cos(phase * 0.5) * 14;
    canvas.drawCircle(Offset(glowX, glowY), size.width * 0.55, topGlow);

    final dotPaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.025)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    final offsetX = (t * 3) % spacing;
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
  bool shouldRepaint(covariant _RegisterBgPainter oldDelegate) =>
      oldDelegate.t != t;
}
