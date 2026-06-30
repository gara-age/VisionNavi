import 'dart:convert';
import 'dart:io';

import '../models/home_user_settings.dart';

class HomeSettingsStore {
  HomeSettingsStore._();

  static final HomeSettingsStore instance = HomeSettingsStore._();

  Future<HomeUserSettings> load() async {
    final file = _settingsFile;
    if (!await file.exists()) {
      return const HomeUserSettings();
    }

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return HomeUserSettings.fromJson(json);
    } catch (_) {
      return const HomeUserSettings();
    }
  }

  Future<void> save(HomeUserSettings settings) async {
    final file = _settingsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  File get _settingsFile =>
      File('${Directory.current.path}/runtime/home_user_settings.json');
}
