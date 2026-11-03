// T23 TS42: Maps/Places keys stay out of git; a clone without a key builds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('TS42 .gitignore ignores the key files', () {
    final lines = _read('../.gitignore').split('\n').map((l) => l.trim());
    expect(lines, contains('secrets.properties'));
    expect(lines, contains('Secrets.xcconfig'));
  });

  test('TS42 Android manifest: key placeholder, network, no background', () {
    final m = _read('android/app/src/main/AndroidManifest.xml');
    expect(m, contains('android:name="com.google.android.geo.API_KEY"'));
    expect(m, contains(r'android:value="${mapsApiKey}"'));
    expect(m, contains('android.permission.INTERNET'));
    expect(m, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(m, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
  });

  test('TS42 Gradle: per-flavor placeholder with a default', () {
    final g = _read('android/app/build.gradle.kts');
    expect(
      g,
      contains(
        'manifestPlaceholders["mapsApiKey"] = napSecret("MAPS_API_KEY_DEV")',
      ),
    );
    expect(
      g,
      contains(
        'manifestPlaceholders["mapsApiKey"] = napSecret("MAPS_API_KEY_PROD")',
      ),
    );
    expect(g, contains('"DEFAULT_API_KEY"'));
    expect(g, contains('secrets.properties'));
    expect(g, contains('implementation(project(":core-trip"))'));
  });

  test('TS42 iOS: GMSApiKey from Secrets.xcconfig', () {
    expect(
      _read('ios/Runner/Info.plist'),
      matches(
        RegExp(r'<key>GMSApiKey</key>\s*<string>\$\(MAPS_API_KEY\)</string>'),
      ),
    );
    for (final f in [
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
    ]) {
      expect(_read(f), contains('#include? "Secrets.xcconfig"'), reason: f);
    }
  });

  test('TS42 example files hold no key', () {
    expect(
      _read('android/secrets.properties.example'),
      contains('MAPS_API_KEY_DEV=DEFAULT_API_KEY'),
    );
    expect(
      _read('ios/Flutter/Secrets.xcconfig.example'),
      contains('MAPS_API_KEY ='),
    );
  });

  test('TS42 no Google API key (AIza…) in the tracked config files', () {
    final key = RegExp('AIza[0-9A-Za-z_-]{20,}');
    for (final f in [
      '../.gitignore',
      'android/app/src/main/AndroidManifest.xml',
      'android/app/build.gradle.kts',
      'android/secrets.properties.example',
      'ios/Runner/Info.plist',
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
      'ios/Flutter/Secrets.xcconfig.example',
      'lib/features/destination/data/destination_providers.dart',
      'lib/features/destination/data/places/places_client.dart',
    ]) {
      expect(key.hasMatch(_read(f)), isFalse, reason: f);
    }
  });
}
