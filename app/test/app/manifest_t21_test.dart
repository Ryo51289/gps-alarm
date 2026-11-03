// S02 (T21 D7, §13): permissions of screens 0 and 9, the background check
// receiver, and the permission flags kept out of backups.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

RegExp _permission(String name) =>
    RegExp(r'<uses-permission\s+android:name="android\.permission\.' + name);

void main() {
  final manifest = _read('android/app/src/main/AndroidManifest.xml');

  test('S02 the five T21 permissions are declared', () {
    for (final name in [
      'POST_NOTIFICATIONS',
      'USE_FULL_SCREEN_INTENT',
      'USE_EXACT_ALARM',
      'SCHEDULE_EXACT_ALARM',
      'VIBRATE',
    ]) {
      expect(_permission(name).hasMatch(manifest), isTrue, reason: name);
    }
    expect(
      manifest,
      matches(
        RegExp(
          r'android\.permission\.SCHEDULE_EXACT_ALARM"\s+'
          'android:maxSdkVersion="32"',
        ),
      ),
    );
  });

  test('S02 never background location or battery exemption requests', () {
    for (final name in [
      'ACCESS_BACKGROUND_LOCATION',
      'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      'ACCESS_NOTIFICATION_POLICY',
      'SYSTEM_ALERT_WINDOW',
    ]) {
      expect(manifest.contains(name), isFalse, reason: name);
    }
  });

  test('S02 the background check receiver is not exported', () {
    expect(
      manifest,
      matches(
        RegExp(
          r'<receiver\s+android:name="\.core\.bridge\.permission\.'
          r'BackgroundCheckReceiver"\s+android:exported="false"\s*/>',
        ),
      ),
    );
  });

  test('S02 permission and screen 0 flags excluded from backup', () {
    const res = 'android/app/src/main/res/xml';
    for (final file in ['napstop_permissions', 'napstop_onboarding']) {
      final exclude = RegExp(
        r'<exclude\s+domain="sharedpref"\s+path="'
        '$file'
        r'\.xml"\s*/>',
      );
      expect(
        exclude.allMatches(_read('$res/data_extraction_rules.xml')).length,
        2,
        reason: file,
      );
      expect(exclude.hasMatch(_read('$res/backup_rules.xml')), isTrue);
    }
    // Same names as the code that writes them.
    expect(
      _read('lib/features/onboarding/data/onboarding_progress.dart'),
      contains("kOnboardingPrefsFile = 'napstop_onboarding'"),
    );
    // Same name as the Kotlin constant.
    expect(
      _read(
        'android/app/src/main/kotlin/app/napstop/core/bridge/permission/'
        'PermissionFlags.kt',
      ),
      contains('const val PREFS = "napstop_permissions"'),
    );
  });
}
