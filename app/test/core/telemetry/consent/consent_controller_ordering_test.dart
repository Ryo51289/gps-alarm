// T29 round 4 (test report Lần 2 #2, #3; review round 3 R3-1, R3-3):
// controller-level ordering of SDK calls and writes, write retry, O1.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_controller.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';

import '../../../helpers/fake_key_value_store.dart';
import '../telemetry_fakes.dart';

/// Writes wait for [gate] when set; [failing] makes every write throw a
/// [StateError] whose message holds a place name.
final class _Kv extends FakeKeyValueStore {
  Completer<void>? gate;
  bool failing = false;
  final List<String> written = [];
  int writeCalls = 0;

  @override
  Future<void> setString(String key, String value) async {
    writeCalls++;
    final g = gate;
    if (g != null) {
      await g.future;
    }
    if (failing) {
      throw StateError('disk full near Ga Đồng Hới');
    }
    written.add(value);
    await super.setString(key, value);
  }
}

/// `setCollectionEnabled` waits for [gate] when set (a slow SDK), so two
/// answers really overlap.
final class _SlowAnalytics extends RecordingAnalyticsSink {
  Completer<void>? gate;

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async {
    calls.add('setCollectionEnabled($enabled)');
    final g = gate;
    if (g != null) {
      await g.future;
    }
  }
}

final class _SlowCrash extends RecordingCrashSink {
  Completer<void>? gate;

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async {
    calls.add('setCollectionEnabled($enabled)');
    final g = gate;
    if (g != null) {
      await g.future;
    }
  }
}

String? _lastSet(List<String> calls) =>
    calls.where((c) => c.startsWith('setCollectionEnabled')).lastOrNull;

const _granted = 'crash=granted;analytics=granted;version=1';

