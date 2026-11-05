// In-memory KeyValueStore for tests (T25). Not a test file.
import 'dart:async';

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

/// [FakeKeyValueStore] with delays; [log] shows how calls interleave.
class SlowKeyValueStore extends FakeKeyValueStore {
  new({this.readDelay = Duration.zero, this.writeDelay = Duration.zero});

  final Duration readDelay;
  final Duration writeDelay;
  final List<String> log = [];

  /// When set, every read waits for it.
  Completer<void>? readGate;

  Future<T> _slowRead<T>(Future<T> Function() read) async {
    await Future<void>.delayed(readDelay);
    await readGate?.future;
    final value = await read();
    return value;
  }

  Future<void> _slowWrite(String key, Future<void> Function() write) async {
    log.add('start $key');
    await Future<void>.delayed(writeDelay);
    await write();
    log.add('end $key');
  }

  @override
  Future<String?> getString(String key) =>
      _slowRead(() => super.getString(key));

  @override
  Future<int?> getInt(String key) => _slowRead(() => super.getInt(key));

  @override
  Future<void> setString(String key, String value) =>
      _slowWrite(key, () => super.setString(key, value));

  @override
  Future<void> setInt(String key, int value) =>
      _slowWrite(key, () => super.setInt(key, value));
}
