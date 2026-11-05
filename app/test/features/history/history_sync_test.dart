// T28 H06-H10: HistorySync (queue → drift → ack → orphans) and trip_end.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/history/data/history_sync.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';
import 'history_fakes.dart';

const int _now = 1700001000000;

void main() {
  late FakeCoreBridge bridge;
  late ScriptedTripsRepository repo;
  late RecordingAnalyticsSink analytics;
  late RecordingCrashSink crash;
  late HistorySync sync;
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previousOnError;

  setUp(() {
    bridge = FakeCoreBridge();
    repo = ScriptedTripsRepository(bridge.calls);
    analytics = RecordingAnalyticsSink();
    crash = RecordingCrashSink();
    final telemetry = recordingTelemetry(analytics, crash);
    sync = HistorySync(
      bridge: bridge,
      repo: repo,
      telemetry: () => telemetry,
      nowMs: () => _now,
    );
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() => FlutterError.onError = previousOnError);

  List<(String, Map<String, Object>)> tripEnds() =>
      analytics.events.where((e) => e.$1 == 'trip_end').toList();

  test('H06 apply each, ack applied/already/noRow, log trip_end once, '
      'then orphans', () async {
    bridge.pending.addAll([
      finishedTrip('f1'),
      finishedTrip('f2'),
      finishedTrip('f3'),
      finishedTrip('f4'),
    ]);
    repo
      ..results['f1'] = ApplyFinishedResult.applied
      ..records['f1'] = sampleRecord(id: 'f1')
      ..results['f2'] = ApplyFinishedResult.alreadyApplied
      ..results['f3'] = ApplyFinishedResult.noRow
      ..errors['f4'] = StateError('SqliteException: Ga Đồng Hới 17.47');

    await sync.sync();

    expect(bridge.ackCalls, [
      ['f1', 'f2', 'f3'],
    ]);
    expect(tripEnds(), hasLength(1));
    expect(reported, hasLength(1));
    final e = reported.single.exception as NonFatalError;
    expect(e.where, 'historySync.apply');
    expect(e.errorType, 'StateError');
    expect(e.toString(), isNot(contains('Ga')));
    expect(
      bridge.calls,
      containsAllInOrder([
        'pendingFinishedTrips',
        'apply:f1',
        'apply:f4',
        'ackFinishedTrips',
        'currentTrip',
        'mark',
      ]),
    );
    expect(repo.marks.single, (
      except: null,
      before: _now - kOrphanGrace.inMilliseconds,
      ended: _now,
    ));
    // f4 stays in the native queue: delivered again next time.
    expect(bridge.pending.map((f) => f.tripId), ['f4']);
    expect(crash.keys['trip_active'], false);
  });

  test('a running trip is never marked', () async {
    bridge.active = activeTrip(tripId: 'run');
    await sync.sync();
    expect(repo.marks.single.except, 'run');
    expect(crash.keys.containsKey('trip_active'), isFalse);
  });

  test(
    'H07 pendingFinishedTrips fails: no ack, no currentTrip, no mark',
    () async {
      bridge.pendingError = channelError();
      await sync.sync();
      expect(bridge.calls, ['pendingFinishedTrips']);
      expect(reported, isEmpty);
    },
  );

  test('H08 currentTrip fails: no mark, ack still sent', () async {
    bridge
      ..pending.add(finishedTrip('f1'))
      ..currentTripError = channelError();
    repo.results['f1'] = ApplyFinishedResult.alreadyApplied;
    await sync.sync();
    expect(bridge.ackCalls, [
      ['f1'],
    ]);
    expect(bridge.calls, isNot(contains('mark')));
    expect(repo.marks, isEmpty);
  });

  test('a failing ack is ignored (delivered again, idempotent)', () async {
    bridge
      ..pending.add(finishedTrip('f1'))
      ..ackError = channelError();
    repo.results['f1'] = ApplyFinishedResult.alreadyApplied;
    await sync.sync();
    expect(repo.marks, hasLength(1));
  });

  test(
    'H09 overlapping calls: exactly one more run after the current',
    () async {
      final gate = Completer<void>();
      bridge.pendingGate = gate;
      final calls = [sync.sync(), sync.sync(), sync.sync()];
      await pumpEventQueue();
      expect(bridge.callCount('pendingFinishedTrips'), 1);
      bridge.pendingGate = null;
      gate.complete();
      await Future.wait(calls);
      expect(bridge.callCount('pendingFinishedTrips'), 2);
      expect(bridge.callCount('currentTrip'), 2);
      // Idle again: a new call runs once.
      await sync.sync();
      expect(bridge.callCount('pendingFinishedTrips'), 3);
    },
  );

  test('H10 tripEndEventOf: wire values, buckets, no name/coordinates', () {
    final f = finishedTrip(
      'f1',
      outcome: TripOutcomeMsg.snoozed,
      startedAtMs: 1000,
      endedAtMs: 1000 + 7 * 3600 * 1000,
      alarmReason: null,
      snoozeCount: 5,
      vehicleGuess: VehicleKindMsg.coach,
    );
    final rec = sampleRecord(
      id: 'f1',
      alarm: const TripAlarmChoice(
        mode: AlarmModeMsg.smart,
        preAlertEnabled: true,
      ),
      simulated: true,
    );
    final e = tripEndEventOf(f, rec);
    final params = e.toParameters();
    expect(e.name, 'trip_end');
    expect(params, {
      'outcome': 'snoozed',
      'end_reason': 'dismissed',
      'alarm_reason': 'none',
      'snooze_count': 3,
      'mode': 'smart',
      'vehicle_guess': 'coach',
      'duration': 'lt12h',
      'distance': 'lt500km',
      'simulated': 1,
    });
    expect(checkAnalyticsEvent(e.name, params), isNull);
    final text = params.values.join(' ');
    expect(text, isNot(contains(rec.destination.name)));
    expect(text, isNot(contains('17.')));
    expect(text, isNot(contains('106.')));
    // Every engine value maps by name.
    for (final o in TripOutcomeMsg.values) {
      for (final r in [null, ...AlarmReasonMsg.values]) {
        final p = tripEndEventOf(
          finishedTrip('x', outcome: o, alarmReason: r),
          rec,
        ).toParameters();
        expect(checkAnalyticsEvent('trip_end', p), isNull);
      }
    }
  });

  test('applied without a record (row vanished) logs nothing', () async {
    bridge.pending.add(finishedTrip('f1'));
    repo.results['f1'] = ApplyFinishedResult.applied;
    await sync.sync();
    expect(tripEnds(), isEmpty);
    expect(bridge.ackCalls.single, ['f1']);
  });

  test('a record is never printed by its toString (privacy)', () {
    final r = sampleRecord(id: 'p');
    expect(r.toString(), isNot(contains(r.destination.name)));
  });
}
