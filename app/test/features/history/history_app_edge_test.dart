// Tester (T28): the real NapStopApp (AppBackgroundTasks) driving HistorySync
// with overlapping triggers, plus what screen 11 shows for the running trip,
// an orphan that gets its result later, and simulated-only months.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/trip_providers.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';
import 'history_fakes.dart';

final DateTime _now = DateTime(2026, 11, 28, 20);
final int _nowMs = _now.millisecondsSinceEpoch;

const Size _tall = Size(390, 2000);

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> s) async {
  s.forEach(tester.binding.handleAppLifecycleStateChanged);
  await tester.pump();
}

const List<AppLifecycleState> _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const List<AppLifecycleState> _toForeground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

Future<AppHarness> _pumpApp(
  WidgetTester tester, {
  required FakeCoreBridge bridge,
  required Future<void> Function(ProviderContainer c) seed,
  RecordingAnalyticsSink? analytics,
  bool settle = true,
}) => pumpAppHarness(
  tester,
  bridge: bridge,
  initialLocation: AppRoutes.history,
  now: _now,
  size: _tall,
  seed: seed,
  useApp: true,
  settle: settle,
  overrides: [
    if (analytics != null)
      telemetryProvider.overrideWithValue(
        recordingTelemetry(analytics, RecordingCrashSink()),
      ),
  ],
);

int _tripEnds(RecordingAnalyticsSink a) =>
    a.events.where((e) => e.$1 == 'trip_end').length;

void main() {
  testWidgets('app start + resume + TripEndedMsg at once: 2 queue reads, '
      'one result, one trip_end', (tester) async {
    final analytics = RecordingAnalyticsSink();
    final gate = Completer<void>();
    final bridge = FakeCoreBridge(active: activeTrip(tripId: 'run'))
      ..pendingGate = gate;
    final h = await _pumpApp(
      tester,
      bridge: bridge,
      analytics: analytics,
      settle: false,
      seed: (c) => c
          .read(tripsRepositoryProvider)
          .insertStarted(
            sampleRecord(id: 'run', startedAtMs: _nowMs - 3600000),
          ),
    );
    await tester.pump(); // post-frame sync starts and waits on the queue
    expect(bridge.callCount('pendingFinishedTrips'), 1);
    // The trip ends; the app comes back and the stream says so, all at once.
    bridge
      ..active = null
      ..pending.add(finishedTrip('run'));
    await _lifecycle(tester, _toBackground);
    await _lifecycle(tester, _toForeground);
    bridge.emit(tripEnded(tripId: 'run'));
    await tester.pump();
    bridge.pendingGate = null;
    gate.complete();
    await tester.pumpAndSettle();

    expect(bridge.callCount('pendingFinishedTrips'), 2);
    expect(bridge.pending, isEmpty);
    expect(_tripEnds(analytics), 1);
    expect(
      (await h.read(tripsRepositoryProvider).byId('run'))!.result,
      TripOutcomeMsg.onTime,
    );
    expect(find.text('Woke up on time'), findsOneWidget);
    expect(find.text('Result unknown'), findsNothing);
  });

  testWidgets('the running trip stays "Tracking now" through start, resumes '
      'and an unrelated TripEndedMsg (9 h old trip)', (tester) async {
    final bridge = FakeCoreBridge(active: activeTrip(tripId: 'run'));
    final h = await _pumpApp(
      tester,
      bridge: bridge,
      seed: (c) => c
          .read(tripsRepositoryProvider)
          .insertStarted(
            sampleRecord(id: 'run', startedAtMs: _nowMs - 9 * 3600000),
          ),
    );
    for (var i = 0; i < 3; i++) {
      await _lifecycle(tester, _toBackground);
      await _lifecycle(tester, _toForeground);
      await tester.pumpAndSettle();
    }
    bridge.emit(tripEnded(tripId: 'other'));
    await tester.pumpAndSettle();
    expect(bridge.callCount('pendingFinishedTrips'), greaterThanOrEqualTo(5));
    expect(find.text('Tracking now'), findsOneWidget);
    expect(find.text('Result unknown'), findsNothing);
    expect(find.byTooltip('Set up this trip again'), findsNothing);
    expect(
      (await h.read(tripsRepositoryProvider).byId('run'))!.endedAtMs,
      isNull,
    );
  });

  testWidgets('updates are not followed while hidden; the end is picked up '
      'at the next resume', (tester) async {
    final bridge = FakeCoreBridge(active: activeTrip(tripId: 'run'));
    await _pumpApp(
      tester,
      bridge: bridge,
      seed: (c) => c
          .read(tripsRepositoryProvider)
          .insertStarted(
            sampleRecord(id: 'run', startedAtMs: _nowMs - 3600000),
          ),
    );
    await _lifecycle(tester, _toBackground);
    // Other providers (screen 4 / tab badge) may still listen to the
    // broadcast stream, so count queue reads instead of listeners.
    final hidden = bridge.callCount('pendingFinishedTrips');
    // Ends in the background: no sync now (the stream is not followed).
    bridge
      ..active = null
      ..pending.add(finishedTrip('run', outcome: TripOutcomeMsg.missed))
      ..emit(tripEnded(tripId: 'run'));
    await tester.pump();
    expect(bridge.callCount('pendingFinishedTrips'), hidden);
    await _lifecycle(tester, _toForeground);
    await tester.pumpAndSettle();
    expect(bridge.callCount('pendingFinishedTrips'), hidden + 1);
    expect(find.text('Missed the stop'), findsOneWidget);
  });

  testWidgets('an orphan shows "Result unknown", then its late result '
      'replaces it (TripEndedMsg)', (tester) async {
    final bridge = FakeCoreBridge();
    await _pumpApp(
      tester,
      bridge: bridge,
      seed: (c) => c
          .read(tripsRepositoryProvider)
          .insertStarted(
            sampleRecord(id: 'orph', startedAtMs: _nowMs - 10 * 60000),
          ),
    );
    expect(find.text('Result unknown'), findsOneWidget);
    expect(find.byTooltip('Set up this trip again'), findsOneWidget);
    bridge
      ..pending.add(finishedTrip('orph', outcome: TripOutcomeMsg.cancelled))
      ..emit(tripEnded(tripId: 'orph'));
    await tester.pumpAndSettle();
    expect(find.text('Result unknown'), findsNothing);
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets('a month of simulated trips only: card 0 / 0 / "—", rows '
      'labelled "Simulated" without restart', (tester) async {
    final bridge = FakeCoreBridge();
    await _pumpApp(
      tester,
      bridge: bridge,
      seed: (c) async {
        final repo = c.read(tripsRepositoryProvider);
        for (final id in ['s1', 's2']) {
          await repo.insertStarted(
            sampleRecord(
              id: id,
              startedAtMs: _nowMs - 3600000,
              simulated: true,
            ),
          );
          await repo.applyFinished(finishedTrip(id, travelledM: 33790));
        }
      },
    );
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Simulated'), findsNWidgets(2));
    expect(find.text('Woke up on time'), findsNWidgets(2));
    expect(find.byTooltip('Set up this trip again'), findsNothing);
  });
}
