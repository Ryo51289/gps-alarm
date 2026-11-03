// T29 tester (review R2-1 guard + extra static scans): every text that may
// reach Crashlytics as a message must come from a code literal, never from
// app data (station ids, destination names, search text, coordinates).
//
// - `reportNonFatal(` call sites: the first argument (`where`, sent as the
//   message of a non-fatal) is a plain string literal without `$`.
// - `SafeDiagnostic` classes (the only errors whose message is sent): a
//   closed, reviewed list; each is constructed only where reviewed, from
//   literals (or names that are code literals).
// - Custom keys: only `CrashReporter.setKey(CrashKey.<member>, …)`;
//   `setCustomKey` only behind the allowlist; the allowlist equals §4.2.
// - Raw sink calls (`recordError`, `log`) only inside CrashReporter.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/crash/crash_keys.dart';

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

/// Source without `//` comments (doc comments included).
String _code(File f) => f
    .readAsStringSync()
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'(^|\s)//.*'), ''))
    .join('\n');

/// A plain single-line string literal without interpolation or escapes.
const String _plainLiteral = r'''('[^'$\\\n]*'|"[^"$\\\n]*")''';

void main() {
  final lib = {
    for (final f in _dartFiles('lib'))
      if (!_norm(f).startsWith('lib/l10n/gen/')) _norm(f): _code(f),
  };

  int countIn(String text, RegExp re) => re.allMatches(text).length;

  group('R2-1 reportNonFatal(where, …)', () {
    test('every call site passes a plain string literal as `where`', () {
      final call = RegExp(r'\breportNonFatal\(');
      final definition = RegExp(r'void\s+reportNonFatal\(');
      final literalFirst = RegExp(
        r'\breportNonFatal\(\s*'
        '$_plainLiteral'
        r'\s*,',
      );
      var calls = 0;
      for (final MapEntry(key: path, value: text) in lib.entries) {
        final all = countIn(text, call) - countIn(text, definition);
        final ok = countIn(text, literalFirst);
        expect(
          ok,
          all,
          reason:
              '$path: $all reportNonFatal call(s), only $ok with a literal '
              r'`where` (no $, no variable, no concatenation)',
        );
        calls += all;
      }
      // The 5 reviewed call sites (trip_providers ×2, destination_controller
      // ×3); a scan that finds nothing is broken.
      expect(calls, greaterThanOrEqualTo(5));
    });

    test('the scan itself rejects interpolated or variable `where`', () {
      final literalFirst = RegExp(
        r'\breportNonFatal\(\s*'
        '$_plainLiteral'
        r'\s*,',
      );
      const bad = [
        r"reportNonFatal('save ${place.name}', e, st)",
        r"reportNonFatal('save $name', e, st)",
        'reportNonFatal(where, e, st)',
        "reportNonFatal('a' + name, e, st)",
        'reportNonFatal(name.toString(), e, st)',
      ];
      for (final b in bad) {
        expect(literalFirst.hasMatch(b), isFalse, reason: b);
      }
      expect(
        literalFirst.hasMatch("reportNonFatal(\n  'destination.x',\n e, st)"),
        isTrue,
      );
    });

    test('NonFatalError is built only by reportNonFatal', () {
      final ctor = RegExp(r'\bNonFatalError\(');
      for (final MapEntry(key: path, value: text) in lib.entries) {
        final n = countIn(text, ctor);
        if (path == 'lib/core/diagnostics/report_error.dart') {
          // `NonFatalError(where, error.runtimeType.toString())` and the
          // `toString` text 'NonFatalError(...)'.
          expect(
            text.contains('NonFatalError(where, error.runtimeType.toString())'),
            isTrue,
          );
          expect(n, 2, reason: path);
        } else {
          expect(n, 0, reason: '$path builds a NonFatalError');
        }
      }
    });
  });

  group('R2-1 SafeDiagnostic classes', () {
    test('closed, reviewed list of implementers', () {
      final impl = RegExp(
        r'class\s+(\w+)[^{;]*\b(?:implements|with|extends)\b[^{;]*\bSafeDiagnostic\b',
      );
      final found = <String, String>{};
      for (final MapEntry(key: path, value: text) in lib.entries) {
        for (final m in impl.allMatches(text)) {
          found[m.group(1)!] = path;
        }
      }
      // A new SafeDiagnostic sends its toString() to Crashlytics: it must
      // be reviewed and added here (with a construction-site check below).
      expect(found, {
        'NonFatalError': 'lib/core/diagnostics/report_error.dart',
        'GuardViolation': 'lib/core/telemetry/analytics/analytics_guard.dart',
        'RemoteConfigInvalid':
            'lib/core/telemetry/remote_config/engine_params_source.dart',
        'TripConfigRejected':
            'lib/features/alarm_settings/data/trip_start_reporter.dart',
      });
    });

    test('RemoteConfigInvalid: const, no argument', () {
      for (final MapEntry(key: path, value: text) in lib.entries) {
        final all = countIn(text, RegExp(r'\bRemoteConfigInvalid\((?!\$)'));
        final constNoArg = countIn(
          text,
          RegExp(r'const\s+RemoteConfigInvalid\(\)'),
        );
        // The `(?!\$)` lookahead skips the toString text
        // 'RemoteConfigInvalid($kTripEngineParamsKey)' (a const key name).
        expect(all, constNoArg, reason: path);
      }
    });

    test('TripConfigRejected: built once, from validateTripConfig', () {
      final ctor = RegExp(r'\bTripConfigRejected\((?!\$)');
      for (final MapEntry(key: path, value: text) in lib.entries) {
        final n = countIn(text, ctor);
        if (path ==
            'lib/features/alarm_settings/data/trip_start_reporter.dart') {
          expect(text.contains('TripConfigRejected(rule)'), isTrue);
          // The construction only (the lookahead skips the toString text).
          expect(n, 1, reason: path);
        } else {
          expect(n, 0, reason: '$path builds a TripConfigRejected');
        }
      }
      // `rule` only ever comes from validateTripConfig…
      final starter =
          lib['lib/features/alarm_settings/domain/trip_starter.dart']!;
      expect(starter, contains('final rule = validateTripConfig('));
      final reporterCalls = [
        for (final MapEntry(key: path, value: text) in lib.entries)
          for (final _ in RegExp(r'\.configRejected\(').allMatches(text)) path,
      ];
      expect(reporterCalls, [
        'lib/features/alarm_settings/domain/trip_starter.dart',
      ]);
      expect(starter, contains('..configRejected(rule)'));
      // …whose every return is null or a plain literal (no value in it).
      final builder =
          lib['lib/features/alarm_settings/domain/trip_config_builder.dart']!;
      final start = builder.indexOf('String? validateTripConfig(');
      expect(start, isNonNegative);
      final body = builder.substring(start, builder.indexOf('\n}\n', start));
      final returns = RegExp(r'\breturn\b([^;]*);').allMatches(body).toList();
      expect(returns.length, greaterThanOrEqualTo(15));
      for (final r in returns) {
        final v = r.group(1)!.trim();
        expect(
          v == 'null' || RegExp('^$_plainLiteral\$').hasMatch(v),
          isTrue,
          reason: 'validateTripConfig returns `$v`',
        );
      }
    });

    test('GuardViolation: only the guard builds it, only from code names', () {
      for (final MapEntry(key: path, value: text) in lib.entries) {
        final n = countIn(text, RegExp(r'\bGuardViolation\((?!\$)'));
        if (path != 'lib/core/telemetry/analytics/analytics_guard.dart') {
          expect(n, 0, reason: '$path builds a GuardViolation');
        }
      }
      // The guard runs on `event.name` / `event.toParameters()` only…
      final callers = [
        for (final MapEntry(key: path, value: text) in lib.entries)
          for (final _ in RegExp(r'\bcheckAnalyticsEvent\(').allMatches(text))
            path,
      ];
      expect(callers.toSet(), {
        'lib/core/telemetry/analytics/analytics_guard.dart', // definition
        'lib/core/telemetry/analytics/app_analytics.dart',
      });
      final app = lib['lib/core/telemetry/analytics/app_analytics.dart']!;
      expect(app, contains('final name = event.name;'));
      expect(app, contains('final params = event.toParameters();'));
      // …and every event name is a code literal (sealed class).
      final events = lib['lib/core/telemetry/analytics/analytics_event.dart']!;
      final getters = RegExp(r'String get name =>\s*([^;]*);')
          .allMatches(events)
          .toList();
      expect(getters, hasLength(8));
      for (final g in getters) {
        expect(
          RegExp('^$_plainLiteral\$').hasMatch(g.group(1)!.trim()),
          isTrue,
          reason: 'event name `${g.group(1)}`',
        );
      }
      expect(events, contains('sealed class AnalyticsEvent'));
    });
  });

  group('custom keys and raw sink calls', () {
    test('setCustomKey only behind the CrashKey allowlist', () {
      final users = <String>{};
      for (final MapEntry(key: path, value: text) in lib.entries) {
        if (RegExp(r'\.setCustomKey\(').hasMatch(text)) {
          users.add(path);
        }
      }
      expect(users, {
        'lib/core/telemetry/crash/crash_reporter.dart',
        'lib/core/telemetry/crash/firebase_crash_sink.dart',
      });
      final reporter = lib['lib/core/telemetry/crash/crash_reporter.dart']!;
      expect(
        countIn(reporter, RegExp(r'_sink\.setCustomKey\(key\.wire, value\)')),
        1,
      );
      expect(countIn(reporter, RegExp(r'\.setCustomKey\(')), 1);
      // The accept check comes before the sink call in setKey.
      final setKey = reporter.substring(reporter.indexOf('void setKey('));
      expect(
        setKey.indexOf('key.accepts(value)'),
        lessThan(setKey.indexOf('_sink.setCustomKey')),
      );
    });

    test('every setKey call names a CrashKey member', () {
      final call = RegExp(r'\.setKey\(\s*([^,]*),');
      var n = 0;
      for (final MapEntry(key: path, value: text) in lib.entries) {
        for (final m in call.allMatches(text)) {
          n++;
          expect(
            RegExp(r'^CrashKey\.\w+$').hasMatch(m.group(1)!.trim()),
            isTrue,
            reason: '$path: setKey(${m.group(1)}, …)',
          );
        }
      }
      expect(n, greaterThanOrEqualTo(7));
    });

    test('the allowlist is exactly the §4.2 table', () {
      expect(CrashKey.values.map((k) => k.wire).toSet(), {
        'flavor',
        'build_mode',
        'locale',
        'trip_active',
        'trip_phase',
        'sampling_tier',
        'alarm_mode',
        'simulated',
        'engine_params_id',
        'perm_location',
        'perm_precise',
        'perm_notifications',
        'perm_full_screen_intent',
        'perm_exact_alarm',
      });
    });

    test('recordError / log reach the sink only inside CrashReporter', () {
      for (final MapEntry(key: path, value: text) in lib.entries) {
        final record = countIn(text, RegExp(r'\.recordError\('));
        final log = countIn(text, RegExp(r'_sink\.log\(|_c\.log\('));
        switch (path) {
          case 'lib/core/telemetry/crash/crash_reporter.dart':
            expect(record, 4, reason: path);
            expect(log, 1, reason: path);
          case 'lib/core/telemetry/crash/firebase_crash_sink.dart':
            expect(record, 1, reason: path);
            expect(log, 1, reason: path);
          default:
            expect(record, 0, reason: '$path calls recordError');
            expect(log, 0, reason: '$path calls the sink log');
        }
      }
    });

    test("the plugin's Flutter error helpers are never used", () {
      for (final MapEntry(key: path, value: text) in lib.entries) {
        expect(text, isNot(contains('recordFlutterFatalError')), reason: path);
        expect(
          RegExp(r'Crashlytics\.instance\.recordFlutterError').hasMatch(text),
          isFalse,
          reason: path,
        );
        expect(text, isNot(contains('information:')), reason: path);
      }
    });
  });
}
