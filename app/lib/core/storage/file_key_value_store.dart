import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:napstop/core/storage/key_value_store.dart';

/// [KeyValueStore] in one JSON object file (T17.1 D11). Used where the
/// platform store cannot be kept out of backups: on iOS the screen 0 flags
/// live in `napstop_db/`, which native code excludes from iCloud backup.
///
/// Reads never throw: a missing, unreadable or corrupt file, or a key of
/// another type, reads as `null`. Writes replace the file atomically (a
/// temporary file next to it, then `rename`), so a write cut short leaves the
/// previous file intact; the leftover temporary file is never read.
/// Writes of one instance run one after the other.
final class FileKeyValueStore implements KeyValueStore {
  /// [locate] gives the file; called once, on first use.
  new(Future<File> Function() locate) : _locate = locate;

  final Future<File> Function() _locate;
  Future<File>? _file;
  Future<void> _writes = Future<void>.value();

  /// Suffix of the temporary file of a write.
  static const String tempSuffix = '.tmp';

  /// The backing file (resolved once).
  Future<File> get file => _file ??= _locate();

  @override
  Future<String?> getString(String key) async => switch ((await _read())[key]) {
    final String v => v,
    _ => null,
  };

  @override
  Future<void> setString(String key, String value) => _write(key, value);

  @override
  Future<int?> getInt(String key) async => switch ((await _read())[key]) {
    final int v => v,
    _ => null,
  };

  @override
  Future<void> setInt(String key, int value) => _write(key, value);

  Future<Map<String, Object?>> _read() async {
    try {
      // Missing file (first launch) included.
      final decoded = jsonDecode(await (await file).readAsString());
      return decoded is Map<String, Object?> ? decoded : const {};
    } on Object {
      return const {};
    }
  }

  Future<void> _write(String key, Object value) {
    final next = _writes.then((_) async {
      final f = await file;
      final values = Map<String, Object?>.of(await _read())..[key] = value;
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}$tempSuffix');
      await tmp.writeAsString(jsonEncode(values), flush: true);
      await tmp.rename(f.path);
    });
    // A failed write fails its caller only, not the next one.
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}
