// T26 W21, W22, W22b: screen 4 opens by itself from screen 1 only (D12).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../alarm/helpers/alarm_fakes.dart';
import '../tracking_fixtures.dart';

/// The real `NapStopApp` (its `TripLaunchScope`) on the harness providers.
Future<AppHarness> _pumpApp(
  WidgetTester tester, {
  required FakeCoreBridge bridge,
  String initialLocation = AppRoutes.home,
}) async {
  final h = await pumpAppHarness(
    tester,
    bridge: bridge,
    initialLocation: initialLocation,
    settle: false,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: const NapStopApp(flavor: AppFlavor.dev),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _resume(WidgetTester tester, {bool settle = true}) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await _frames(tester);
  }
}

/// Pumps frames without settling (the glow of screen 5 pulses forever).
Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('W21 cold start on /home with a running trip → /tracking', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(active: activeMsg(state: w01State()));
    final h = await _pumpApp(tester, bridge: bridge);
    expect(h.location, AppRoutes.tracking);
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
  });

  testWidgets('W21 resume on /home with a running trip → /tracking', (
    tester,
  ) async {
    final bridge = FakeCoreBridge();
    final h = await _pumpApp(tester, bridge: bridge);
    expect(h.location, AppRoutes.home);
    bridge.active = activeMsg(state: w01State());
    await _resume(tester);
    expect(h.location, AppRoutes.tracking);
  });

  group('W22 no navigation', () {
    for (final (name, active, location) in [
      ('no trip', null, AppRoutes.home),
      (
        'ended trip',
        activeMsg(
          state: stateMsg(
            phase: TripPhaseMsg.ended,
            outcome: TripOutcomeMsg.onTime,
          ),
        ),
        AppRoutes.home,
      ),
      ('screen 0', activeMsg(), AppRoutes.onboarding),
      ('screen 2', activeMsg(), AppRoutes.destination),
    ]) {
      testWidgets('$name at $location (start + resume)', (tester) async {
        final bridge = FakeCoreBridge(active: active);
        final h = await _pumpApp(
          tester,
          bridge: bridge,
          initialLocation: location,
        );
        expect(h.location, location);
        await _resume(tester);
        expect(h.location, location);
      });
    }

    testWidgets('T27 route /overshoot?trip=t-1&past=1500&open=1 on resume', (
      tester,
    ) async {
      const location = '${AppRoutes.overshoot}?trip=t-1&past=1500&open=1';
      final bridge = FakeCoreBridge();
      final h = await _pumpApp(tester, bridge: bridge);
      h.router.go(location);
      await tester.pumpAndSettle();
      bridge.active = activeMsg();
      await _resume(tester);
      expect(h.router.state.uri.toString(), location);
    });

    // The real screen 5 fallback (T27 §8) only stays while its trip rings:
    // with no trip it closes itself. The trip is running (not ENDED), so
    // only the `/alarm` on top keeps screen 4 away.
    testWidgets('T27 route /alarm?trip=t-1 on resume', (tester) async {
      const location = '${AppRoutes.alarm}?trip=t-1';
      final bridge = FakeCoreBridge();
      final h = await _pumpApp(tester, bridge: bridge);
      bridge.active = ringingTrip(ringingState(tripId: 't-1'));
      unawaited(h.router.push<void>(location));
      // No settling: the alarm glow pulses forever.
      await _frames(tester);
      expect(h.router.state.uri.toString(), location);
      // Every location change: a `go('/tracking')` would be hidden by the
      // coordinator pushing /alarm again after its grace.
      final seen = <String>[];
      void record() => seen.add(h.router.state.uri.toString());
      h.router.routerDelegate.addListener(record);
      addTearDown(() => h.router.routerDelegate.removeListener(record));
      await _resume(tester, settle: false);
      // Past the grace of AlarmUiCoordinator (it does not push /alarm
      // twice either).
      await tester.pump(const Duration(seconds: 10));
      await _frames(tester);
      expect(h.router.state.uri.toString(), location);
      expect(seen.where((l) => l != location), isEmpty);
    });

    testWidgets('currentTrip throws', (tester) async {
      final bridge = FakeCoreBridge()..currentTripError = channelError();
      final h = await _pumpApp(tester, bridge: bridge);
      expect(h.location, AppRoutes.home);
      bridge.currentTripError = StateError('x');
      // AlarmUiCoordinator of NapStopApp reads currentTrip() too on resume
      // and reports an unexpected error by its type only (T27 §10);
      // TripLaunchScope reports nothing.
      final reported = ReportedErrors();
      addTearDown(reported.restore);
      await _resume(tester);
      reported.restore();
      expect(h.location, AppRoutes.home);
      expect(reported.texts, hasLength(1));
      expect(
        reported.texts.single,
        contains('NonFatalError(alarmUi.currentTrip: StateError)'),
      );
    });
  });

  testWidgets('W22b T27 navigates while currentTrip is pending', (
    tester,
  ) async {
    final bridge = FakeCoreBridge();
    final h = await _pumpApp(tester, bridge: bridge);
    final gate = Completer<void>();
    bridge
      ..active = activeMsg()
      ..currentTripGate = gate;
    await _resume(tester);
    const overshoot = '${AppRoutes.overshoot}?trip=t-1&past=1500&open=1';
    h.router.go(overshoot);
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(h.router.state.uri.toString(), overshoot);
  });
}
