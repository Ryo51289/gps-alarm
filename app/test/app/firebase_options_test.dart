// T29.2 FU01, FU02: Firebase options per platform; the hand-written iOS
// options match ios/Runner/GoogleService-Info.plist and the Runner bundle id.
// Failure messages name the key, never its value (the API key is public but
// is kept out of logs anyway).
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/firebase/firebase_options.dart';
import 'package:napstop/app/firebase/firebase_options_ios.dart';
import 'package:napstop/app/flavor.dart';

/// `<key>K</key><string>V</string>` pairs of a flat XML plist.
Map<String, String> plistStrings(String xml) => {
  for (final m in RegExp(
    r'<key>([^<]+)</key>\s*<string>([^<]*)</string>',
  ).allMatches(xml))
    m.group(1)!: m.group(2)!,
};

void main() {
  group('FU01 firebaseOptionsFor', () {
    test('iOS: the same options for dev and prod', () {
      for (final flavor in AppFlavor.values) {
        expect(
          identical(
            firebaseOptionsFor(flavor, platform: TargetPlatform.iOS),
            iosFirebaseOptions,
          ),
          isTrue,
          reason: flavor.name,
        );
      }
    });

    test('every other platform and the host default: null', () {
      for (final flavor in AppFlavor.values) {
        for (final p in TargetPlatform.values) {
          if (p == TargetPlatform.iOS) {
            continue;
          }
          expect(
            firebaseOptionsFor(flavor, platform: p),
            isNull,
            reason: '$flavor $p',
          );
        }
        // flutter test runs with defaultTargetPlatform == android.
        expect(firebaseOptionsFor(flavor), isNull, reason: flavor.name);
      }
    });

    test('still fits bootstrapTelemetry(optionsFor:)', () {
      const FirebaseOptionsForFlavor f = firebaseOptionsFor;
      expect(f(AppFlavor.dev), isNull);
    });
  });

  group('FU02 options == GoogleService-Info.plist', () {
    final plist = plistStrings(
      File('ios/Runner/GoogleService-Info.plist').readAsStringSync(),
    );
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();

    test('each field equals its plist key', () {
      final fields = <String, String?>{
        'API_KEY': iosFirebaseOptions.apiKey,
        'GOOGLE_APP_ID': iosFirebaseOptions.appId,
        'GCM_SENDER_ID': iosFirebaseOptions.messagingSenderId,
        'PROJECT_ID': iosFirebaseOptions.projectId,
        'STORAGE_BUCKET': iosFirebaseOptions.storageBucket,
        'BUNDLE_ID': iosFirebaseOptions.iosBundleId,
      };
      for (final MapEntry(:key, :value) in fields.entries) {
        expect(plist.containsKey(key), isTrue, reason: '$key in the plist');
        expect(value != null && value.isNotEmpty, isTrue, reason: key);
        expect(plist[key] == value, isTrue, reason: '$key differs');
      }
    });

    test('an iOS app of the expected project and bundle', () {
      expect(
        RegExp(r'^1:\d+:ios:[0-9a-f]+$').hasMatch(iosFirebaseOptions.appId),
        isTrue,
      );
      expect(iosFirebaseOptions.iosBundleId, 'app.napstop');
      expect(iosFirebaseOptions.projectId, 'napstop-dev-10636');
    });

    test('BUNDLE_ID == PRODUCT_BUNDLE_IDENTIFIER of Runner (3 configs)', () {
      final ids = RegExp('PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(pbxproj)
          .map((m) => m.group(1)!.trim())
          .where((id) => !id.endsWith('.RunnerTests'))
          .toList();
      expect(ids, hasLength(3), reason: 'Debug, Release, Profile');
      expect(ids.toSet(), {plist['BUNDLE_ID']});
    });

    test('the plist is in the Runner Resources phase exactly once', () {
      expect(
        RegExp(r'/\* GoogleService-Info\.plist in Resources \*/,')
            .allMatches(pbxproj),
        hasLength(1),
      );
      expect(
        RegExp(
          r'/\* GoogleService-Info\.plist in Resources \*/ = \{isa = PBXBuildFile',
        ).allMatches(pbxproj),
        hasLength(1),
      );
    });
  });
}

/// The type `bootstrapTelemetry` expects for `optionsFor`.
typedef FirebaseOptionsForFlavor = FirebaseOptions? Function(AppFlavor);
