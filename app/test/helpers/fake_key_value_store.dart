// In-memory KeyValueStore for tests (T25). Not a test file.
import 'package:napstop/core/storage/key_value_store.dart';

class FakeKeyValueStore implements KeyValueStore {
  new([Map<String, Object>? values]) : values = {...?values};

  /// Stored values; tests may put a wrong type on purpose.
  final Map<String, Object> values;

  /// Set to make every call throw it.
  Object? error;

  Future<T?> _get<T>(String key) {
    final e = error;
    if (e != null) {
      return Future<T?>.error(e);
    }
    final v = values[key];
    if (v == null) {
      return Future<T?>.value();
    }
    if (v is! T) {
      return Future<T?>.error(StateError('wrong type'));
    }
    return Future<T?>.value(v as T);
  }

  Future<void> _set(String key, Object value) {
    final e = error;
    if (e != null) {
      return Future<void>.error(e);
    }
    values[key] = value;
    return Future<void>.value();
  }

  @override
  Future<String?> getString(String key) => _get<String>(key);

  @override
  Future<void> setString(String key, String value) => _set(key, value);

  @override
  Future<int?> getInt(String key) => _get<int>(key);

  @override
  Future<void> setInt(String key, int value) => _set(key, value);
}
