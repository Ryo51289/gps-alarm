// U22: first-run flag (T21 §6.5).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import '../../../helpers/fake_key_value_store.dart';

void main() {
  test('U22 isOnboardingCompleted', () async {
    expect(await isOnboardingCompleted(FakeKeyValueStore()), isFalse);
    expect(
      await isOnboardingCompleted(FakeKeyValueStore({kOnboardingKey: 1})),
      isTrue,
    );
    expect(
      await isOnboardingCompleted(FakeKeyValueStore({kOnboardingKey: 2})),
      isTrue,
    );
    expect(
      await isOnboardingCompleted(FakeKeyValueStore({kOnboardingKey: 0})),
      isFalse,
    );
    // Wrong type: getInt fails.
    expect(
      await isOnboardingCompleted(FakeKeyValueStore({kOnboardingKey: 'x'})),
      isFalse,
    );
    final broken = FakeKeyValueStore()..error = StateError('io');
    expect(await isOnboardingCompleted(broken), isFalse);
  });

  test('U22 markOnboardingCompleted writes 1 and never throws', () async {
    final store = FakeKeyValueStore();
    await markOnboardingCompleted(store);
    expect(store.values[kOnboardingKey], kOnboardingVersion);
    expect(kOnboardingVersion, 1);
    expect(kOnboardingKey, 'onboarding.completedVersion');

    final broken = FakeKeyValueStore()..error = StateError('io');
    await expectLater(markOnboardingCompleted(broken), completes);
  });

  test('review #3: Android keeps the flags in napstop_onboarding', () {
    final android = onboardingStoreOptions(TargetPlatform.android);
    expect(android, isA<SharedPreferencesAsyncAndroidOptions>());
    final options = android as SharedPreferencesAsyncAndroidOptions;
    expect(
      options.backend,
      SharedPreferencesAndroidBackendLibrary.SharedPreferences,
    );
    expect(
      options.originalSharedPreferencesOptions?.fileName,
      kOnboardingPrefsFile,
    );
    expect(kOnboardingPrefsFile, 'napstop_onboarding');
    expect(
      onboardingStoreOptions(TargetPlatform.iOS),
      isNot(isA<SharedPreferencesAsyncAndroidOptions>()),
    );
  });

  group('startupLocation (T21 CQ1)', () {
    test(
      'completed: /home; not completed or read error: /onboarding',
      () async {
        expect(
          await startupLocation(FakeKeyValueStore({kOnboardingKey: 1})),
          AppRoutes.home,
        );
        expect(
          await startupLocation(FakeKeyValueStore()),
          AppRoutes.onboarding,
        );
        expect(
          await startupLocation(FakeKeyValueStore()..error = StateError('io')),
          AppRoutes.onboarding,
        );
      },
    );

    test('the wait is 500 ms', () {
      expect(kOnboardingReadTimeout, const Duration(milliseconds: 500));
    });

    test('a read slower than the timeout shows screen 0', () async {
      // Completed flag, but it arrives too late.
      final store = _SlowStore(const Duration(milliseconds: 300), 1);
      expect(
        await startupLocation(store, timeout: const Duration(milliseconds: 20)),
        AppRoutes.onboarding,
      );
    });

    test('a completed flag read in time goes home', () async {
      final store = _SlowStore(const Duration(milliseconds: 10), 1);
      expect(
        await startupLocation(store, timeout: const Duration(seconds: 2)),
        AppRoutes.home,
      );
    });

    test('a read that never answers shows screen 0', () async {
      expect(
        await startupLocation(
          _HungStore(),
          timeout: const Duration(milliseconds: 20),
        ),
        AppRoutes.onboarding,
      );
    });
  });
}

/// Answers getInt with [value] after [delay].
class _SlowStore extends FakeKeyValueStore {
  new(this.delay, this.value);

  final Duration delay;
  final int value;

  @override
  Future<int?> getInt(String key) => Future<int?>.delayed(delay, () => value);
}

/// Never answers.
class _HungStore implements KeyValueStore {
  @override
  Future<int?> getInt(String key) => Completer<int?>().future;

  @override
  Future<String?> getString(String key) => Completer<String?>().future;

  @override
  Future<void> setInt(String key, int value) => Completer<void>().future;

  @override
  Future<void> setString(String key, String value) => Completer<void>().future;
}
