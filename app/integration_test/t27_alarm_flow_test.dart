// T27 IT1, IT2: the Flutter side of the native alarm on the real runtime
// (simulated trips of T18, real T16 ring and AlarmActivity). Android emulator
// or device API 34+, dev flavor, screen on and unlocked (P =
// android.permission):
//   adb shell pm grant app.napstop.dev P.ACCESS_FINE_LOCATION
//   adb shell pm grant app.napstop.dev P.ACCESS_COARSE_LOCATION
//   adb shell pm grant app.napstop.dev P.POST_NOTIFICATIONS
//   adb shell svc power stayon true   # IT1 ~6 min, IT2 ~11 min
//   adb shell wm dismiss-keyguard
//   flutter test integration_test/t27_alarm_flow_test.dart -d <device-id>
//
// Both tests check T16 D8 / T27 D1, D3: the app is open on /home while the
// alarm rings; the native AlarmActivity covers it, so Flutter never pushes
// /alarm (screen 5 fallback) and never goes to /overshoot (screen 8) unless
// "Xem đường quay lại" was pressed. Logs no destination name or coordinates.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm/presentation/alarm_fallback_screen.dart';
import 'package:napstop/features/alarm/presentation/overshoot_screen.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/main.dart' as app;

import 'support/sim_expectations.dart';

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

/// The app, its providers and every location the router went through.
final class _App {
  new(this.container, this.locations);

  final ProviderContainer container;
  final List<String> locations;

  CoreBridge get bridge => container.read(coreBridgeProvider);
  GoRouter get router => container.read(appRouterProvider);

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

/// Starts the real app on /home (screen 0 marked done), vi locale.
Future<_App> _launch(WidgetTester tester) async {
  tester.platformDispatcher
    ..localesTestValue = const [Locale('vi', 'VN')]
    ..localeTestValue = const Locale('vi', 'VN');
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await markOnboardingCompleted(createOnboardingStore());
  await app.main();
  await _pumpUntil(tester, find.byType(HomeScreen));
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  );
  final a = _App(container, <String>[]);
  a.locations.add(a.location);
  void track() => a.locations.add(a.location);
  // No removeListener in a tear-down: the app (container, router) is
  // already disposed by then; the router dies with it.
  a.router.routerDelegate.addListener(track);
  await cleanSlate(a.bridge);
  return a;
}

/// The trips row T25 writes before startTrip (screen 8 reads it, D7).
Future<void> _insertRow(_App a, String tripId, SimTrace trace) => a.container
    .read(tripsRepositoryProvider)
    .insertStarted(
      TripRecord.started(
        id: tripId,
        draft: TripDraft(
          destination: TripDestination(
            name: trace.destination.name ?? trace.destination.id,
            lat: trace.destination.lat,
            lng: trace.destination.lng,
            kind: switch (trace.vehicle) {
              VehicleKindMsg.train => DestinationKind.train,
              VehicleKindMsg.coach => DestinationKind.coach,
              _ => DestinationKind.bus,
            },
          ),
          source: DestinationSource.station,
        ),
        alarm: const TripAlarmChoice(
          mode: AlarmModeMsg.distance,
          distanceThresholdM: 1000,
          preAlertEnabled: true,
        ),
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
        simulated: true,
      ),
    );

/// Real-time wait. Never `tester.pump` here: while the native AlarmActivity
/// covers the app, Flutter draws no frame and a pump never returns (first
/// run of IT2 hung until the 15 min timeout). The router and the app run
/// on their own; the location listener records every navigation.
Future<T> _await<T>(WidgetTester tester, Future<T> future) => future;

