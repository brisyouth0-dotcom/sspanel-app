import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

Future<void> showChangePasswordDialog(BuildContext context) async {
  final oldCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  var obscureOld = true;
  var obscureNew = true;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final s = context.read<AppState>().strings;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(s.changePasswordDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldCtrl,
                  obscureText: obscureOld,
                  decoration: InputDecoration(
                    hintText: s.oldPasswordHint,
                    suffixIcon: IconButton(
                      icon: Icon(obscureOld ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setLocal(() => obscureOld = !obscureOld),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    hintText: s.newPasswordHint,
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setLocal(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(hintText: s.confirmPasswordHint),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final old = oldCtrl.text;
                final newPwd = newCtrl.text;
                final confirm = confirmCtrl.text;
                if (old.isEmpty || newPwd.isEmpty) {
                  showAppErrorSnackBar(ctx, s.passwordFieldsRequired);
                  return;
                }
                if (newPwd.length < 6) {
                  showAppErrorSnackBar(ctx, s.passwordTooShort);
                  return;
                }
                if (newPwd != confirm) {
                  showAppErrorSnackBar(ctx, s.passwordMismatch);
                  return;
                }
                final ok = await context.read<AppState>().changePassword(
                      oldPassword: old,
                      newPassword: newPwd,
                    );
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (hintCtx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: Text(s.passwordChanged),
                      content: Text(s.passwordReloginHint),
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.pop(hintCtx),
                          child: Text(s.confirm),
                        ),
                      ],
                    ),
                  );
                  if (context.mounted) {
                    await context.read<AppState>().logout();
                    if (!context.mounted) return;
                    Navigator.of(context, rootNavigator: true)
                        .popUntil((route) => route.isFirst);
                  }
                } else {
                  final err = context.read<AppState>().error;
                  if (err != null) showAppErrorSnackBar(ctx, err);
                }
              },
              child: Text(s.confirmChangePassword),
            ),
          ],
        );
      },
    ),
  );

  oldCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();
}
