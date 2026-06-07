import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _subjectCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (subject.isEmpty || content.isEmpty) {
      showAppErrorSnackBar(context, '请填写主题与描述');
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);
    try {
      final ok = await context.read<AppState>().createTicket(
        subject,
        content,
        quiet: true,
      );
      if (!mounted) return;
      if (ok) {
        showAppSnackBar(context, '工单已提交');
        Navigator.pop(context, true);
      } else {
        final err = context.read<AppState>().error;
        showAppErrorSnackBar(context, err ?? '提交失败');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('新建工单')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _subjectCtrl,
            decoration: const InputDecoration(hintText: '主题'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _contentCtrl,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '问题描述',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Text('提交'),
          ),
        ],
      ),
    );
  }
}
