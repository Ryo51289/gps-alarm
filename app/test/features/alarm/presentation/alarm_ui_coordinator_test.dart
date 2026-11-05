// T27 W11–W17: AlarmUiCoordinator (launch action, grace, native first,
// fallback, D13), W13 (screen 2 removed by `go`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../destination/presentation/destination_harness.dart';
import '../helpers/alarm_fakes.dart';

LaunchActionMsg _action({String tripId = 't-1', int? pastM = 1500}) =>
    LaunchActionMsg(
      kind: LaunchActionKindMsg.overshootRoute,
      tripId: tripId,
      pastM: pastM,
    );

AlarmMsg _alarmMsg() => AlarmMsg(
  tripId: 'trip-1',
  atMs: 1700000000000,
  reason: AlarmReasonMsg.distance,
  ringNow: true,
  snoozeAllowed: true,
  distanceM: 1200,
);

/// Pumps a few frames without settling (the alarm glow repeats forever).
Future<void> _frames(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState s) async {
  tester.binding.handleAppLifecycleStateChanged(s);
  await tester.pump();
}

void main() {
  Future<AppHarness> pump(
    WidgetTester tester, {
    FakeCoreBridge? bridge,
    String initialLocation = AppRoutes.home,
  }) => pumpAppHarness(
    tester,
    bridge: bridge,
    initialLocation: initialLocation,
    alarmUi: true,
  );

  String uri(AppHarness h) => h.router.state.uri.toString();

  testWidgets('W11 cold start with a launch action → screen 8 (go)', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()..launchAction = _action();
    final h = await pump(tester, bridge: bridge);
    expect(uri(h), '/overshoot?trip=t-1&past=1500&open=1');
    expect(bridge.callCount('consumeLaunchAction'), 1);
    // Back goes home, not to an older screen.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W11 invalid launch action fields are not trusted', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..launchAction = _action(tripId: 'a/b', pastM: 3);
    final h = await pump(tester, bridge: bridge);
    expect(h.location, AppRoutes.home);
    bridge.launchAction = _action(pastM: -4);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(uri(h), '/overshoot?trip=t-1&open=1');
  });

  testWidgets('W12 resumes while a read is in flight: one call at a time, '
      'one more after it', (tester) async {
    final gate = Completer<void>();
    final bridge = FakeCoreBridge()..consumeLaunchGate = gate;
    final h = await pump(tester, bridge: bridge);
    expect(bridge.callCount('consumeLaunchAction'), 1);
    for (var i = 0; i < 2; i++) {
      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
    }
    expect(bridge.callCount('consumeLaunchAction'), 1, reason: 'in flight');
    // The action arrives while the first read waits.
    bridge.launchAction = _action();
    gate.complete();
    await tester.pumpAndSettle();
    expect(bridge.callCount('consumeLaunchAction'), 2);
    expect(uri(h), '/overshoot?trip=t-1&past=1500&open=1');
  });

  testWidgets('W14 bridge errors: no navigation; only unexpected ones '
      'reported', (tester) async {
    final bridge = FakeCoreBridge()..consumeLaunchActionError = channelError();
    final reported = ReportedErrors();
    addTearDown(reported.restore);
    final h = await pump(tester, bridge: bridge);
    expect(h.location, AppRoutes.home);
    expect(reported.texts, isEmpty);

    bridge.consumeLaunchActionError = StateError('Ga Đồng Hới t-1');
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    reported.restore();
    expect(h.location, AppRoutes.home);
    expect(reported.texts, hasLength(1));
    expect(reported.texts.single, contains('StateError'));
    expect(reported.texts.single, isNot(contains('Đồng Hới')));
  });

  testWidgets('W15 a ring while the app is visible: nothing for 3.9 s', (
    tester,
  ) async {
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge: bridge);
    bridge
      ..emit(_alarmMsg())
      ..emit(TripStateUpdateMsg(state: ringingState()));
    await tester.pump(const Duration(milliseconds: 3900));
    expect(bridge.showAlarmScreenCalls, isEmpty);
    expect(h.location, AppRoutes.home);
    // Ends before the grace: still nothing.
    bridge.emit(TripStateUpdateMsg(state: ringingState(ringing: false)));
    await tester.pump(const Duration(seconds: 20));
    expect(bridge.showAlarmScreenCalls, isEmpty);
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W16 4 s, native says no → /alarm; Back does not close it', (
    tester,
  ) async {
    final state = ringingState();
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge: bridge);
    // The trip starts ringing after the app is on screen.
    bridge
      ..active = ringingTrip(state)
      ..emit(TripStateUpdateMsg(state: state));
    await tester.pump(const Duration(milliseconds: 3999));
    expect(bridge.showAlarmScreenCalls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
    expect(find.text('Vuốt hết thanh để tắt'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
    // Still ringing a minute later: no second push, no second ask.
    await tester.pump(const Duration(minutes: 1));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);

    // The ring stops: the screen pops back to screen 1.
    bridge.emit(TripStateUpdateMsg(state: ringingState(ringing: false)));
    await _frames(tester, 10);
    expect(h.location, AppRoutes.home);
    await tester.pump(const Duration(seconds: 30));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
  });

  testWidgets('W16 native says yes but the app stays visible → /alarm after '
      '4 s more', (tester) async {
    final state = ringingState();
    final bridge = FakeCoreBridge()..showAlarmScreenResult = true;
    final h = await pump(tester, bridge: bridge);
    // The trip starts ringing after the app is on screen.
    bridge
      ..active = ringingTrip(state)
      ..emit(TripStateUpdateMsg(state: state));
    await tester.pump(const Duration(seconds: 4));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(h.location, AppRoutes.home);
    await tester.pump(const Duration(milliseconds: 100));
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
  });

  testWidgets('W17 native screen covers the app (inactive): no push, no '
      'listener (D13)', (tester) async {
    final state = ringingState();
    final bridge = FakeCoreBridge()..showAlarmScreenResult = true;
    // Screen 9: nothing else listens to the updates (screen 12 does since
    // T28: it watches activeTripProvider).
    final h = await pump(
      tester,
      bridge: bridge,
      initialLocation: AppRoutes.batteryGuide,
    );
    expect(bridge.hasListener, isTrue);
    // The trip starts ringing after the app is on screen.
    bridge
      ..active = ringingTrip(state)
      ..emit(TripStateUpdateMsg(state: state));
    await tester.pump(const Duration(seconds: 4));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    await tester.pump(const Duration(seconds: 1));
    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(bridge.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(h.location, AppRoutes.batteryGuide);
    expect(bridge.showAlarmScreenCalls, ['trip-1']);

    // Back after the user stopped the alarm on the native screen.
    bridge.active = null;
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(bridge.hasListener, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(h.location, AppRoutes.batteryGuide);
  });

  testWidgets('W13 go to screen 8 while screen 2 debounces: no request', (
    tester,
  ) async {
    final d = await pumpDestination(tester);
    await tapVisible(tester, find.text('Tìm địa chỉ bằng Google Maps'));
    final before = d.places.requests.length;
    final distancesBefore = d.bridge.distancesCalls.length;
    await tester.enterText(find.byType(TextField), 'ben xe duc');
    await tester.pump(const Duration(milliseconds: 100));
    // What AlarmUiCoordinator does with a launch action.
    d.app.router.go('/overshoot?trip=t-1&past=10&open=1');
    // One frame applies the new pages (a real device draws every 16 ms).
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(d.app.location, AppRoutes.overshoot);
    expect(d.places.requests, hasLength(before));
    expect(d.bridge.distancesCalls, hasLength(distancesBefore));
  });
}
