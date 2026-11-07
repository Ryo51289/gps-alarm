// T23 TS40: no logging anywhere in screen 2 (queries, names and coordinates
// are location data) and layer boundaries. T23.2 RG01: nothing of Google
// Maps Platform (SDK, Places, key) comes back (ADR-002).
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
  final files = [
    ..._dartFiles('lib/features/destination'),
    ..._dartFiles('lib/core/text'),
  ];

  test('TS40 files exist', () {
    expect(files.length, greaterThanOrEqualTo(20));
  });

  test('TS40 no logging', () {
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

  test('TS40 domain is pure Dart', () {
    for (final f in _dartFiles('lib/features/destination/domain')) {
      final text = f.readAsStringSync();
      expect(text.contains('package:flutter'), isFalse, reason: _norm(f));
      expect(text.contains('google_maps_flutter'), isFalse, reason: _norm(f));
    }
  });

  test('TS40 no package:http in lib (Places removed, T23.2)', () {
    final users = [
      for (final f in _dartFiles('lib'))
        if (f.readAsStringSync().contains('package:http/')) _norm(f),
    ];
    expect(users, isEmpty);
  });

  test('RG01 no Google Maps SDK, Places or Maps key left (T23.2)', () {
    const forbidden = [
      'google_maps_flutter',
      'GoogleMaps',
      'GMSServices',
      'GMSApiKey',
      'places.googleapis.com',
      'MapsConfig',
      'mapsConfig',
      'geo.API_KEY',
      'MAPS_API_KEY',
      'mapsApiKey',
      'X-Goog-Api-Key',
    ];
    // Tracked files plus new files not yet committed; gitignored ones are
    // skipped (review T23.2: an old Secrets.xcconfig left on a dev machine
    // must not turn this red). Generated plugin registrants are gitignored
    // and rebuilt by `flutter pub get`.
    final listed = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '-z',
      '--',
      'lib',
      'android/app/src/main',
      'android/app/build.gradle.kts',
      'ios/Runner',
      'ios/Flutter',
      'ios/scripts',
      'pigeons',
      'pubspec.yaml',
    ]);
    expect(listed.exitCode, 0, reason: '${listed.stderr}');
    final files = [
      for (final path in (listed.stdout as String).split('\x00'))
        if (path.isNotEmpty && _textExtensions.any(path.endsWith)) File(path),
    ].where((f) => f.existsSync()).toList();
    final names = files.map(_norm).toSet();
    expect(files.length, greaterThan(100));
    expect(names, contains('android/app/build.gradle.kts'));
    expect(names, contains('pubspec.yaml'));
    expect(names, contains('ios/Runner/Info.plist'));
    final hits = <String>[];
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final word in forbidden) {
        if (text.contains(word)) {
          hits.add('$word in ${_norm(f)}');
        }
      }
    }
    expect(hits, isEmpty);
  });
}

/// Text files scanned by RG01 (binary assets such as PNG/TTF are skipped).
const _textExtensions = [
  '.dart',
  '.kt',
  '.kts',
  '.java',
  '.xml',
  '.swift',
  '.h',
  '.m',
  '.plist',
  '.xcconfig',
  '.sh',
  '.yaml',
  '.json',
  '.arb',
  '.properties',
];
