// T27 W23: no logging in lib/features/alarm (URL, coordinates, destination
// name and distances never leave as text); the Maps URL is built in one
// place only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

/// Source without `//` comments.
String _code(File f) => f
    .readAsStringSync()
    .split('\n')
    .map((l) => l.replaceFirst(RegExp('//.*'), ''))
    .join('\n');

void main() {
  final files = _dartFiles('lib/features/alarm');

  test('W23 files exist', () {
    expect(files.length, greaterThanOrEqualTo(9));
  });

  test('W23 no print, debugPrint or logger', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      // `analytics.log(event)` is the typed, guarded Analytics API.
      'log(': RegExp(r'(?<!analytics\s*\.)\blog\('),
      'Logger(': RegExp(r'\bLogger\('),
      'appLog': RegExp(r'\bappLog\b'),
      'dart:developer': RegExp('dart:developer'),
    };
    for (final f in files) {
      final text = _code(f);
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('W23 uri / lat / lng never reach a report or an event', () {
    // Arguments of reportNonFatal are (literal, error, stack) only; an
    // Analytics event of this feature only carries an action and a bit.
    final report = RegExp(r'reportNonFatal\(([^;]*)\);');
    final event = RegExp(r'OvershootActionEvent\(([^;]*?)\)');
    for (final f in files) {
      final text = _code(f);
      for (final m in report.allMatches(text)) {
        final args = m.group(1)!;
        for (final bad in ['uri', 'lat', 'lng', 'destination', 'pastM']) {
          expect(
            RegExp('\\b$bad\\b').hasMatch(args),
            isFalse,
            reason: '$bad in reportNonFatal of ${_norm(f)}',
          );
        }
      }
      for (final m in event.allMatches(text)) {
        expect(
          m.group(1)!.replaceAll(RegExp(r'\s'), ''),
          matches(
            RegExp(r'^action:OvershootActionTag\.\w+,simulated:[^,]+,?$'),
          ),
          reason: _norm(f),
        );
      }
    }
    final builders = files
        .where((f) => _code(f).contains('/maps/dir/'))
        .map(_norm)
        .toList();
    expect(builders, ['lib/features/alarm/domain/route_back.dart']);
  });
}
