// T29 TC13–TC15: consent rules (Q2 = opt-in), store, controller.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_controller.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';

import '../../../helpers/fake_key_value_store.dart';
import '../telemetry_fakes.dart';

/// The rules of T29 §7, written out independently of the implementation.
EffectiveCollection _expected(
  ConsentChoice choice,
  int version,
  AppFlavor flavor, {
  required bool debug,
  required TelemetryOverride override,
}) {
  if (override == TelemetryOverride.off) {
    return EffectiveCollection.none;
  }
  if (override == TelemetryOverride.on && flavor == AppFlavor.dev) {
    return const EffectiveCollection(crash: true, analytics: true);
  }
  if (debug) {
    return EffectiveCollection.none;
  }
  final on = choice == ConsentChoice.granted && version >= 1;
  return EffectiveCollection(crash: on, analytics: on);
}

void main() {
  test('Q2 = opt-in', () {
    expect(kCollectWhenUnknown, isFalse);
    expect(kConsentTextVersion, 1);
    expect(TelemetryOverride.parse('on'), TelemetryOverride.on);
    expect(TelemetryOverride.parse('off'), TelemetryOverride.off);
    expect(TelemetryOverride.parse(null), TelemetryOverride.auto);
    expect(TelemetryOverride.parse('ON'), TelemetryOverride.auto);
    expect(TelemetryOverride.fromEnvironment, TelemetryOverride.auto);
  });

  test('TC13 matrix', () {
    for (final choice in ConsentChoice.values) {
      for (final version in [0, 1]) {
        for (final flavor in AppFlavor.values) {
          for (final debug in [true, false]) {
            for (final override in TelemetryOverride.values) {
              final c = TelemetryConsent(
                crash: choice,
                analytics: choice,
                version: version,
              );
              expect(
                resolveCollection(
                  consent: c,
                  flavor: flavor,
                  isDebugBuild: debug,
                  override: override,
                ),
                _expected(
                  choice,
                  version,
                  flavor,
                  debug: debug,
                  override: override,
                ),
                reason: '$c $flavor debug=$debug $override',
              );
              expect(
                needsConsentPrompt(c),
                choice == ConsentChoice.unknown || version < 1,
              );
            }
          }
        }
      }
    }
  });

  test('TC13 kinds are independent', () {
    final r = resolveCollection(
      consent: const TelemetryConsent(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.denied,
        version: 1,
      ),
      flavor: AppFlavor.prod,
      isDebugBuild: false,
      override: TelemetryOverride.auto,
    );
    expect(r, const EffectiveCollection(crash: true, analytics: false));
    expect(
      needsConsentPrompt(
        const TelemetryConsent(
          crash: ConsentChoice.granted,
          analytics: ConsentChoice.unknown,
          version: 1,
        ),
      ),
      isTrue,
    );
  });

  group('TC14 store', () {
    test('round trip', () async {
      final kv = FakeKeyValueStore();
      final store = TelemetryConsentStore(kv);
      expect(await store.read(), TelemetryConsent.initial);
      const c = TelemetryConsent(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.denied,
        version: 1,
      );
      await store.write(c);
      expect(await store.read(), c);
      // R3-2: one key, one atomic setString.
      expect(kv.values, {
        'telemetry.consent': 'crash=granted;analytics=denied;version=1',
      });
    });

    test('R3-2 the single key wins over legacy keys (migration)', () async {
      final kv = FakeKeyValueStore({
        'telemetry.crash': 'granted',
        'telemetry.analytics': 'granted',
        'telemetry.consent_version': 1,
      });
      final store = TelemetryConsentStore(kv);
      expect(
        (await store.read()).crash,
        ConsentChoice.granted,
        reason: 'legacy',
      );
      const declined = TelemetryConsent(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
        version: 1,
      );
      await store.write(declined);
      expect(await store.read(), declined, reason: 'stale legacy ignored');
    });

    test(
      'R3-2 a malformed single key → initial, never the legacy keys',
      () async {
        final kv = FakeKeyValueStore({
          'telemetry.consent': 'crash=granted;analytics=gran',
          'telemetry.crash': 'granted',
          'telemetry.analytics': 'granted',
          'telemetry.consent_version': 1,
        });
        expect(
          await TelemetryConsentStore(kv).read(),
          TelemetryConsent.initial,
        );
        for (final c in [
          TelemetryConsent.initial,
          const TelemetryConsent(
            crash: ConsentChoice.unknown,
            analytics: ConsentChoice.granted,
            version: 1,
          ),
        ]) {
          expect(
            TelemetryConsentStore.decode(TelemetryConsentStore.encode(c)),
            c,
          );
        }
      },
    );

    test('unknown values read as unknown; errors as initial', () async {
      final kv = FakeKeyValueStore({
        'telemetry.crash': 'yes',
        'telemetry.analytics': 'granted',
        'telemetry.consent_version': 1,
      });
      final store = TelemetryConsentStore(kv);
      expect(
        await store.read(),
        const TelemetryConsent(
          crash: ConsentChoice.unknown,
          analytics: ConsentChoice.granted,
          version: 1,
        ),
      );
      kv.values['telemetry.consent_version'] = 'one';
      expect(await store.read(), TelemetryConsent.initial);
      kv.error = StateError('disk');
      expect(await store.read(), TelemetryConsent.initial);
    });
  });

  group('TC15 controller', () {
    late RecordingCrashSink crash;
    late RecordingAnalyticsSink analytics;
    late FakeKeyValueStore kv;

    TelemetryConsentController controller({
      TelemetryConsent consent = TelemetryConsent.initial,
      bool debug = false,
      TelemetryOverride override = TelemetryOverride.auto,
    }) => TelemetryConsentController(
      store: TelemetryConsentStore(kv),
      consent: consent,
      crashSink: crash,
      analyticsSink: analytics,
      flavor: AppFlavor.prod,
      isDebugBuild: debug,
      override: override,
    );

    setUp(() {
      crash = RecordingCrashSink();
      analytics = RecordingAnalyticsSink();
      kv = FakeKeyValueStore();
    });

    test('grant then revoke', () async {
      final c = controller();
      expect(c.needsPrompt, isTrue);
      expect(c.effective, EffectiveCollection.none);
      var notified = 0;
      c.addListener(() => notified++);

      await c.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      expect(crash.calls, ['setCollectionEnabled(true)', 'sendUnsentReports']);
      expect(analytics.calls, ['setCollectionEnabled(true)']);
      expect(
        c.effective,
        const EffectiveCollection(crash: true, analytics: true),
      );
      expect(c.needsPrompt, isFalse);
      expect(
        kv.values['telemetry.consent'],
        'crash=granted;analytics=granted;version=1',
      );

      crash.calls.clear();
      analytics.calls.clear();
      await c.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      expect(crash.calls, [
        'setCollectionEnabled(false)',
        'deleteUnsentReports',
      ]);
      expect(analytics.calls, ['setCollectionEnabled(false)', 'resetData']);
      expect(
        kv.values['telemetry.consent'],
        'crash=denied;analytics=denied;version=1',
      );
      expect(notified, 2);
    });

    test('one kind at a time; no change, no SDK call', () async {
      final c = controller();
      await c.update(analytics: ConsentChoice.granted);
      expect(crash.calls, isEmpty);
      expect(analytics.calls, ['setCollectionEnabled(true)']);
      await c.update(analytics: ConsentChoice.granted);
      expect(analytics.calls, hasLength(1));
      expect(c.current.crash, ConsentChoice.unknown);
    });

    test('debug build: answers are stored, nothing is enabled', () async {
      final c = controller(debug: true);
      await c.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      expect(crash.calls, isEmpty);
      expect(analytics.calls, isEmpty);
      expect(kv.values['telemetry.consent'], startsWith('crash=granted;'));
    });

    test('a failing store keeps the answer for the session', () async {
      kv.error = StateError('disk');
      final c = controller();
      await c.update(crash: ConsentChoice.granted);
      expect(c.current.crash, ConsentChoice.granted);
      expect(c.effective.crash, isTrue);
    });

    test('applyInitial: unknown keeps pending reports', () async {
      await controller().applyInitial();
      expect(crash.calls, ['setCollectionEnabled(false)']);
      expect(analytics.calls, ['setCollectionEnabled(false)']);
    });

    test('applyInitial: denied deletes pending reports', () async {
      await controller(
        consent: const TelemetryConsent(
          crash: ConsentChoice.denied,
          analytics: ConsentChoice.denied,
          version: 1,
        ),
      ).applyInitial();
      expect(crash.calls, [
        'setCollectionEnabled(false)',
        'deleteUnsentReports',
      ]);
    });

    test('applyInitial: granted sends pending reports', () async {
      await controller(
        consent: const TelemetryConsent(
          crash: ConsentChoice.granted,
          analytics: ConsentChoice.granted,
          version: 1,
        ),
      ).applyInitial();
      expect(crash.calls, ['setCollectionEnabled(true)', 'sendUnsentReports']);
      expect(analytics.calls, ['setCollectionEnabled(true)']);
    });

    test('a throwing sink never escapes', () async {
      crash.throwOnCall = StateError('sdk');
      final c = controller();
      await c.applyInitial();
      await c.update(crash: ConsentChoice.granted);
      expect(c.effective.crash, isTrue);
    });
  });
}
