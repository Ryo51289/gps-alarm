// S01: no logging where coordinates live; generated row classes (whose
// toString prints coordinates) stay inside the data layer; screen 1 uses
// NapIcons only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final scanned = [
    for (final d in [
      'lib/core/db',
      'lib/core/trip',
      'lib/core/device',
      'lib/core/format',
      'lib/core/diagnostics',
      'lib/features/home',
      'lib/features/onboarding',
      'lib/app',
    ])
      ..._dartFiles(d),
  ];

  test('S01 files exist', () {
    expect(scanned.length, greaterThanOrEqualTo(25));
  });

  test('S01 no logging', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'log(': RegExp(r'\blog\('),
      'dart:developer': RegExp('dart:developer'),
    };
    for (final f in scanned) {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('S01 TripRow/SavedPlaceRow only in lib/core/db and core/trip/data', () {
    final row = RegExp(r'\b(TripRow|SavedPlaceRow)\b');
    for (final f in _dartFiles('lib')) {
      final path = _norm(f);
      if (path.contains('lib/core/db/') ||
          path.contains('lib/core/trip/data/')) {
        continue;
      }
      expect(row.hasMatch(f.readAsStringSync()), isFalse, reason: path);
    }
  });

  test('S01 screen 1 uses NapIcons, never Icons.*', () {
    final icons = RegExp(r'\bIcons\.');
    for (final f in _dartFiles('lib/features/home')) {
      expect(icons.hasMatch(f.readAsStringSync()), isFalse, reason: _norm(f));
    }
  });

  test('domain layers do not import Flutter', () {
    for (final f in [
      ..._dartFiles('lib/core/trip/domain'),
      ..._dartFiles('lib/features/home/domain'),
      ..._dartFiles('lib/features/onboarding/domain'),
      File('lib/core/format/distance_format.dart'),
    ]) {
      expect(
        f.readAsStringSync().contains('package:flutter/'),
        isFalse,
        reason: _norm(f),
      );
    }
  });
}
