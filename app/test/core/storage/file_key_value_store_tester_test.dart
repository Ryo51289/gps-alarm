// Tester T17.1: FileKeyValueStore beyond PD01 (atomic replace, rollback on a
// failed write, odd JSON values).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/storage/file_key_value_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('napstop_kv_t_');
    file = File(p.join(tmp.path, 'napstop_db', 'onboarding.json'));
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  FileKeyValueStore store() => FileKeyValueStore(() async => file);

  test('a write that cannot complete leaves the previous file intact '
      '(the target is only replaced by rename)', () async {
    final s = store();
    await s.setInt('done', 1);
    final before = file.readAsStringSync();
    // Block the temporary file: a directory with its name.
    Directory('${file.path}${FileKeyValueStore.tempSuffix}').createSync();
    await expectLater(s.setInt('done', 2), throwsA(isA<FileSystemException>()));
    expect(file.readAsStringSync(), before);
    expect(await store().getInt('done'), 1);
  });

  test('values of the wrong JSON type, null and nested objects read as null',
      () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '{"i": 1.5, "s": 3, "n": null, "o": {"a": 1}, "ok": 7, "t": "x"}',
    );
    final s = store();
    expect(await s.getInt('i'), isNull);
    expect(await s.getString('s'), isNull);
    expect(await s.getInt('n'), isNull);
    expect(await s.getString('o'), isNull);
    expect(await s.getInt('ok'), 7);
    expect(await s.getString('t'), 'x');
    // A write keeps the other keys as they are.
    await s.setInt('new', 2);
    final again = store();
    expect(await again.getInt('ok'), 7);
    expect(await again.getString('t'), 'x');
    expect(await again.getInt('new'), 2);
  });

  test('a corrupt file is never thrown at the caller of a write either',
      () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"done": 1');
    final s = store();
    await s.setInt('other', 5);
    expect(await store().getInt('other'), 5);
    // The corrupt content is dropped, not merged.
    expect(await store().getInt('done'), isNull);
  });
}
