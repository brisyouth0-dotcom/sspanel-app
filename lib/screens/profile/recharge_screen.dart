import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});

  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadRecharges();
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = context.watch<AppState>().recharges;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('充值记录')),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Text('暂无充值记录'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = records[i];
                    return Card(
                      child: ListTile(
                        title: Text('¥${r.amount.toStringAsFixed(2)}'),
                        subtitle: Text('${r.method} · ${fmt.format(r.createdAt)}'),
                        trailing: Text(
                          r.status,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
