// T17.1 PD01: the JSON file store of the iOS screen 0 flags.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/storage/file_key_value_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('napstop_kv_');
    file = File(p.join(tmp.path, 'sub', 'onboarding.json'));
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  FileKeyValueStore store() => FileKeyValueStore(() async => file);

  test('PD01 values written are read back, also by a new instance', () async {
    final s = store();
    expect(await s.getInt('a'), isNull);
    expect(await s.getString('b'), isNull);
    await s.setInt('a', 1);
    await s.setString('b', 'x');
    await s.setInt('a', 2);
    expect(await s.getInt('a'), 2);
    expect(await s.getString('b'), 'x');
    expect(await store().getInt('a'), 2);
    expect(await store().getString('b'), 'x');
    // The parent directory is created; no temporary file is left.
    expect(file.existsSync(), isTrue);
    expect(
      File('${file.path}${FileKeyValueStore.tempSuffix}').existsSync(),
      isFalse,
    );
  });

  test('PD01 a key of another type reads as null', () async {
    final s = store();
    await s.setString('k', '1');
    expect(await s.getInt('k'), isNull);
    await s.setInt('n', 1);
    expect(await s.getString('n'), isNull);
  });

  test(
    'PD01 a corrupt file reads as null and is replaced by the next write',
    () async {
      file.parent.createSync(recursive: true);
      for (final bad in ['{not json', '[1, 2]', '"x"', '']) {
        file.writeAsStringSync(bad);
        expect(await store().getInt('a'), isNull, reason: bad);
      }
      final s = store();
      await s.setInt('a', 1);
      expect(await store().getInt('a'), 1);
    },
  );

  test('PD01 a write cut short: the temporary file is ignored', () async {
    final s = store();
    await s.setInt('a', 1);
    // A crash between writing the temporary file and the rename.
    File('${file.path}${FileKeyValueStore.tempSuffix}')
        .writeAsStringSync('{"a": 5, "b": "half"}');
    expect(await store().getInt('a'), 1);
    expect(await store().getString('b'), isNull);
    // The next write replaces it.
    await s.setInt('a', 3);
    expect(await store().getInt('a'), 3);
    expect(await store().getString('b'), isNull);
  });

  test('PD01 concurrent writes of one instance keep every key', () async {
    final s = store();
    await Future.wait([for (var i = 0; i < 10; i++) s.setInt('k$i', i)]);
    for (var i = 0; i < 10; i++) {
      expect(await store().getInt('k$i'), i);
    }
  });

  test('PD01 an unavailable location fails writes, reads give null', () async {
    final s = FileKeyValueStore(
      () async => throw const FileSystemException('x'),
    );
    expect(await s.getInt('a'), isNull);
    await expectLater(s.setInt('a', 1), throwsA(isA<FileSystemException>()));
    // The failed write does not block the next call.
    await expectLater(s.setInt('a', 2), throwsA(isA<FileSystemException>()));
  });
}
