import 'package:napstop/core/storage/key_value_store.dart';

/// [KeyValueStore] kept in memory for the session: the default store of the
/// no-op telemetry (widget tests need no override).
final class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> _values = {};

  @override
  Future<String?> getString(String key) async => switch (_values[key]) {
    final String v => v,
    _ => null,
  };

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<int?> getInt(String key) async => switch (_values[key]) {
    final int v => v,
    _ => null,
  };

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;
}
