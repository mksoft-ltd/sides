import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small synchronous-read key/value store for settings and the cached
/// ad-free entitlement. A seam so widget tests never await a plugin.
abstract class SettingsStore {
  String? getString(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, Object>? initial])
      : values = <String, Object>{...?initial};
  final Map<String, Object> values;

  @override
  String? getString(String key) => values[key] as String?;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<void> setString(String key, String value) async =>
      values[key] = value;
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
}

/// Overridden in `main()` with the loaded SharedPreferences, and in tests
/// with [InMemorySettingsStore].
final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => throw UnimplementedError('settingsStoreProvider not overridden'),
);
