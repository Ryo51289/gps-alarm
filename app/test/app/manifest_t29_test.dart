// T29 §7 + CD1 (TC26, source + merged part): Firebase collection off by
// default, no advertising id and no Privacy Sandbox ad permissions.
//
// The merged-manifest checks need a prior `flutter build apk --debug`
// (dev) / `--flavor prod`; without that build output they are skipped (the
// CI `dart` job does not build). The tester runs them after a build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _removed = [
  'com.google.android.gms.permission.AD_ID',
  'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
  'android.permission.ACCESS_ADSERVICES_AD_ID',
];

const _metaOff = [
  'firebase_analytics_collection_enabled',
  'firebase_crashlytics_collection_enabled',
  'google_analytics_adid_collection_enabled',
  'google_analytics_default_allow_ad_personalization_signals',
];

/// `<meta-data android:name="[name]" android:value="false"`.
RegExp _metaFalse(String name) => RegExp(
  [
    r'<meta-data\s+android:name="',
    RegExp.escape(name),
    r'"\s+android:value="false"',
  ].join(),
);

/// `<uses-permission android:name="[name]" tools:node="remove"/>`.
RegExp _removedPermission(String name) => RegExp(
  [
    r'<uses-permission\s+android:name="',
    RegExp.escape(name),
    r'"\s+tools:node="remove"\s*/>',
  ].join(),
);

/// Final merged manifests of the debug builds (AGP output paths).
const _merged = {
  'devDebug':
      'build/app/intermediates/merged_manifests/devDebug/'
      'processDevDebugManifest/AndroidManifest.xml',
  'prodDebug':
      'build/app/intermediates/merged_manifests/prodDebug/'
      'processProdDebugManifest/AndroidManifest.xml',
};

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('source: tools namespace, three permissions removed', () {
    expect(
      manifest,
      contains('xmlns:tools="http://schemas.android.com/tools"'),
    );
    for (final p in _removed) {
      expect(_removedPermission(p).hasMatch(manifest), isTrue, reason: p);
    }
  });

  test('source: Analytics and Crashlytics start off', () {
    for (final name in _metaOff) {
      expect(_metaFalse(name).hasMatch(manifest), isTrue, reason: name);
    }
  });

  for (final MapEntry(key: variant, value: path) in _merged.entries) {
    final file = File(path);
    test(
      'merged $variant: no ad permissions, collection off, no new location',
      () {
        final merged = file.readAsStringSync();
        for (final p in _removed) {
          expect(merged, isNot(contains('"$p"')), reason: p);
        }
        expect(merged, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
        for (final name in _metaOff) {
          expect(_metaFalse(name).hasMatch(merged), isTrue, reason: name);
        }
      },
      skip: file.existsSync() ? false : 'no $variant build output',
    );
  }
}
