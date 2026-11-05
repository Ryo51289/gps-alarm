// T26 S01 (no logging, no coordinates) and U19 (no history writes, D15).
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
  final scanned = _dartFiles('lib/features/tracking');

  test('S01/U19 files exist', () {
    expect(scanned.length, greaterThanOrEqualTo(14));
  });

  test('S01 no logging of the trip, no coordinates', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'dart:developer': RegExp('dart:developer'),
      'Logger(': RegExp(r'\bLogger\('),
      'destLat/destLng': RegExp(r'\bdest(Lat|Lng)\b'),
      '.lat/.lng': RegExp(r'\.(lat|lng)\b'),
    };
    final logLine = RegExp(
      r'\.log\(.*\b(state|config|trip|distance)',
      caseSensitive: false,
    );
    for (final f in scanned) {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
      for (final line in text.split('\n')) {
        expect(logLine.hasMatch(line), isFalse, reason: '${_norm(f)}: $line');
      }
    }
  });

  test('U19 one history path only (T28 HistorySync, D15)', () {
    final forbidden = RegExp(
      r'\b(pendingFinishedTrips|ackFinishedTrips|applyFinished|'
      r'markUnfinishedAsUnknown|tripsRepositoryProvider|insertStarted)\b',
    );
    for (final f in scanned) {
      expect(
        forbidden.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: _norm(f),
      );
    }
  });
}
