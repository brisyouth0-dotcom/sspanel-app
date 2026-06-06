import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadTickets();
    });
  }

  void _showCreateDialog() {
    final subjectCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('新建工单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectCtrl,
              decoration: const InputDecoration(hintText: '主题'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(hintText: '问题描述'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final subject = subjectCtrl.text.trim();
              final content = contentCtrl.text.trim();
              if (subject.isEmpty || content.isEmpty) {
                showAppErrorSnackBar(ctx, '请填写主题与描述');
                return;
              }
              final ok = await context.read<AppState>().createTicket(
                subject,
                content,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (mounted) {
                  showAppSnackBar(context, ok ? '工单已提交' : '提交失败');
                }
              }
            },
            child: const Text('提交'),
          ),
        ],
      ),
    );
  }

  void _openDetail(SupportTicket ticket) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            TicketDetailScreen(ticketId: ticket.id, title: ticket.subject),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tickets = context.watch<AppState>().tickets;
    final fmt = DateFormat('MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('工单管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AppState>().loadTickets(),
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _showCreateDialog),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        label: const Text('新建工单'),
        icon: const Icon(Icons.add),
      ),
      body: tickets == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : tickets.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.support_agent_outlined,
                    size: 48,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text('暂无工单', style: AppTheme.bodySecondary),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _showCreateDialog,
                    child: const Text('提交第一个工单'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => context.read<AppState>().loadTickets(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: tickets.length,
                itemBuilder: (context, i) {
                  final t = tickets[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(
                        t.subject,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            t.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fmt.format(t.updatedAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: _StatusChip(status: t.status),
                      onTap: () => _openDetail(t),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    required this.title,
  });

  final String ticketId;
  final String title;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  SupportTicket? _ticket;
  bool _loading = true;
  bool _sending = false;
  final _replyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ticket = await context.read<AppState>().fetchTicketDetail(
        widget.ticketId,
      );
      if (mounted) setState(() => _ticket = ticket);
    } catch (e) {
      if (mounted) showAppErrorSnackBar(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final ok = await context.read<AppState>().replyTicket(
        widget.ticketId,
        text,
      );
      if (!mounted) return;
      if (ok) {
        _replyCtrl.clear();
        await _load();
        if (mounted) showAppSnackBar(context, '回复已发送');
      } else {
        final error = context.read<AppState>().error;
        showAppErrorSnackBar(context, error ?? '回复失败');
      }
    } catch (e) {
      if (mounted) showAppErrorSnackBar(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('关闭工单'),
        content: const Text('确定要关闭此工单吗？关闭后将无法继续回复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final closed = await context.read<AppState>().closeTicket(widget.ticketId);
    if (!mounted) return;
    if (closed) {
      await _load();
      if (mounted) showAppSnackBar(context, '工单已关闭');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    final ticket = _ticket;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (ticket != null && !ticket.closed)
            TextButton(onPressed: _close, child: const Text('关闭')),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ticket == null
          ? const Center(child: Text('加载失败'))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          _StatusChip(status: ticket.status),
                          const SizedBox(width: 8),
                          Text(
                            fmt.format(ticket.updatedAt),
                            style: AppTheme.bodySecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (ticket.messages.isEmpty)
                        _MessageBubble(
                          text: ticket.preview,
                          isMe: true,
                          time: ticket.updatedAt,
                        )
                      else
                        ...ticket.messages.map(
                          (m) => _MessageBubble(
                            text: m.message,
                            isMe: m.isMe,
                            time: m.createdAt,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!ticket.closed)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyCtrl,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: '输入回复…',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _sending ? null : _reply,
                            child: _sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.time,
  });

  final String text;
  final bool isMe;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.cardElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 6),
            Text(
              fmt.format(time),
              style: AppTheme.bodySecondary.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TicketStatus.open => ('待回复', Colors.orange),
      TicketStatus.replied => ('已回复', AppColors.primary),
      TicketStatus.closed => ('已关闭', AppColors.textSecondary),
    };
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      backgroundColor: color.withValues(alpha: 0.1),
      padding: EdgeInsets.zero,
    );
  }
}
