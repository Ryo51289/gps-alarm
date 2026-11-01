// TC36: no logging in the search module (queries are location data), and
// the domain layer stays free of Flutter.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final dirs = [
    'lib/features/destination/domain',
    'lib/features/destination/data',
    'lib/core/text',
  ];
  final files = [
    for (final d in dirs)
      ...Directory(d)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];

  test('source files exist', () {
    expect(files.length, greaterThanOrEqualTo(7));
  });

  final forbidden = <String, RegExp>{
    'print(': RegExp(r'\bprint\('),
    'debugPrint(': RegExp(r'\bdebugPrint\('),
    'log(': RegExp(r'\blog\('),
    'developer.log': RegExp(r'developer\.log'),
    'dart:developer': RegExp('dart:developer'),
  };

  for (final f in files) {
    final name = f.path.replaceAll(r'\', '/');
    test('no logging in $name', () {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${f.path}');
      }
    });
  }

  test('domain does not import Flutter', () {
    for (final f in files.where(
      (f) => f.path.replaceAll(r'\', '/').contains('/domain/'),
    )) {
      expect(
        f.readAsStringSync().contains('package:flutter'),
        isFalse,
        reason: f.path,
      );
    }
  });
}
