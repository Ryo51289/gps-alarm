/// First run (T21 §6.5, D10): screen 0 opens until its main button was
/// pressed once for the current [kOnboardingVersion].
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/db/connection.dart';
import 'package:napstop/core/storage/file_key_value_store.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

/// Bump when screen 0 gets a new item everybody must see.
const int kOnboardingVersion = 1;
const String kOnboardingKey = 'onboarding.completedVersion';

/// True when the stored version is at least [kOnboardingVersion]. Any error
/// reads as false (screen 0 again: safe for permissions).
Future<bool> isOnboardingCompleted(KeyValueStore store) async {
  try {
    final v = await store.getInt(kOnboardingKey);
    return v != null && v >= kOnboardingVersion;
  } on Object {
    return false;
  }
}

/// Writes [kOnboardingVersion]. Errors are swallowed: screen 0 shows again
/// on the next launch.
Future<void> markOnboardingCompleted(KeyValueStore store) async {
  try {
    await store.setInt(kOnboardingKey, kOnboardingVersion);
  } on Object {
    // Accepted (§6.5).
  }
}

/// Android file of the screen 0 flags: `shared_prefs/napstop_onboarding.xml`,
/// excluded from Auto Backup and device transfer (res/xml backup rules):
/// runtime permissions do not move to a new phone, so screen 0 must show
/// there again (T21 review #3). Same name in the backup rules.
const String kOnboardingPrefsFile = 'napstop_onboarding';

/// Options of the onboarding store: on Android the legacy SharedPreferences
/// backend in [kOnboardingPrefsFile]; elsewhere the default store. iOS does
/// not use SharedPreferences at all ([createOnboardingStore], T17.1 D11).
SharedPreferencesOptions onboardingStoreOptions(TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? const SharedPreferencesAsyncAndroidOptions(
        backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
        originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
          fileName: kOnboardingPrefsFile,
        ),
      )
    : const SharedPreferencesOptions();

/// iOS file of the screen 0 flags, in the database directory
/// (`<app support>/napstop_db/`) that native code excludes from iCloud backup
/// (T17.1 D10, D11): NSUserDefaults cannot be excluded per key.
const String kOnboardingFileName = 'onboarding.json';

/// The store of the screen 0 flags (not the app preferences store). iOS: a
/// JSON file in `napstop_db/` (T17.1 Q1 = B; nothing to migrate, iOS was not
/// released); Android and others: SharedPreferences ([onboardingStoreOptions]).
/// [platform] and [supportDirectory] are for tests.
KeyValueStore createOnboardingStore({
  TargetPlatform? platform,
  Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.iOS) {
    return FileKeyValueStore(() async {
      final dir = await appDatabaseDirectory(
        supportDirectory: supportDirectory,
      );
      return File(p.join(dir.path, kOnboardingFileName));
    });
  }
  return SharedPreferencesKeyValueStore(null, onboardingStoreOptions(target));
}

/// [createOnboardingStore] for screen 0. Widget tests override it.
final onboardingStoreProvider = Provider<KeyValueStore>(
  (ref) => createOnboardingStore(),
);

/// Longest wait for the flag before the first frame (R10).
const Duration kOnboardingReadTimeout = Duration(milliseconds: 500);

/// The initial route: /home when screen 0 was completed, else /onboarding.
/// A read slower than [timeout] counts as not completed (T21 CQ1): the
/// slowest read is the first launch after install, exactly when screen 0
/// must show; showing it once too often is harmless.
Future<String> startupLocation(
  KeyValueStore store, {
  Duration timeout = kOnboardingReadTimeout,
}) async {
  final done = await isOnboardingCompleted(store)
      .timeout(timeout, onTimeout: () => false);
  return done ? AppRoutes.home : AppRoutes.onboarding;
}

/// Initial route of the router; main() overrides it. Default /home, so
/// widget tests that pump the app are unchanged.
final startupLocationProvider = Provider<String>((ref) => AppRoutes.home);
