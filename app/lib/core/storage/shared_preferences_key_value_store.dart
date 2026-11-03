import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [KeyValueStore] on `SharedPreferencesAsync` (no in-memory cache, so every
/// screen reads the stored value). A key holding another type, or a missing
/// platform plugin, makes the call fail; callers treat any error as
/// "missing".
final class SharedPreferencesKeyValueStore implements KeyValueStore {
  new([this._injected]);

  final SharedPreferencesAsync? _injected;

  /// Created on first use: the constructor throws when no platform plugin is
  /// registered (plain unit tests), which must surface as a failed call.
  late final SharedPreferencesAsync _prefs =
      _injected ?? SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) =>
      Future.sync(() => _prefs.getString(key));

  @override
  Future<void> setString(String key, String value) =>
      Future.sync(() => _prefs.setString(key, value));

  @override
  Future<int?> getInt(String key) => Future.sync(() => _prefs.getInt(key));

  @override
  Future<void> setInt(String key, int value) =>
      Future.sync(() => _prefs.setInt(key, value));
}

/// The app store. Widget tests override it with an in-memory map.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SharedPreferencesKeyValueStore(),
);
