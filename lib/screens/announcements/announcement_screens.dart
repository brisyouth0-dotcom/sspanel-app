import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class AnnouncementListScreen extends StatefulWidget {
  const AnnouncementListScreen({super.key});

  @override
  State<AnnouncementListScreen> createState() => _AnnouncementListScreenState();
}

class _AnnouncementListScreenState extends State<AnnouncementListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadAnnouncements();
    });
  }

  void _openDetail(Announcement ann) {
    context.read<AppState>().markAnnouncementRead(ann.id);
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AnnouncementDetailScreen(announcement: ann),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final announcements = state.announcements ?? [];
    final readIds = state.readAnnouncementIds;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('站点公告')),
      body: announcements.isEmpty
          ? Center(child: Text('暂无公告', style: AppTheme.bodySecondary))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: announcements.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final ann = announcements[i];
                final read = readIds.contains(ann.id);
                return _AnnouncementListTile(
                  announcement: ann,
                  read: read,
                  onTap: () => _openDetail(ann),
                );
              },
            ),
    );
  }
}

class _AnnouncementListTile extends StatelessWidget {
  const _AnnouncementListTile({
    required this.announcement,
    required this.read,
    required this.onTap,
  });

  final Announcement announcement;
  final bool read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = announcement.publishedAt;
    final dateLabel = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : '';

    return Material(
      color: read ? AppColors.card : AppColors.cardElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: read ? AppColors.border : AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (dateLabel.isNotEmpty)
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: read ? AppColors.textMuted : AppColors.primary,
                        fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                  const Spacer(),
                  if (!read)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                announcement.listTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                  color: read ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                announcement.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: read ? AppColors.textMuted : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final date = announcement.publishedAt;
    final dateLabel = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('公告详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (dateLabel.isNotEmpty)
            Text(dateLabel, style: AppTheme.bodySecondary.copyWith(fontSize: 12)),
          const SizedBox(height: 10),
          Text(
            announcement.listTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            announcement.bodyText,
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
        ],
      ),
    );
  }
}
