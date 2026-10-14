import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/settings_store.dart';

/// Light / dark / follow-the-system. Persisted locally; nothing leaves the
/// phone.
class ThemeModeController extends Notifier<ThemeMode> {
  static const String key = 'theme_mode';

  @override
  ThemeMode build() {
    final String? stored = ref.read(settingsStoreProvider).getString(key);
    return ThemeMode.values.where((ThemeMode m) => m.name == stored).firstOrNull ??
        ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsStoreProvider).setString(key, mode.name);
  }
}

final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
