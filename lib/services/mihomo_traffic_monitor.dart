import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'mihomo_bridge.dart';

/// 订阅 mihomo `/traffic` 流式接口，获取实时上下行速率
class MihomoTrafficMonitor {
  HttpClient? _client;
  bool _running = false;
  final _buffer = StringBuffer();

  bool get isRunning => _running;

  Future<void> start(void Function(int upBps, int downBps) onUpdate) async {
    if (_running) return;
    _running = true;

    if (Platform.isAndroid) {
      await _startAndroidPoll(onUpdate);
      return;
    }

    while (_running) {
      _client?.close(force: true);
      _client = HttpClient();
      try {
        final req = await _client!.getUrl(
          Uri.parse('${AppConfig.mihomoControllerBase}/traffic'),
        );
        req.headers.set(
          'Authorization',
          'Bearer ${AppConfig.mihomoSecret}',
        );
        final res = await req.close();
        if (res.statusCode != 200) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        await for (final chunk in res.transform(utf8.decoder)) {
          if (!_running) break;
          _feed(chunk, onUpdate);
        }
      } catch (_) {
        if (_running) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
  }

  Future<void> _startAndroidPoll(
    void Function(int upBps, int downBps) onUpdate,
  ) async {
    while (_running) {
      try {
        final sample = await MihomoBridge.pollTraffic();
        if (!_running) break;
        if (sample != null) {
          onUpdate(sample.up, sample.down);
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  void _feed(String chunk, void Function(int upBps, int downBps) onUpdate) {
    _buffer.write(chunk);
    var pending = _buffer.toString();
    while (true) {
      final idx = pending.indexOf('\n');
      if (idx < 0) break;
      _parseLine(pending.substring(0, idx), onUpdate);
      pending = pending.substring(idx + 1);
    }
    _buffer
      ..clear()
      ..write(pending);
  }

  void _parseLine(String line, void Function(int upBps, int downBps) onUpdate) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return;
    try {
      final m = jsonDecode(trimmed) as Map<String, dynamic>;
      final up = (m['up'] as num?)?.toInt() ?? 0;
      final down = (m['down'] as num?)?.toInt() ?? 0;
      onUpdate(up, down);
    } catch (_) {}
  }

  void stop() {
    _running = false;
    _client?.close(force: true);
    _client = null;
    _buffer.clear();
  }
}