void _expectNeverAlarmOrOvershoot(_App a) {
  for (final l in a.locations) {
    expect(l, isNot(startsWith(AppRoutes.alarm)), reason: '${a.locations}');
    expect(l, isNot(startsWith(AppRoutes.overshoot)), reason: '${a.locations}');
  }
  expect(find.byType(AlarmFallbackScreen), findsNothing);
  expect(find.byType(OvershootScreen), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'IT1 overshoot coach at 60x: no screen pushed, dismiss ends the trip '
    'as missed, no launch action, no /overshoot (D3)',
    timeout: const Timeout(Duration(minutes: 12)),
    (tester) async {
      final a = await _launch(tester);
      final bridge = a.bridge;
      final trace = (await loadCatalog()).byId(
        SimTraces.coachGbPhulyOvershoot,
      )!;
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);

      final tripId = _id('it1');
      await _insertRow(a, tripId, trace);
      await startSim(bridge, simConfig(tripId, trace), trace, 60);
      expect(a.location, AppRoutes.home);

      final alarm = await _await(
        tester,
        waitForUpdate<AlarmMsg>(received, timeout: const Duration(minutes: 2)),
      );
      expect(alarm.reason, AlarmReasonMsg.distance);
      expect(alarm.ringNow, isTrue);
      // Longer than kRingUiGrace twice (8 s): a fallback would be up by now.
      await _await(tester, Future<void>.delayed(const Duration(seconds: 10)));
      _expectNeverAlarmOrOvershoot(a);

      // After the first alarm the trip runs at 1x (T18 D3).
      final over = await _await(
        tester,
        waitForUpdate<OvershootMsg>(
          received,
          timeout: const Duration(minutes: 7),
        ),
      );
      expect(over.tripId, tripId);
      expect(over.pastM, greaterThan(0));
      await _await(tester, Future<void>.delayed(const Duration(seconds: 10)));
      _expectNeverAlarmOrOvershoot(a);

      final mark = received.length;
      await bridge.dismiss(tripId);
      final ended = await _await(
        tester,
        waitForUpdate<TripEndedMsg>(received, from: mark),
      );
      expect(ended.trip.tripId, tripId);
      expect(ended.trip.outcome, TripOutcomeMsg.missed);
      expect(await bridge.currentTrip(), isNull, reason: 'tracking stopped');
      // Flutter is resumed again: the coordinator already read the slot.
      await _await(tester, Future<void>.delayed(const Duration(seconds: 3)));
      expect(await bridge.consumeLaunchAction(), isNull);
      _expectNeverAlarmOrOvershoot(a);
      expect(a.location, AppRoutes.home);
      await bridge.ackFinishedTrips([tripId]);
    },
  );

  testWidgets(
    'IT2 train at 60x: snooze, snoozeEnd after 60 s with snooze not '
    'allowed, dismiss = snoozed; no /alarm, no launch action',
    timeout: const Timeout(Duration(minutes: 15)),
    (tester) async {
      final a = await _launch(tester);
      final bridge = a.bridge;
      final trace = (await loadCatalog()).byId(SimTraces.trainHnDh)!;
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);

      final tripId = _id('it2');
      await _insertRow(a, tripId, trace);
      await startSim(bridge, simConfig(tripId, trace), trace, 60);

      final first = await _await(
        tester,
        waitForUpdate<AlarmMsg>(received, timeout: const Duration(minutes: 11)),
      );
      expect(first.reason, AlarmReasonMsg.distance);
      expect(first.snoozeAllowed, isTrue);
      await _await(tester, Future<void>.delayed(const Duration(seconds: 10)));
      _expectNeverAlarmOrOvershoot(a);

      var mark = received.length;
      final snoozedAt = DateTime.now();
      await bridge.snooze(tripId);
      final again = await _await(
        tester,
        waitForUpdate<AlarmMsg>(
          received,
          from: mark,
          test: (m) => m.reason == AlarmReasonMsg.snoozeEnd,
          timeout: const Duration(seconds: 90),
        ),
      );
      final waited = DateTime.now().difference(snoozedAt);
      expect(
        waited.inMilliseconds,
        inInclusiveRange(58000, 62000 + 1000),
        reason: 'snooze lasted $waited (60 s ±2 s, +1 s poll)',
      );
      expect(again.snoozeAllowed, isFalse);
      await _await(tester, Future<void>.delayed(const Duration(seconds: 10)));
      _expectNeverAlarmOrOvershoot(a);

      mark = received.length;
      await bridge.dismiss(tripId);
      final ended = await _await(
        tester,
        waitForUpdate<TripEndedMsg>(received, from: mark),
      );
      expect(ended.trip.outcome, TripOutcomeMsg.snoozed);
      expect(ended.trip.snoozeCount, 1);
      await _await(tester, Future<void>.delayed(const Duration(seconds: 3)));
      expect(await bridge.consumeLaunchAction(), isNull);
      _expectNeverAlarmOrOvershoot(a);
      await bridge.ackFinishedTrips([tripId]);
    },
  );
}