void main() {
  late _Kv kv;
  late _SlowCrash crash;
  late _SlowAnalytics analytics;
  var now = 0;

  TelemetryConsentController controller({
    TelemetryConsent consent = TelemetryConsent.initial,
  }) => TelemetryConsentController(
    store: TelemetryConsentStore(kv),
    consent: consent,
    crashSink: crash,
    analyticsSink: analytics,
    flavor: AppFlavor.prod,
    isDebugBuild: false,
    override: TelemetryOverride.auto,
    nowMs: () => now,
  );

  setUp(() {
    kv = _Kv();
    crash = _SlowCrash();
    analytics = _SlowAnalytics();
    now = 0;
  });

  group('R3-1 the SDKs end in the latest state', () {
    test('Analytics: grant, then decline while the SDK is slow', () async {
      final c = controller();
      analytics.gate = Completer();
      final a = c.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      await pumpEventQueue();
      expect(_lastSet(analytics.calls), 'setCollectionEnabled(true)');
      final b = c.update(analytics: ConsentChoice.denied);
      expect(c.effective.analytics, isFalse, reason: 'in force at once');
      analytics.gate!.complete();
      analytics.gate = null;
      await Future.wait([a, b]);
      expect(_lastSet(analytics.calls), 'setCollectionEnabled(false)');
      expect(analytics.calls.last, 'resetData');
      expect(
        kv.values[TelemetryConsentStore.consentKey],
        'crash=granted;analytics=denied;version=1',
      );
    });

    test('Analytics: both answers before any step ran', () async {
      final c = controller();
      final a = c.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      final b = c.update(analytics: ConsentChoice.denied);
      await Future.wait([a, b]);
      // The intermediate "granted" never reached the SDK.
      expect(analytics.calls, isEmpty);
      expect(_lastSet(crash.calls), 'setCollectionEnabled(true)');
      expect(kv.written, ['crash=granted;analytics=denied;version=1']);
    });

    test('Crashlytics: grant, then decline while the SDK is slow', () async {
      final c = controller();
      crash.gate = Completer();
      final a = c.update(crash: ConsentChoice.granted);
      await pumpEventQueue();
      final b = c.update(crash: ConsentChoice.denied);
      crash.gate!.complete();
      crash.gate = null;
      await Future.wait([a, b]);
      expect(_lastSet(crash.calls), 'setCollectionEnabled(false)');
      expect(crash.calls.last, 'deleteUnsentReports');
      expect(crash.calls, isNot(contains('sendUnsentReports')));
    });

    test('Crashlytics: decline, then grant while the SDK is slow', () async {
      final c = controller(
        consent: const TelemetryConsent(
          crash: ConsentChoice.granted,
          analytics: ConsentChoice.granted,
          version: 1,
        ),
      );
      await c.applyInitial();
      crash.calls.clear();
      crash.gate = Completer();
      final a = c.update(crash: ConsentChoice.denied);
      await pumpEventQueue();
      final b = c.update(crash: ConsentChoice.granted);
      crash.gate!.complete();
      crash.gate = null;
      await Future.wait([a, b]);
      expect(_lastSet(crash.calls), 'setCollectionEnabled(true)');
      expect(kv.values[TelemetryConsentStore.consentKey], _granted);
    });
  });

  group('R3-3 write ordering', () {
    test('an older slow write never lands after the newer answer', () async {
      final c = controller();
      kv.gate = Completer();
      final a = c.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      await pumpEventQueue();
      expect(kv.writeCalls, 1, reason: 'the first write has started');
      final b = c.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      await pumpEventQueue();
      expect(kv.writeCalls, 1, reason: 'the second write waits its turn');
      kv.gate!.complete();
      kv.gate = null;
      await Future.wait([a, b]);
      expect(kv.written, [_granted, 'crash=denied;analytics=denied;version=1']);
      expect(c.hasUnsavedAnswer, isFalse);
    });
  });

  group('R3-3 / Lần 2 #3 write failure', () {
    test('two attempts, type-only warning, retried on resume with backoff, '
        'never re-enabled', () async {
      final crumbs = <String>[];
      AppLog.configure(isRelease: true, breadcrumb: crumbs.add);
      final c = controller(
        consent: const TelemetryConsent(
          crash: ConsentChoice.granted,
          analytics: ConsentChoice.granted,
          version: 1,
        ),
      );
      kv.failing = true;
      await c.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      await pumpEventQueue();
      expect(kv.writeCalls, 2);
      expect(c.hasUnsavedAnswer, isTrue);
      expect(c.effective, EffectiveCollection.none);
      const warning =
          '[WARNING] napstop.telemetry.consent: consent write failed: '
          'StateError';
      expect(crumbs, [warning]);

      // Backoff 5 s: a resume before that does not write.
      now = 4999;
      await c.retryUnsaved();
      expect(kv.writeCalls, 2);
      now = 5000;
      await c.retryUnsaved();
      expect(kv.writeCalls, 4, reason: 'retried (still failing)');
      // Backoff doubled: 10 s from the last failure.
      now = 14999;
      await c.retryUnsaved();
      expect(kv.writeCalls, 4);
      kv.failing = false;
      now = 15000;
      await c.retryUnsaved();
      expect(c.hasUnsavedAnswer, isFalse);
      expect(
        kv.values[TelemetryConsentStore.consentKey],
        'crash=denied;analytics=denied;version=1',
      );
      await c.retryUnsaved();
      expect(kv.writeCalls, 5, reason: 'nothing left to write');
      // Never re-enabled by the failures.
      expect(_lastSet(crash.calls), 'setCollectionEnabled(false)');
      expect(_lastSet(analytics.calls), 'setCollectionEnabled(false)');
      for (final s in crumbs) {
        expect(s, isNot(contains('Đồng Hới')));
      }
    });

    test('the next update retries at once, whatever the backoff', () async {
      final c = controller();
      kv.failing = true;
      await c.update(crash: ConsentChoice.denied);
      expect(c.hasUnsavedAnswer, isTrue);
      kv.failing = false;
      await c.update(analytics: ConsentChoice.denied);
      expect(c.hasUnsavedAnswer, isFalse);
      expect(
        kv.values[TelemetryConsentStore.consentKey],
        'crash=denied;analytics=denied;version=1',
      );
    });
  });

  group('O1 pending reports on a first decline', () {
    test(
      'unknown → decline deletes at once; declining again does not',
      () async {
        final c = controller();
        await c.update(crash: ConsentChoice.denied);
        expect(crash.calls, ['deleteUnsentReports']);
        await c.update(crash: ConsentChoice.denied);
        expect(crash.calls, ['deleteUnsentReports']);
      },
    );

    test('granted → decline: off, then delete (once)', () async {
      final c = controller();
      await c.update(crash: ConsentChoice.granted);
      crash.calls.clear();
      await c.update(crash: ConsentChoice.denied);
      expect(crash.calls, [
        'setCollectionEnabled(false)',
        'deleteUnsentReports',
      ]);
    });

    test('decline then grant before the SDK step: nothing deleted', () async {
      final c = controller();
      final a = c.update(crash: ConsentChoice.denied);
      final b = c.update(crash: ConsentChoice.granted);
      await Future.wait([a, b]);
      expect(crash.calls, ['setCollectionEnabled(true)', 'sendUnsentReports']);
    });

    test('analytics-only answers never touch Crashlytics', () async {
      final c = controller();
      await c.update(analytics: ConsentChoice.denied);
      expect(crash.calls, isEmpty);
      expect(analytics.calls, isEmpty, reason: 'off → off');
    });
  });

  test('no-op sinks still work through the queues', () async {
    final c = TelemetryConsentController(
      store: TelemetryConsentStore(kv),
      consent: TelemetryConsent.initial,
      crashSink: const NoopCrashSink(),
      analyticsSink: const NoopAnalyticsSink(),
      flavor: AppFlavor.dev,
      isDebugBuild: true,
      override: TelemetryOverride.auto,
    );
    await c.update(crash: ConsentChoice.granted);
    expect(c.current.crash, ConsentChoice.granted);
  });
}
