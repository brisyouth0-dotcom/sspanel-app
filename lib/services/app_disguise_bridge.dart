import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/ui_strings.dart';

enum AppDisguiseOption {
  original('original'),
  calculator('calculator'),
  weather('weather'),
  notes('notes'),
  settings('settings'),
  album('album'),
  gallery('gallery'),
  phone('phone');

  const AppDisguiseOption(this.id);

  final String id;

  static AppDisguiseOption fromId(String? id) {
    return values.firstWhere(
      (option) => option.id == id,
      orElse: () => AppDisguiseOption.original,
    );
  }
}

class AppDisguiseBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.kele.kele_vpn/app_disguise',
  );

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<AppDisguiseOption> current() async {
    if (!supported) return AppDisguiseOption.original;
    final id = await _channel.invokeMethod<String>('current');
    return AppDisguiseOption.fromId(id);
  }

  static Future<bool> apply(AppDisguiseOption option) async {
    if (!supported) return false;
    final ok = await _channel.invokeMethod<bool>('apply', {'id': option.id});
    return ok ?? false;
  }
}

extension AppDisguiseOptionLabel on AppDisguiseOption {
  String title(UiStrings s) {
    return switch (this) {
      AppDisguiseOption.original => s.appDisguiseOriginal,
      AppDisguiseOption.calculator => s.appDisguiseCalculator,
      AppDisguiseOption.weather => s.appDisguiseWeather,
      AppDisguiseOption.notes => s.appDisguiseNotes,
      AppDisguiseOption.settings => s.appDisguiseSettings,
      AppDisguiseOption.album => s.appDisguiseAlbum,
      AppDisguiseOption.gallery => s.appDisguiseGallery,
      AppDisguiseOption.phone => s.appDisguisePhone,
    };
  }

  String subtitle(UiStrings s) {
    return switch (this) {
      AppDisguiseOption.original => s.appDisguiseOriginalSub,
      AppDisguiseOption.calculator => s.appDisguiseCalculatorSub,
      AppDisguiseOption.weather => s.appDisguiseWeatherSub,
      AppDisguiseOption.notes => s.appDisguiseNotesSub,
      AppDisguiseOption.settings => s.appDisguiseSettingsSub,
      AppDisguiseOption.album => s.appDisguiseAlbumSub,
      AppDisguiseOption.gallery => s.appDisguiseGallerySub,
      AppDisguiseOption.phone => s.appDisguisePhoneSub,
    };
  }
}
