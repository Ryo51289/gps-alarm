// S02: the database stays out of Android backup and device transfer; the
// default deep link handler is off (T22 D5, D12).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const res = 'android/app/src/main/res/xml';
  final exclude = RegExp(r'<exclude\s+domain="file"\s+path="napstop_db/"\s*/>');

  test('S02 manifest points at both rule files', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      matches(
        RegExp(
          r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+'
          'android:value="false"',
        ),
      ),
    );
  });

  test('S02 data_extraction_rules: cloud backup and device transfer', () {
    final xml = _read('$res/data_extraction_rules.xml');
    final cloud = RegExp(
      '<cloud-backup>(.*?)</cloud-backup>',
      dotAll: true,
    ).firstMatch(xml);
    final transfer = RegExp(
      '<device-transfer>(.*?)</device-transfer>',
      dotAll: true,
    ).firstMatch(xml);
    expect(cloud, isNotNull);
    expect(transfer, isNotNull);
    expect(exclude.hasMatch(cloud!.group(1)!), isTrue);
    expect(exclude.hasMatch(transfer!.group(1)!), isTrue);
  });

  test('S02 backup_rules: full backup content (API <= 30)', () {
    final xml = _read('$res/backup_rules.xml');
    final body = RegExp(
      '<full-backup-content>(.*?)</full-backup-content>',
      dotAll: true,
    ).firstMatch(xml);
    expect(body, isNotNull);
    expect(exclude.hasMatch(body!.group(1)!), isTrue);
  });

  test('S02 connection.dart opens the database in napstop_db', () {
    final source = _read('lib/core/db/connection.dart');
    expect(source, contains("kDatabaseDirName = 'napstop_db'"));
    expect(source, contains('p.join(support.path, kDatabaseDirName)'));
    expect(source, contains('databaseDirectory: appDatabaseDirectory'));
  });

  test('iOS Info.plist turns Flutter deep linking off', () {
    expect(
      _read('ios/Runner/Info.plist'),
      matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')),
    );
  });
}
