// T29 TC22–TC24: static scans of lib/ for the telemetry privacy rules.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    .map((l) => l.replaceFirst(RegExp('//.*'), ''))
    .join('\n');

void main() {
  final lib = _dartFiles('lib')
      .where((f) => !_norm(f).startsWith('lib/l10n/gen/'))
      .toList();

  test('TC22 only the adapters import package:firebase_*', () {
    const allowed = {
      'lib/core/telemetry/analytics/firebase_analytics_sink.dart':
          'firebase_analytics',
      'lib/core/telemetry/crash/firebase_crash_sink.dart':
          'firebase_crashlytics',
      'lib/core/telemetry/remote_config/firebase_remote_config_client.dart':
          'firebase_remote_config',
      'lib/core/telemetry/telemetry_bootstrap.dart': 'firebase_core',
    };
    final import = RegExp(r'''import\s+'package:(firebase_\w+)/''');
    final seen = <String>{};
    for (final f in lib) {
      final path = _norm(f);
      for (final m in import.allMatches(f.readAsStringSync())) {
        final pkg = m.group(1)!;
        if (path.startsWith('lib/app/firebase/')) {
          expect(pkg, 'firebase_core', reason: path);
          continue;
        }
        expect(allowed[path], pkg, reason: '$pkg imported by $path');
        seen.add(path);
      }
    }
    expect(seen, allowed.keys.toSet());
  });

  test('TC23 no user id, user property, route observer or print', () {
    final forbidden = <String, RegExp>{
      'FirebaseAnalyticsObserver': RegExp('FirebaseAnalyticsObserver'),
      'setUserId(': RegExp(r'\bsetUserId\('),
      'setUserIdentifier(': RegExp(r'\bsetUserIdentifier\('),
      'setUserProperty(': RegExp(r'\bsetUserProperty\('),
      'setDefaultEventParameters(': RegExp(r'\bsetDefaultEventParameters\('),
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
    };
    for (final f in lib) {
      final text = _code(f);
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('TC24 no coordinate identifiers in telemetry and logging', () {
    final coordinate = RegExp(
      r'\b(lat|lng|latitude|longitude)\b',
      caseSensitive: false,
    );
    final files = [
      ..._dartFiles('lib/core/telemetry'),
      ..._dartFiles('lib/core/logging'),
    ];
    expect(files.length, greaterThanOrEqualTo(25));
    for (final f in files) {
      final path = _norm(f);
      // The redactor spells the key names in its patterns, by design.
      if (path.endsWith('redaction/redactor.dart')) {
        continue;
      }
      expect(coordinate.hasMatch(f.readAsStringSync()), isFalse, reason: path);
    }
  });

  test('dart:developer only in the logger', () {
    for (final f in lib) {
      final path = _norm(f);
      if (path == 'lib/core/logging/app_log.dart') {
        continue;
      }
      expect(
        f.readAsStringSync().contains('dart:developer'),
        isFalse,
        reason: path,
      );
    }
  });

  test('no realtime Remote Config, no analytics observer in the router', () {
    for (final f in lib) {
      expect(_code(f).contains('onConfigUpdated'), isFalse, reason: _norm(f));
    }
  });
}
