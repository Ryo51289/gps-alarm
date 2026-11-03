// S01 (T21): screens 0 and 9 never log, use NapIcons only, and show text
// only through ARB (no Vietnamese string literal in the code).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

/// [text] without `//` comments (doc comments included).
String _code(String text) =>
    text.split('\n').map((l) => l.replaceFirst(RegExp('//.*'), '')).join('\n');

/// Letters only Vietnamese uses (with diacritics), upper or lower case.
final _vietnamese = RegExp(
  '[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]',
  caseSensitive: false,
);

void main() {
  final files = [
    ..._dartFiles('lib/features/onboarding'),
    ..._dartFiles('lib/features/battery_guide'),
  ];

  test('S01 files exist', () {
    expect(files.length, greaterThanOrEqualTo(15));
  });

  test('S01 no logging', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'log(': RegExp(r'\blog\('),
      'dart:developer': RegExp('dart:developer'),
    };
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('S01 NapIcons only, never Icons.*', () {
    for (final f in files) {
      expect(
        RegExp(r'\bIcons\.').hasMatch(f.readAsStringSync()),
        isFalse,
        reason: _norm(f),
      );
    }
  });

  test('S01 no Vietnamese text in the code', () {
    for (final f in files) {
      expect(
        _vietnamese.hasMatch(_code(f.readAsStringSync())),
        isFalse,
        reason: _norm(f),
      );
    }
  });

  test('battery guide domain does not import Flutter', () {
    for (final f in _dartFiles('lib/features/battery_guide/domain')) {
      expect(
        f.readAsStringSync().contains('package:flutter/'),
        isFalse,
        reason: _norm(f),
      );
    }
  });
}
