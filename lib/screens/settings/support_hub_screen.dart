import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/settings_tile.dart';
import '../../widgets/x_logo_icon.dart';
import '../profile/tickets_screen.dart';

class SupportHubScreen extends StatefulWidget {
  const SupportHubScreen({super.key});

  @override
  State<SupportHubScreen> createState() => _SupportHubScreenState();
}

class _SupportHubScreenState extends State<SupportHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadTickets(quiet: true);
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showAppErrorSnackBar(context, '无法打开链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadTicketCount;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(state.strings.customerService)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SettingsSection(
            children: [
              SettingsTile(
                icon: Icons.support_agent_outlined,
                title: '工单',
                subtitle: '查看与创建工单，管理员回复会在此提示',
                trailing: unread > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const TicketsScreen()),
                ),
              ),
              SettingsTile(
                leading: const XLogoIcon(size: 22),
                icon: Icons.tag,
                title: 'X',
                subtitle: '跳转 X 官方账号',
                onTap: () => _openUrl(AppConfig.twitterSupportUrl),
              ),
              SettingsTile(
                icon: Icons.telegram,
                title: 'Telegram',
                subtitle: state.strings.customerServiceSub,
                onTap: () async {
                  final url = await state.telegramSupportUrl();
                  await _openUrl(url);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
