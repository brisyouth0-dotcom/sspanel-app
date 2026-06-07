import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  var _obscureOld = true;
  var _obscureNew = true;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.read<AppState>().strings;
    final old = _oldCtrl.text;
    final newPwd = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (old.isEmpty || newPwd.isEmpty) {
      showAppErrorSnackBar(context, s.passwordFieldsRequired);
      return;
    }
    if (newPwd.length < 6) {
      showAppErrorSnackBar(context, s.passwordTooShort);
      return;
    }
    if (newPwd != confirm) {
      showAppErrorSnackBar(context, s.passwordMismatch);
      return;
    }
    final ok = await context.read<AppState>().changePassword(
          oldPassword: old,
          newPassword: newPwd,
        );
    if (!mounted) return;
    if (ok) {
      showAppSnackBar(context, s.passwordChanged);
      Navigator.pop(context);
    } else {
      final err = context.read<AppState>().error;
      if (err != null) showAppErrorSnackBar(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().strings;
    final loading = context.watch<AppState>().loading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(s.changePassword)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(s.changePasswordDialogBody, style: AppTheme.bodySecondary),
          const SizedBox(height: 24),
          TextField(
            controller: _oldCtrl,
            obscureText: _obscureOld,
            decoration: InputDecoration(
              hintText: s.oldPasswordHint,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureOld ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscureOld = !_obscureOld),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _newCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              hintText: s.newPasswordHint,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(hintText: s.confirmPasswordHint),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: loading ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: Text(s.confirmChangePassword),
          ),
        ],
      ),
    );
  }
}
