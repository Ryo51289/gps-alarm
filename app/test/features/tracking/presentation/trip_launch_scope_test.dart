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

Future<void> _resume(WidgetTester tester) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
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

    for (final location in [
      '${AppRoutes.overshoot}?trip=t-1&past=1500&open=1',
      '${AppRoutes.alarm}?trip=t-1',
    ]) {
      testWidgets('T27 route $location on resume', (tester) async {
        final bridge = FakeCoreBridge();
        final h = await _pumpApp(tester, bridge: bridge);
        if (location.startsWith(AppRoutes.alarm)) {
          unawaited(h.router.push<void>(location));
        } else {
          h.router.go(location);
        }
        await tester.pumpAndSettle();
        bridge.active = activeMsg();
        await _resume(tester);
        expect(h.router.state.uri.toString(), location);
      });
    }

    testWidgets('currentTrip throws', (tester) async {
      final bridge = FakeCoreBridge()..currentTripError = channelError();
      final h = await _pumpApp(tester, bridge: bridge);
      expect(h.location, AppRoutes.home);
      bridge.currentTripError = StateError('x');
      await _resume(tester);
      expect(h.location, AppRoutes.home);
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
