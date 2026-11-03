// T29 tester: consent matrix through the real bootstrap (fake SDK sinks).
// stored {unknown, accepted, declined} × read {fast, slow > 500 ms} ×
// answer {none, accept, decline} × answered {after load, during the slow
// read}. Oracle = spec §7 tables, written out independently below:
// - bootstrap: granted → crash on + sendUnsentReports, analytics on;
//   denied → crash off + deleteUnsentReports, analytics off;
//   unknown → both off, pending reports kept.
// - a change of the effective value: → on: enable (+ sendUnsentReports);
//   → off: disable + deleteUnsentReports / resetAnalyticsData.
// Also: nothing collected while the stored value is unknown or not yet
// read, a stale late read never overrides an answer, and the R2-2 race.
import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_bootstrap.dart';

import '../../../helpers/fake_key_value_store.dart';
import '../telemetry_fakes.dart';

const _options = FirebaseOptions(
  apiKey: 'test',
  appId: '1:0:android:0',
  messagingSenderId: '0',
  projectId: 'test',
);

const _event = OvershootActionEvent(
  action: OvershootActionTag.dismiss,
  simulated: false,
);

/// Reads (and optionally writes) take a fixed time.
final class _TimedKv extends FakeKeyValueStore {
  new({
    required this.read,
    this.write = Duration.zero,
    Map<String, Object>? values,
  }) : super(values);

  final Duration read;

  /// Read when each write call starts (tests change it between answers).
  Duration write;

  /// The next [failWrites] write calls throw (after [write]); negative =
  /// every call fails.
  int failWrites = 0;

  /// Write calls that reached the store (failed ones included).
  int writeCalls = 0;

  Future<T> _after<T>(Duration d, Future<T> Function() f) =>
      d == Duration.zero ? f() : Future<void>.delayed(d).then((_) => f());

  /// Simulates a process killed in the middle of a write: the call never
  /// completes; [commitAs] (if set) decides what reached the disk for a
  /// `setString` (null = nothing, else the stored text).
  bool hangWrites = false;
  String? Function(String value)? commitAs;

  Future<void> _write(Future<void> Function() f) {
    writeCalls++;
    final fail = failWrites != 0;
    if (failWrites > 0) {
      failWrites--;
    }
    return _after(
      write,
      () => fail ? Future<void>.error(StateError('disk full')) : f(),
    );
  }

  @override
  Future<String?> getString(String key) =>
      _after(read, () => super.getString(key));

  @override
  Future<int?> getInt(String key) => _after(read, () => super.getInt(key));

  @override
  Future<void> setString(String key, String value) {
    if (hangWrites) {
      writeCalls++;
      final committed = commitAs?.call(value);
      if (committed != null) {
        values[key] = committed;
      }
      return Completer<void>().future;
    }
    return _write(() => super.setString(key, value));
  }

  @override
  Future<void> setInt(String key, int value) =>
      _write(() => super.setInt(key, value));
}

/// Records each call when ISSUED (SDK channel order), then completes after
/// [delay].
final class _DelayedCrashSink extends RecordingCrashSink {
  new(this.delay);

