// T23.2 RG02–RG03 (replaces T23 TS42): no Google Maps key anywhere in the
// build configuration (ADR-002); the legacy key files stay gitignored.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('RG03 .gitignore still ignores the legacy key files', () {
    final lines = _read('../.gitignore').split('\n').map((l) => l.trim());
    expect(lines, contains('secrets.properties'));
    expect(lines, contains('Secrets.xcconfig'));
  });

  test('RG02 Android manifest: no Maps key, network, no background', () {
    final m = _read('android/app/src/main/AndroidManifest.xml');
    expect(m, isNot(contains('com.google.android.geo.API_KEY')));
    expect(m, isNot(contains('mapsApiKey')));
    expect(m, contains('android.permission.INTERNET'));
    expect(m, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(m, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
  });

  test('RG02 Gradle: no Maps placeholder, no secrets file', () {
    final g = _read('android/app/build.gradle.kts');
    expect(g, isNot(contains('manifestPlaceholders["mapsApiKey"]')));
    expect(g, isNot(contains('napSecret')));
    expect(g, isNot(contains('secrets.properties')));
    expect(g, contains('implementation(project(":core-trip"))'));
  });

  test('RG02 iOS: no GMSApiKey, no Secrets.xcconfig include', () {
    expect(_read('ios/Runner/Info.plist'), isNot(contains('GMSApiKey')));
    for (final f in [
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
    ]) {
      final text = _read(f);
      expect(text, isNot(contains('Secrets.xcconfig')), reason: f);
      expect(text, contains('#include "Generated.xcconfig"'), reason: f);
    }
    // T01.2: the diagnostics include of Release stays.
    expect(
      _read('ios/Flutter/Release.xcconfig'),
      contains('#include? "Diag.xcconfig"'),
    );
  });

  test('RG02 the key example files are gone', () {
    expect(File('android/secrets.properties.example').existsSync(), isFalse);
    expect(File('ios/Flutter/Secrets.xcconfig.example').existsSync(), isFalse);
  });

  test('no Google API key (AIza…) in the tracked config files', () {
    final key = RegExp('AIza[0-9A-Za-z_-]{20,}');
    for (final f in [
      '../.gitignore',
      'android/app/src/main/AndroidManifest.xml',
      'android/app/build.gradle.kts',
      'ios/Runner/Info.plist',
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
    ]) {
      expect(key.hasMatch(_read(f)), isFalse, reason: f);
    }
  });
}
