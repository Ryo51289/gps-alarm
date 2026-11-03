// Tester T21 (§6.5, CQ1): the first-run decision at the real 500 ms limit
// (fake time), and every odd value the store can hold. A wrong "/home" on the
// first launch means screen 0 is skipped and permissions may stay missing.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';

import '../../../helpers/fake_key_value_store.dart';

class _DelayedStore extends FakeKeyValueStore {
  new(this.delay, int? value) : super({kOnboardingKey: ?value});

  final Duration delay;

  @override
  Future<int?> getInt(String key) =>
      Future<void>.delayed(delay).then((_) => super.getInt(key));
}

class _SyncThrowStore extends FakeKeyValueStore {
  @override
  Future<int?> getInt(String key) => throw StateError('disk');
}

Future<String> _decide(KeyValueStore store) => startupLocation(store);

void main() {
  for (final (ms, value, expected) in [
    (0, 1, AppRoutes.home),
    (499, 1, AppRoutes.home),
    (501, 1, AppRoutes.onboarding), // CQ1: too slow = not completed
    (2000, 1, AppRoutes.onboarding),
    (10, null, AppRoutes.onboarding),
    (499, null, AppRoutes.onboarding),
  ]) {
    testWidgets('flag $value after $ms ms -> $expected (default 500 ms)', (
      tester,
    ) async {
      String? route;
      unawaited(
        _decide(_DelayedStore(Duration(milliseconds: ms), value))
            .then((r) => route = r),
      );
      // Nothing is decided before the read or the limit.
      if (ms > 0) {
        await tester.pump(Duration(milliseconds: (ms < 500 ? ms : 500) - 1));
        expect(route, isNull);
      }
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(route, expected);
    });
  }

  test('stored values: only >= the current version counts as done', () async {
    for (final (stored, expected) in [
      (null, AppRoutes.onboarding),
      (-1, AppRoutes.onboarding),
      (0, AppRoutes.onboarding),
      (kOnboardingVersion, AppRoutes.home),
      (kOnboardingVersion + 1, AppRoutes.home), // newer build, then downgrade
    ]) {
      final store = FakeKeyValueStore({kOnboardingKey: ?stored});
      expect(await _decide(store), expected, reason: '$stored');
    }
  });

  test('a value of the wrong type or a read error shows screen 0', () async {
    expect(
      await _decide(FakeKeyValueStore({kOnboardingKey: '1'})),
      AppRoutes.onboarding,
    );
    expect(
      await _decide(FakeKeyValueStore()..error = StateError('io')),
      AppRoutes.onboarding,
    );
    expect(await _decide(_SyncThrowStore()), AppRoutes.onboarding);
  });

  test('after "Tiếp tục" the next launch goes home; a failed write shows '
      'screen 0 again', () async {
    final store = FakeKeyValueStore();
    expect(await _decide(store), AppRoutes.onboarding);
    await markOnboardingCompleted(store);
    expect(store.values[kOnboardingKey], kOnboardingVersion);
    expect(await _decide(store), AppRoutes.home);
    // Idempotent.
    await markOnboardingCompleted(store);
    expect(await _decide(store), AppRoutes.home);

    final broken = FakeKeyValueStore()..error = StateError('full');
    await markOnboardingCompleted(broken);
    broken.error = null;
    expect(await _decide(broken), AppRoutes.onboarding);
  });

  test('the flag key and file name match the backup rules', () {
    expect(kOnboardingKey, 'onboarding.completedVersion');
    expect(kOnboardingPrefsFile, 'napstop_onboarding');
  });
}