  final Duration delay;

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async {
    await super.setCollectionEnabled(enabled: enabled);
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> sendUnsentReports() async {
    await super.sendUnsentReports();
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> deleteUnsentReports() async {
    await super.deleteUnsentReports();
    await Future<void>.delayed(delay);
  }
}

final class _DelayedAnalyticsSink extends RecordingAnalyticsSink {
  new(this.delay);

  final Duration delay;

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async {
    await super.setCollectionEnabled(enabled: enabled);
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> resetData() async {
    await super.resetData();
    await Future<void>.delayed(delay);
  }
}

enum _Stored { unknown, accepted, declined }

/// Where the stored answer is: the 3 keys of earlier builds, or the single
/// key `telemetry.consent` (round 4, R3-2).
enum _Storage { legacy, single }

enum _Read { fast, slow }

enum _Answer { none, accept, decline }

enum _When { afterLoad, duringSlowRead }

Map<String, Object> _valuesOf(_Stored s, [_Storage at = _Storage.legacy]) =>
    at == _Storage.single
    ? {TelemetryConsentStore.consentKey: _encoded(s)}
    : _legacyValuesOf(s);

String _encoded(_Stored s) => switch (s) {
  _Stored.unknown => 'crash=unknown;analytics=unknown;version=0',
  _Stored.accepted => 'crash=granted;analytics=granted;version=1',
  _Stored.declined => 'crash=denied;analytics=denied;version=1',
};

Map<String, Object> _legacyValuesOf(_Stored s) => switch (s) {
  _Stored.unknown => const {},
  _Stored.accepted => const {
    'telemetry.crash': 'granted',
    'telemetry.analytics': 'granted',
    'telemetry.consent_version': 1,
  },
  _Stored.declined => const {
    'telemetry.crash': 'denied',
    'telemetry.analytics': 'denied',
    'telemetry.consent_version': 1,
  },
};

const _on = 'setCollectionEnabled(true)';
const _off = 'setCollectionEnabled(false)';
const _send = 'sendUnsentReports';
const _delete = 'deleteUnsentReports';
const _reset = 'resetData';

/// What the store holds now (the single key; null when never written).
TelemetryConsent? _saved(FakeKeyValueStore kv) {
  final raw = kv.values[TelemetryConsentStore.consentKey];
  return raw == null ? null : TelemetryConsentStore.decode(raw as String);
}

/// What the next launch reads from [values], and whether it would collect
/// anything (release, auto).
Future<(TelemetryConsent, EffectiveCollection)> _nextLaunch(
  Map<String, Object> values,
) async {
  final c = await TelemetryConsentStore(FakeKeyValueStore(values)).read();
  return (
    c,
    resolveCollection(
      consent: c,
      flavor: AppFlavor.prod,
      isDebugBuild: false,
      override: TelemetryOverride.auto,
    ),
  );
}

String? _lastSet(List<String> calls) {
  final sets = calls.where((c) => c.startsWith('setCollectionEnabled'));
  return sets.isEmpty ? null : sets.last;
}

/// Collection-related SDK calls only (custom keys, logs and events are
/// checked elsewhere).
List<String> _sdk(List<String> calls) => [
  for (final c in calls)
    if (c.startsWith('setCollectionEnabled') ||
        c == _send ||
        c == _delete ||
        c == _reset)
      c,
];

/// §7 "lúc bootstrap" for a known stored value.
(List<String>, List<String>) _bootCalls(_Stored s) => switch (s) {
  _Stored.accepted => ([_on, _send], [_on]),
  _Stored.declined => ([_off, _delete], [_off]),
  _Stored.unknown => ([_off], [_off]),
};

bool _onFor(_Stored s) => s == _Stored.accepted;

/// §7 "Chuyển" for an effective change [before] → [after], plus the
/// orchestrator rule of round 3 (test report O1): the first crash decline
/// (previous answer not `denied`, which includes "not read yet") deletes
/// pending reports at once even when collection was already off.
(List<String>, List<String>) _changeCalls({
  required bool before,
  required bool after,
  bool previouslyDenied = false,
}) {
  if (before == after) {
    final firstDecline = !after && !previouslyDenied;
    return (firstDecline ? const [_delete] : const [], const []);
  }
  return after ? ([_on, _send], [_on]) : ([_off, _delete], [_off, _reset]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Telemetry, RecordingCrashSink, RecordingAnalyticsSink, _TimedKv)>
  boot(
    WidgetTester tester, {
    required _Stored stored,
    required _Read read,
    _Storage storage = _Storage.legacy,
    Map<String, Object>? values,
    RecordingCrashSink? crashSink,
    RecordingAnalyticsSink? analyticsSink,
    Duration write = Duration.zero,
    bool isDebugBuild = false,
    TelemetryOverride override = TelemetryOverride.auto,
    AppFlavor flavor = AppFlavor.prod,
  }) async {
    final crash = crashSink ?? RecordingCrashSink();
    final analytics = analyticsSink ?? RecordingAnalyticsSink();
    final kv = _TimedKv(
      // Slow: the value lands after boot() returns (700 ms). Legacy keys:
      // 3 reads × 400 ms = 1.2 s. Single key: 1 read of 1 s (absent: the
      // legacy reads, 3 s).
      read: read == _Read.fast
          ? Duration.zero
          : storage == _Storage.legacy
          ? const Duration(milliseconds: 400)
          : const Duration(seconds: 1),
      write: write,
      values: values ?? _valuesOf(stored, storage),
    );
    Telemetry? t;
    unawaited(
      bootstrapTelemetry(
        flavor: flavor,
        kv: kv,
        optionsFor: (_) => _options,
        init: (_) async {},
        adapters: () => (
          crash: crash,
          analytics: analytics,
          remoteConfig: FakeRemoteConfigClient(),
        ),
        override: override,
        isDebugBuild: isDebugBuild,
        installHandlers: false,
        languageCode: 'vi',
      ).then((v) => t = v),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(t, isNotNull, reason: 'bootstrap must not wait for a slow read');
    addTearDown(t!.dispose);
    return (t!, crash, analytics, kv);
  }

  Future<void> finishRead(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 3));

  for (final storage in _Storage.values) {
    for (final stored in _Stored.values) {
      for (final read in _Read.values) {
        for (final answer in _Answer.values) {
          for (final when in _When.values) {
            if (answer == _Answer.none && when == _When.duringSlowRead) {
              continue;
            }
            if (read == _Read.fast && when == _When.duringSlowRead) {
              continue;
            }
            final whenText = answer == _Answer.none ? '' : ' ${when.name}';
            final name =
                '${storage.name}: stored=${stored.name} read=${read.name} '
                'answer=${answer.name}$whenText';
            testWidgets(name, (tester) async {
              final (t, crash, analytics, kv) = await boot(
                tester,
                stored: stored,
                read: read,
                storage: storage,
              );
              final expectCrash = <String>[];
              final expectAnalytics = <String>[];
              var effectiveOn = false;
              // The answer the controller knows before the user's: `initial`
              // (unknown) until the stored value is read.
              var knownDenied = false;

              if (read == _Read.slow) {
                // Not read yet: nothing collected, nobody asked.
                expect(t.consent.isLoaded, isFalse);
                expect(t.consent.needsPrompt, isFalse);
                expect(t.consent.effective, EffectiveCollection.none);
                expectCrash.add(_off);
                expectAnalytics.add(_off);
                t.analytics.log(_event);
                await tester.pump();
                expect(analytics.events, isEmpty);
              }

              Future<void> answerNow() async {
                final choice = answer == _Answer.accept
                    ? ConsentChoice.granted
                    : ConsentChoice.denied;
                final after = answer == _Answer.accept;
                final (c, a) = _changeCalls(
                  before: effectiveOn,
                  after: after,
                  previouslyDenied: knownDenied,
                );
                expectCrash.addAll(c);
                expectAnalytics.addAll(a);
                effectiveOn = after;
                await t.consent.update(crash: choice, analytics: choice);
              }

              if (answer != _Answer.none && when == _When.duringSlowRead) {
                await answerNow();
                await finishRead(tester); // the late read must be ignored
              } else {
                if (read == _Read.slow) {
                  await finishRead(tester);
                }
                final (c, a) = _bootCalls(stored);
                expectCrash.addAll(c);
                expectAnalytics.addAll(a);
                effectiveOn = _onFor(stored);
                knownDenied = stored == _Stored.declined;
                expect(t.consent.isLoaded, isTrue);
                expect(t.consent.needsPrompt, stored == _Stored.unknown);
                if (answer != _Answer.none) {
                  await answerNow();
                }
              }
              await tester.pump();

              expect(_sdk(crash.calls), expectCrash, reason: 'crash SDK calls');
              expect(
                _sdk(analytics.calls),
                expectAnalytics,
                reason: 'analytics',
              );
              expect(
                t.consent.effective,
                EffectiveCollection(crash: effectiveOn, analytics: effectiveOn),
              );
              // Events follow the final state.
              analytics.calls.clear();
              t.analytics.log(_event);
              await tester.pump();
              expect(analytics.events, hasLength(effectiveOn ? 1 : 0));
              if (answer != _Answer.none) {
                final w = answer == _Answer.accept ? 'granted' : 'denied';
                final saved = _saved(kv)!;
                expect(saved.crash.name, w);
                expect(saved.analytics.name, w);
                expect(saved.version, 1);
                // It replaces the legacy keys: the next launch reads it.
                final (next, _) = await _nextLaunch(kv.values);
                expect(next.crash.name, w);
                expect(t.consent.needsPrompt, isFalse);
              }
            });
          }
        }
      }
    }
  }

  testWidgets('first decline during the session: pending reports deleted '
      'at once, and again on the next launch', (tester) async {
    final (t, crash, _, kv) = await boot(
      tester,
      stored: _Stored.unknown,
      read: _Read.fast,
    );
    await t.consent.update(
      crash: ConsentChoice.denied,
      analytics: ConsentChoice.denied,
    );
    // Round 3 (O1): unknown → denied deletes the reports kept while
    // unknown at once, although collection was already off.
    expect(_sdk(crash.calls), [_off, _delete]);
    // Declining again deletes nothing more.
    await t.consent.update(crash: ConsentChoice.denied);
    expect(_sdk(crash.calls), [_off, _delete]);
    final next = RecordingCrashSink();
    final t2 = await bootstrapTelemetry(
      flavor: AppFlavor.prod,
      kv: FakeKeyValueStore(kv.values),
      optionsFor: (_) => _options,
      init: (_) async {},
      adapters: () => (
        crash: next,
        analytics: RecordingAnalyticsSink(),
        remoteConfig: FakeRemoteConfigClient(),
      ),
      isDebugBuild: false,
      installHandlers: false,
      languageCode: 'vi',
    );
    addTearDown(t2.dispose);
    expect(_sdk(next.calls), [_off, _delete]);
  });

  group('debug builds and the override', () {
    for (final stored in _Stored.values) {
      testWidgets('debug + auto, stored=${stored.name}: nothing collected', (
        tester,
      ) async {
        final (t, crash, analytics, _) = await boot(
          tester,
          stored: stored,
          read: _Read.fast,
          isDebugBuild: true,
        );
        expect(t.consent.effective, EffectiveCollection.none);
        expect(crash.calls, isNot(contains(_on)));
        expect(crash.calls, isNot(contains(_send)));
        // A declined user's old reports are still deleted.
        expect(crash.calls.contains(_delete), stored == _Stored.declined);
        await t.consent.update(
          crash: ConsentChoice.granted,
          analytics: ConsentChoice.granted,
        );
        expect(t.consent.effective, EffectiveCollection.none);
        expect(analytics.calls, isNot(contains(_on)));
      });

      testWidgets(
        'prod + NAPSTOP_TELEMETRY=on, stored=${stored.name}: = auto',
        (tester) async {
          final (t, _, _, _) = await boot(
            tester,
            stored: stored,
            read: _Read.fast,
            override: TelemetryOverride.on,
          );
          final on = stored == _Stored.accepted;
          expect(
            t.consent.effective,
            EffectiveCollection(crash: on, analytics: on),
          );
        },
      );

      testWidgets('off override, stored=${stored.name}: never on', (
        tester,
      ) async {
        final (t, crash, analytics, _) = await boot(
          tester,
          stored: stored,
          read: _Read.slow,
          override: TelemetryOverride.off,
          flavor: AppFlavor.dev,
        );
        await finishRead(tester);
        await t.consent.update(
          crash: ConsentChoice.granted,
          analytics: ConsentChoice.granted,
        );
        expect(t.consent.effective, EffectiveCollection.none);
        expect(crash.calls, isNot(contains(_on)));
        expect(crash.calls, isNot(contains(_send)));
        expect(analytics.calls, isNot(contains(_on)));
      });
    }
  });

  group('R2-2 race: decline while the late read is being applied', () {
    // Stored = accepted, slow read. The late read starts enabling (each SDK
    // call takes 50 ms); the user declines at various moments during it.
    // Whatever the interleaving, the LAST collection call of each SDK must
    // be "off", nothing may be enabled or sent after the decline was issued,
    // and the session ends with nothing collected.
    for (final offsetMs in [0, 1, 25, 49, 50, 51, 75, 99, 100, 101, 149, 200]) {
      testWidgets('decline ${offsetMs}ms after the read lands', (tester) async {
        final crash = _DelayedCrashSink(const Duration(milliseconds: 50));
        final analytics = _DelayedAnalyticsSink(
          const Duration(milliseconds: 50),
        );
        final (t, _, _, _) = await boot(
          tester,
          stored: _Stored.accepted,
          read: _Read.slow,
          crashSink: crash,
          analyticsSink: analytics,
        );
        // boot() returned at 700 ms (timeout 500 ms + its own apply, 100 ms
        // of SDK calls); the 3 reads land at 1 200 ms.
        await tester.pump(const Duration(milliseconds: 500));
        expect(t.consent.isLoaded, isTrue);
        await tester.pump(Duration(milliseconds: offsetMs));
        final crashBefore = crash.calls.length;
        final analyticsBefore = analytics.calls.length;
        final done = t.consent.update(
          crash: ConsentChoice.denied,
          analytics: ConsentChoice.denied,
        );
        await tester.pump(const Duration(seconds: 1));
        await done;
        final crashAfter = crash.calls.sublist(crashBefore);
        final analyticsAfter = analytics.calls.sublist(analyticsBefore);
        expect(crashAfter, isNot(contains(_on)), reason: '$crashAfter');
        expect(crashAfter, isNot(contains(_send)), reason: '$crashAfter');
        expect(analyticsAfter, isNot(contains(_on)), reason: '$analyticsAfter');
        expect(
          crash.calls.lastWhere((c) => c.startsWith('setCollectionEnabled')),
          _off,
        );
        expect(
          analytics.calls.lastWhere(
            (c) => c.startsWith('setCollectionEnabled'),
          ),
          _off,
        );
        expect(t.consent.effective, EffectiveCollection.none);
        t.analytics.log(_event);
        await tester.pump();
        expect(analytics.events, isEmpty);
      });
    }
  });

  testWidgets(
    'revoking is immediate even when the store write is slow',
    (tester) async {
      // §7 "Thu hồi đồng ý: Tắt ngay". SharedPreferences can take > 500 ms at
      // cold start (T21 CQ1); a write can be as slow.
      final (t, crash, analytics, _) = await boot(
        tester,
        stored: _Stored.accepted,
        read: _Read.fast,
        write: const Duration(milliseconds: 800),
      );
      expect(t.consent.effective.analytics, isTrue);
      final done = t.consent.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      // The user has just switched it off: an event logged now must not go.
      t.analytics.log(_event);
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        analytics.events,
        isEmpty,
        reason: 'event sent after the user revoked consent',
      );
      expect(t.consent.effective, EffectiveCollection.none);
      await tester.pump(const Duration(seconds: 2));
      await done;
      expect(_sdk(crash.calls).last, _delete);
    },
    // docs/test-reports/T29.md bug #1, fixed in round 3 (the coder removed
    // the skip).
    skip: false,
  );

  group('round 3: two answers in quick succession, slow store', () {
    const pairs = [
      (ConsentChoice.denied, ConsentChoice.granted),
      (ConsentChoice.granted, ConsentChoice.denied),
      (ConsentChoice.granted, ConsentChoice.granted),
      (ConsentChoice.denied, ConsentChoice.denied),
    ];
    for (final stored in _Stored.values) {
      for (final (first, second) in pairs) {
        // gap 0: same frame; gap 1 ms: the first (800 ms) write has started,
        // the second write would be fast (10 ms) if it were not queued.
        for (final gapMs in [0, 1]) {
          testWidgets('stored=${stored.name} ${first.name} then ${second.name} '
              '(gap ${gapMs}ms)', (tester) async {
            final (t, crash, analytics, kv) = await boot(
              tester,
              stored: stored,
              read: _Read.fast,
              write: const Duration(milliseconds: 800),
            );
            final a = t.consent.update(crash: first, analytics: first);
            if (gapMs > 0) {
              await tester.pump(Duration(milliseconds: gapMs));
              kv.write = const Duration(milliseconds: 10);
            }
            final b = t.consent.update(crash: second, analytics: second);
            final on = second == ConsentChoice.granted;
            // In force at once, before any write landed.
            expect(
              t.consent.effective,
              EffectiveCollection(crash: on, analytics: on),
            );
            t.analytics.log(_event);
            await tester.pump(const Duration(milliseconds: 5));
            expect(analytics.events, hasLength(on ? 1 : 0));
            await tester.pump(const Duration(seconds: 3));
            await Future.wait([a, b]);

            expect(t.consent.current.crash, second);
            expect(t.consent.current.analytics, second);
            expect(
              t.consent.effective,
              EffectiveCollection(crash: on, analytics: on),
            );
            // The SDKs end in the state of the last answer.
            expect(_lastSet(crash.calls), 'setCollectionEnabled($on)');
            expect(_lastSet(analytics.calls), 'setCollectionEnabled($on)');
            // Persisted = last answer (a slow older write never lands
            // after the newer one).
            expect(_saved(kv)!.crash, second);
            expect(_saved(kv)!.analytics, second);
            expect(_saved(kv)!.version, 1);
            final (c, eff) = await _nextLaunch(kv.values);
            expect(c.crash, second);
            expect(eff, EffectiveCollection(crash: on, analytics: on));
          });
        }
      }
    }

    // Repro of test report Lần 2 bug #2 (the unsafe direction): the newer
    // answer needs FEWER SDK calls than the older one, so it is queued for
    // writing first and its SDK call is issued first.
    testWidgets('accept both, then decline usage stats at once → '
        'usage stats off in the SDK and on disk', (tester) async {
      final (t, _, analytics, kv) = await boot(
        tester,
        stored: _Stored.unknown,
        read: _Read.fast,
      );
      final a = t.consent.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      final b = t.consent.update(analytics: ConsentChoice.denied);
      await tester.pump(const Duration(seconds: 1));
      await Future.wait([a, b]);
      expect(
        t.consent.effective,
        const EffectiveCollection(crash: true, analytics: false),
      );
      expect(_lastSet(analytics.calls), _off, reason: '${analytics.calls}');
      expect(_saved(kv)!.analytics, ConsentChoice.denied);
      final (_, eff) = await _nextLaunch(kv.values);
      expect(eff.analytics, isFalse);
    });

    testWidgets('a decline while the read is slow, then accept', (
      tester,
    ) async {
      final (t, _, _, kv) = await boot(
        tester,
        stored: _Stored.declined,
        read: _Read.slow,
        write: const Duration(milliseconds: 800),
      );
      final a = t.consent.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      final b = t.consent.update(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
      );
      await tester.pump(const Duration(seconds: 4)); // late read lands too
      await Future.wait([a, b]);
      expect(
        t.consent.effective,
        const EffectiveCollection(crash: true, analytics: true),
      );
      expect(_saved(kv)!.crash, ConsentChoice.granted);
    });
  });

  group('round 4: the store write fails after a decline', () {
    // One write per try now (single key, R3-2); two tries at once.
    // failWrites: 1 = the first try (the immediate retry succeeds);
    // 2 = both tries (saved at the next answer / a resume); -1 = always.
    for (final storage in _Storage.values) {
      for (final stored in _Stored.values) {
        for (final failWrites in [1, 2, -1]) {
          for (final read in _Read.values) {
            final persistent = failWrites < 0;
            testWidgets(
              '${storage.name}: stored=${stored.name} read=${read.name} '
              'failWrites=$failWrites',
              (tester) async {
                final (t, crash, analytics, kv) = await boot(
                  tester,
                  stored: stored,
                  read: read,
                  storage: storage,
                );
                final before = Map<String, Object>.of(kv.values);
                kv.failWrites = failWrites;
                final crashMark = crash.calls.length;
                final analyticsMark = analytics.calls.length;
                await t.consent.update(
                  crash: ConsentChoice.denied,
                  analytics: ConsentChoice.denied,
                );
                // The late read (slow case) lands, then a stale "accepted"
                // is offered again: both must be ignored.
                await tester.pump(const Duration(seconds: 4));
                await t.consent.adoptLoaded(
                  const TelemetryConsent(
                    crash: ConsentChoice.granted,
                    analytics: ConsentChoice.granted,
                    version: 1,
                  ),
                );
                await tester.pump();

                void expectOff() {
                  expect(t.consent.effective, EffectiveCollection.none);
                  expect(t.consent.current.crash, ConsentChoice.denied);
                  final crashAfter = crash.calls.sublist(crashMark);
                  final analyticsAfter = analytics.calls.sublist(analyticsMark);
                  expect(
                    crashAfter,
                    isNot(contains(_on)),
                    reason: '$crashAfter',
                  );
                  expect(crashAfter, isNot(contains(_send)));
                  expect(analyticsAfter, isNot(contains(_on)));
                  expect(_lastSet(crash.calls), _off);
                  expect(_lastSet(analytics.calls), _off);
                }

                expectOff();
                t.analytics.log(_event);
                await tester.pump();
                expect(analytics.events, isEmpty);

                switch (failWrites) {
                  case 1:
                    expect(kv.writeCalls, 2, reason: 'fail + immediate retry');
                    expect(t.consent.hasUnsavedAnswer, isFalse);
                  case 2:
                    expect(kv.writeCalls, 2, reason: 'two tries at once');
                    expect(t.consent.hasUnsavedAnswer, isTrue);
                    // The next answer retries at once (no backoff).
                    await t.consent.update(analytics: ConsentChoice.denied);
                    await tester.pump();
                    expect(kv.writeCalls, 3);
                    expect(t.consent.hasUnsavedAnswer, isFalse);
                  default:
                    expect(kv.writeCalls, 2);
                    expect(t.consent.hasUnsavedAnswer, isTrue);
                    await t.consent.update(analytics: ConsentChoice.denied);
                    await tester.pump();
                    expect(kv.writeCalls, 4, reason: 'retried at once, twice');
                    expect(t.consent.hasUnsavedAnswer, isTrue);
                }
                expectOff();

                final (c, eff) = await _nextLaunch(kv.values);
                if (!persistent) {
                  expect(c.crash, ConsentChoice.denied, reason: 'saved');
                  expect(c.analytics, ConsentChoice.denied);
                  expect(eff, EffectiveCollection.none);
                } else {
                  // Documented limit (§7 "Lưu và thứ tự", round 4): nothing
                  // could be written, so the next launch reads the old value
                  // exactly; it is "accepted" only if the user accepted it.
                  final (old, oldEff) = await _nextLaunch(before);
                  expect(c.crash, old.crash);
                  expect(c.analytics, old.analytics);
                  expect(eff, oldEff);
                  if (stored != _Stored.accepted) {
                    expect(eff, EffectiveCollection.none);
                  }
                }
              },
            );
          }
        }
      }
    }
  });

  testWidgets('round 4: an unsaved answer is retried on resume, with backoff '
      '(fake clock), and never re-enables anything', (tester) async {
    var now = 0;
    final kv = _TimedKv(
      read: Duration.zero,
      values: _valuesOf(_Stored.accepted, _Storage.single),
    )..failWrites = -1;
    final crashSink = RecordingCrashSink();
    final analyticsSink = RecordingAnalyticsSink();
    final controller = TelemetryConsentController(
      store: TelemetryConsentStore(kv),
      consent: const TelemetryConsent(
        crash: ConsentChoice.granted,
        analytics: ConsentChoice.granted,
        version: 1,
      ),
      crashSink: crashSink,
      analyticsSink: analyticsSink,
      flavor: AppFlavor.prod,
      isDebugBuild: false,
      override: TelemetryOverride.auto,
      nowMs: () => now,
    );
    final crash = CrashReporter(crashSink);
    final t = Telemetry(
      analytics: AppAnalytics(
        sink: analyticsSink,
        crash: crash,
        isEnabled: () => controller.effective.analytics,
      ),
      crash: crash,
      engineParams: EngineParamsSource(
        const NoopRemoteConfigClient(),
        flavor: AppFlavor.prod,
      ),
      consent: controller,
    )..attachLifecycle();
    addTearDown(t.dispose);

    Future<void> resumeAt(int ms) async {
      now = ms;
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    await controller.update(
      crash: ConsentChoice.denied,
      analytics: ConsentChoice.denied,
    );
    await tester.pump();
    expect(controller.hasUnsavedAnswer, isTrue);
    expect(kv.writeCalls, 2);
    await resumeAt(4999); // before the 5 s backoff: no try
    expect(kv.writeCalls, 2);
    await resumeAt(5000); // 2 more tries, fail; next after 10 s
    expect(kv.writeCalls, 4);
    await resumeAt(14999);
    expect(kv.writeCalls, 4);
    await resumeAt(15000);
    expect(kv.writeCalls, 6);
    kv.failWrites = 0; // the disk recovers
    await resumeAt(15000 + 20000);
    expect(kv.writeCalls, 7);
    expect(controller.hasUnsavedAnswer, isFalse);
    expect(_saved(kv)!.crash, ConsentChoice.denied);
    await resumeAt(60000 * 60); // nothing left to save
    expect(kv.writeCalls, 7);
    expect(controller.effective, EffectiveCollection.none);
    expect(_lastSet(crashSink.calls), _off);
    expect(_lastSet(analyticsSink.calls), _off);
    expect(crashSink.calls.where((c) => c == _on), isEmpty);
    final (c, eff) = await _nextLaunch(kv.values);
    expect(c.crash, ConsentChoice.denied);
    expect(eff, EffectiveCollection.none);
  });

  group('round 4: single key vs legacy keys', () {
    const legacyGranted = {
      'telemetry.crash': 'granted',
      'telemetry.analytics': 'granted',
      'telemetry.consent_version': 1,
    };
    const legacyDenied = {
      'telemetry.crash': 'denied',
      'telemetry.analytics': 'denied',
      'telemetry.consent_version': 1,
    };

    for (final read in _Read.values) {
      testWidgets('legacy granted + new key declined → declined '
          '(${read.name})', (tester) async {
        final (t, crash, _, _) = await boot(
          tester,
          stored: _Stored.declined,
          read: read,
          storage: _Storage.single,
          values: {
            ...legacyGranted,
            TelemetryConsentStore.consentKey: _encoded(_Stored.declined),
          },
        );
        await tester.pump(const Duration(seconds: 4));
        expect(t.consent.current.crash, ConsentChoice.denied);
        expect(t.consent.effective, EffectiveCollection.none);
        expect(t.consent.needsPrompt, isFalse);
        expect(crash.calls, isNot(contains(_on)));
        expect(crash.calls, contains(_delete));
      });
    }

    testWidgets('legacy declined + new key granted → granted (new wins)', (
      tester,
    ) async {
      final (t, _, _, _) = await boot(
        tester,
        stored: _Stored.accepted,
        read: _Read.fast,
        values: {
          ...legacyDenied,
          TelemetryConsentStore.consentKey: _encoded(_Stored.accepted),
        },
      );
      expect(
        t.consent.effective,
        const EffectiveCollection(crash: true, analytics: true),
      );
    });

    const malformed = [
      '',
      ' ',
      'garbage',
      'crash=granted;analytics=granted',
      'crash=granted;analytics=granted;version=',
      'crash=granted;analytics=granted;version=1;',
      'crash=granted;analytics=granted;version=1 ',
      ' crash=granted;analytics=granted;version=1',
      'crash=granted;analytics=granted;version=1\n',
      'CRASH=granted;analytics=granted;version=1',
      'crash=Granted;analytics=granted;version=1',
      'crash=yes;analytics=granted;version=1',
      'analytics=granted;crash=granted;version=1',
      'crash=granted;analytics=granted;version=-1',
      'crash=granted;analytics=granted;version=1234567890',
      'crash=granted,analytics=granted,version=1',
      '{"crash":"granted","analytics":"granted","version":1}',
      'crash=granted;crash=granted;version=1',
      'crash=unknown;analytics=unknown;version=0', // valid: unanswered
    ];
    for (final (i, raw) in malformed.indexed) {
      testWidgets('legacy granted + new key #$i malformed/unanswered → '
          'unanswered, nothing collected', (tester) async {
        final (t, crash, analytics, _) = await boot(
          tester,
          stored: _Stored.unknown,
          read: _Read.fast,
          values: {...legacyGranted, TelemetryConsentStore.consentKey: raw},
        );
        expect(t.consent.current.crash, ConsentChoice.unknown);
        expect(t.consent.current.analytics, ConsentChoice.unknown);
        expect(t.consent.needsPrompt, isTrue, reason: 'ask again');
        expect(t.consent.effective, EffectiveCollection.none);
        expect(_sdk(crash.calls), [_off], reason: 'no delete, never on');
        expect(_sdk(analytics.calls), [_off]);
      });
    }

    testWidgets('legacy granted + new key of the wrong type → unanswered', (
      tester,
    ) async {
      final (t, crash, _, _) = await boot(
        tester,
        stored: _Stored.unknown,
        read: _Read.fast,
        values: {...legacyGranted, TelemetryConsentStore.consentKey: 1},
      );
      expect(t.consent.effective, EffectiveCollection.none);
      expect(t.consent.needsPrompt, isTrue);
      expect(crash.calls, isNot(contains(_on)));
    });

    test('decode: never throws; granted only for the exact format', () {
      final valid = RegExp(
        '^crash=(granted|denied|unknown);analytics=(granted|denied|unknown);'
        r'version=(\d{1,9})$',
      );
      final rnd = Random(4);
      const alphabet = 'crashanlytigdeuowkv=;0123456789 ,-\n';
      const base = 'crash=granted;analytics=granted;version=1';
      for (var i = 0; i < 30000; i++) {
        final String s;
        if (i.isEven) {
          final len = rnd.nextInt(48);
          s = String.fromCharCodes([
            for (var j = 0; j < len; j++)
              alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
          ]);
        } else {
          final p = rnd.nextInt(base.length);
          final ch = alphabet[rnd.nextInt(alphabet.length)];
          s = switch (rnd.nextInt(3)) {
            0 => base.replaceRange(p, p + 1, ''),
            1 => base.replaceRange(p, p, ch),
            _ => base.replaceRange(p, p + 1, ch),
          };
        }
        final c = TelemetryConsentStore.decode(s);
        if (!valid.hasMatch(s)) {
          expect(c, TelemetryConsent.initial, reason: s);
        }
        if (c.crash == ConsentChoice.granted) {
          expect(s, startsWith('crash=granted;'), reason: s);
        }
      }
      // Every strict prefix of a stored value (a torn write) is unanswered.
      for (final s in _Stored.values) {
        final v = _encoded(s);
        for (var n = 0; n < v.length; n++) {
          expect(
            TelemetryConsentStore.decode(v.substring(0, n)),
            TelemetryConsent.initial,
            reason: v.substring(0, n),
          );
        }
      }
    });
  });

  group('round 4: process killed in the middle of the write', () {
    const olds = <String, Map<String, Object>>{
      'none': {},
      'legacy accepted': {
        'telemetry.crash': 'granted',
        'telemetry.analytics': 'granted',
        'telemetry.consent_version': 1,
      },
      'legacy declined': {
        'telemetry.crash': 'denied',
        'telemetry.analytics': 'denied',
        'telemetry.consent_version': 1,
      },
      'single accepted': {
        'telemetry.consent': 'crash=granted;analytics=granted;version=1',
      },
      'single declined': {
        'telemetry.consent': 'crash=denied;analytics=denied;version=1',
      },
      'single unknown': {
        'telemetry.consent': 'crash=unknown;analytics=unknown;version=0',
      },
    };
    const answers = <List<ConsentChoice>>[
      [ConsentChoice.denied],
      [ConsentChoice.granted],
      [ConsentChoice.granted, ConsentChoice.denied],
      [ConsentChoice.denied, ConsentChoice.granted],
    ];
    const commits = ['nothing', 'all', 'half', 'all but 1 char'];

    String? commit(String mode, String v) => switch (mode) {
      'nothing' => null,
      'all' => v,
      'half' => v.substring(0, v.length ~/ 2),
      _ => v.substring(0, v.length - 1),
    };

    for (final MapEntry(key: oldName, value: old) in olds.entries) {
      for (final seq in answers) {
        for (final mode in commits) {
          testWidgets(
            'old=$oldName answers=${seq.map((a) => a.name).join('>')} '
            'disk got: $mode',
            (tester) async {
              final (t, crash, analytics, kv) = await boot(
                tester,
                stored: _Stored.unknown,
                read: _Read.fast,
                values: old,
              );
              final (oldConsent, oldEff) = await _nextLaunch(old);
              kv
                ..hangWrites = true
                ..commitAs = (v) => commit(mode, v);
              for (final a in seq) {
                // The save never completes: do not await.
                unawaited(t.consent.update(crash: a, analytics: a));
              }
              await tester.pump(const Duration(seconds: 1));
              final last = seq.last;
              final on = last == ConsentChoice.granted;
              // In session: the SDKs follow the last answer, whatever the
              // disk does.
              expect(
                t.consent.effective,
                EffectiveCollection(crash: on, analytics: on),
              );
              expect(_lastSet(crash.calls), 'setCollectionEnabled($on)');
              expect(_lastSet(analytics.calls), 'setCollectionEnabled($on)');
              expect(kv.writeCalls, 1, reason: 'one write of the latest');

              // Next launch, after the kill.
              final (c, eff) = await _nextLaunch(kv.values);
              final expected = switch (mode) {
                'nothing' => oldConsent.crash,
                'all' => last,
                _ => ConsentChoice.unknown, // torn single key → unanswered
              };
              expect(c.crash, expected);
              final userAccepted =
                  seq.contains(ConsentChoice.granted) ||
                  oldConsent.crash == ConsentChoice.granted;
              if (eff.crash || eff.analytics) {
                expect(userAccepted, isTrue, reason: 'collects without a yes');
              }
              if (mode == 'nothing') {
                expect(eff, oldEff, reason: 'documented limit: old value');
              }
            },
          );
        }
      }
    }
  });
}
