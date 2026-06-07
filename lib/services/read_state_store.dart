import 'package:shared_preferences/shared_preferences.dart';

/// 本地记录公告/工单已读状态（仅客户端展示，不影响其他端逻辑）。
class ReadStateStore {
  static const _announcementsKey = 'read_announcement_ids';
  static const _ticketsKey = 'read_ticket_ids';

  Future<Set<String>> _loadSet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key)?.toSet() ?? {};
  }

  Future<void> _saveSet(String key, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, ids.toList());
  }

  Future<Set<String>> readAnnouncementIds() => _loadSet(_announcementsKey);

  Future<void> markAnnouncementRead(String id) async {
    final ids = await readAnnouncementIds();
    if (ids.add(id)) {
      await _saveSet(_announcementsKey, ids);
    }
  }

  Future<Set<String>> readTicketIds() => _loadSet(_ticketsKey);

  Future<void> markTicketRead(String id) async {
    final ids = await readTicketIds();
    if (ids.add(id)) {
      await _saveSet(_ticketsKey, ids);
    }
  }
}
