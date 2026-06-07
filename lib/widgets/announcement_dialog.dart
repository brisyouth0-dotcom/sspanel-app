import 'package:flutter/material.dart';

import '../screens/announcements/announcement_screens.dart';

Future<void> showAnnouncementDialog(BuildContext context) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const AnnouncementListScreen()),
  );
}
