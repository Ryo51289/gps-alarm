// T25 S01: no logging where the destination lives; coordinates only reach
// startTrip from the start flow; screen 3 uses NapIcons; domain is pure.
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
  final scanned = [
    for (final d in [
      'lib/features/alarm_settings',
      'lib/core/preferences',
      'lib/core/storage',
      // T29: only the part screen 3 uses. The rest of lib/core/telemetry is
      // the telemetry API itself (`CrashSink.log`, `AppAnalytics.log`) and
      // has its own scan (test/core/telemetry/source_scan_test.dart).
      'lib/core/telemetry/remote_config',
      'lib/core/text',
    ])
      ..._dartFiles(d),
  ];

  test('S01 files exist', () {
    expect(scanned.length, greaterThanOrEqualTo(25));
    expect(
      scanned.map(_norm),
      contains(
        endsWith('alarm_settings/presentation/alarm_settings_screen.dart'),
      ),
    );
  });

  test('S01 no logging', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      // T29: `analytics.log(event)` sends a typed, guarded Analytics event
      // (no value of the config or the draft); it is not logging.
      'log(': RegExp(r'(?<!analytics\.)\blog\('),
      'Logger(': RegExp(r'\bLogger\('),
      'developer.log': RegExp(r'developer\.log'),
      'dart:developer': RegExp('dart:developer'),
    };
    for (final f in scanned) {
      final text = _code(f);
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('S01 destLat:/destLng: only in trip_starter.dart', () {
    // Named arguments only; the validator messages ("destLat: out of
    // range") are not coordinates.
    final re = RegExp(r'\bdest(Lat|Lng):(?! out of range)');
    for (final f in _dartFiles('lib/features/alarm_settings')) {
      if (_norm(f).endsWith('domain/trip_starter.dart')) {
        expect(re.hasMatch(_code(f)), isTrue);
        continue;
      }
      expect(re.hasMatch(_code(f)), isFalse, reason: _norm(f));
    }
  });

  test('screen 3 uses NapIcons, never Icons.*', () {
    final icons = RegExp(r'\bIcons\.');
    for (final f in _dartFiles('lib/features/alarm_settings')) {
      expect(icons.hasMatch(_code(f)), isFalse, reason: _norm(f));
    }
  });

  test('domain and pure helpers do not import Flutter', () {
    final flutter = RegExp(r'''import\s+'package:flutter(_riverpod)?/''');
    for (final f in [
      ..._dartFiles('lib/features/alarm_settings/domain'),
      File('lib/core/preferences/trip_settings.dart'),
      File('lib/core/preferences/alarm_preferences.dart'),
      File('lib/core/telemetry/remote_config/engine_params_override.dart'),
      File('lib/core/telemetry/remote_config/strict_json.dart'),
      File('lib/core/storage/key_value_store.dart'),
      File('lib/core/text/kotlin_blank.dart'),
    ]) {
      expect(flutter.hasMatch(f.readAsStringSync()), isFalse, reason: _norm(f));
    }
  });
}
