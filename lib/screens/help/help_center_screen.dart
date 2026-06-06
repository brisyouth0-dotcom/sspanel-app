import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().strings;
    final all = s.faqPairs();

    final qNorm = _search.text.trim().toLowerCase();
    final filtered = qNorm.isEmpty
        ? all
        : all
            .where((e) => e.q.toLowerCase().contains(qNorm) || e.a.toLowerCase().contains(qNorm))
            .toList();

    final orderedCats = <String>[];
    for (final e in filtered) {
      if (!orderedCats.contains(e.category)) {
        orderedCats.add(e.category);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Text(s.helpCenter),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          TextField(
            controller: _search,
            style: const TextStyle(color: AppColors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: s.searchDocsHint,
              prefixIcon: const Icon(Icons.search, size: 22, color: AppColors.textSecondary),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          for (final cat in orderedCats) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                cat,
                style: AppTheme.bodySecondary.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            for (final e in filtered.where((x) => x.category == cat))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: AppColors.border),
                  child: Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    child: ExpansionTile(
                      iconColor: AppColors.primary,
                      collapsedIconColor: AppColors.textSecondary,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      collapsedShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.q,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.thumb_up_alt_outlined,
                            size: 16,
                            color: AppColors.primary.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            e.a,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
