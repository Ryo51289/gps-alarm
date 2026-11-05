// T27 tester, beyond the spec (risk: "can the app fail to wake the user?"):
// the screen 5 safety net of AlarmUiCoordinator in situations W15–W17 do not
// cover, and the launch action against a visible safety net.
//  X1 cold start into a trip that is already ringing (snapshot only).
//  X2 Home / back while ringing: the next resume starts a full new grace.
//  X3 a ring that stops at 3.9 s and rings again (snooze end) gets a full
//     4 s grace from the new start, not from the first one.
//  X4 a launch action while /alarm is shown: screen 8 wins, the end of the
//     ring does not pop it back home.
//  X5 the TripEndedMsg of another trip does not close the safety net.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../helpers/alarm_fakes.dart';

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
  Future<AppHarness> pump(WidgetTester tester, FakeCoreBridge bridge) =>
      pumpAppHarness(tester, bridge: bridge, alarmUi: true);

  String uri(AppHarness h) => h.router.state.uri.toString();

  testWidgets('X1 cold start while the trip already rings: native asked '
      'after 4 s, then the safety net', (tester) async {
    final state = ringingState();
    // No stream item at all: only the currentTrip() snapshot says "ringing".
    final bridge = FakeCoreBridge()..active = ringingTrip(state);
    // The harness settles the first frames (fake time passes), so only the
    // outcome is checked here; the 4 s timing is X1b.
    final h = await pump(tester, bridge);
    await tester.pump(const Duration(seconds: 5));
    await _frames(tester);
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    expect(uri(h), '/alarm?trip=trip-1');
    expect(find.text('Vuốt hết thanh để tắt'), findsOneWidget);
  });

  testWidgets('X1b app brought back while the trip already rings (snapshot '
      'only): full grace from the resume, then the safety net', (tester) async {
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.paused);
    // Rings while the app is in the background; no stream item reaches it.
    bridge.active = ringingTrip(ringingState());
    await tester.pump(const Duration(minutes: 1));
    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(bridge.showAlarmScreenCalls, isEmpty);
    expect(h.location, AppRoutes.home);
    await tester.pump(const Duration(milliseconds: 200));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
  });

  testWidgets('X2 leaving while ringing, back still ringing: a full new '
      'grace, then the safety net', (tester) async {
    final state = ringingState();
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge);
    bridge
      ..active = ringingTrip(state)
      ..emit(TripStateUpdateMsg(state: state));
    await tester.pump(const Duration(seconds: 3));
    // Home 3 s into the ring (no native screen yet).
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(bridge.showAlarmScreenCalls, isEmpty, reason: 'not visible');
    expect(h.location, AppRoutes.home);

    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(bridge.showAlarmScreenCalls, isEmpty, reason: 'new grace');
    await tester.pump(const Duration(milliseconds: 200));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
  });

  testWidgets('X3 ring 3.9 s, stop, ring again: the grace restarts', (
    tester,
  ) async {
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge);
    final ringing = ringingState();
    bridge
      ..active = ringingTrip(ringing)
      ..emit(TripStateUpdateMsg(state: ringing));
    await tester.pump(const Duration(milliseconds: 3900));
    bridge.emit(
      TripStateUpdateMsg(
        state: ringingState(phase: TripPhaseMsg.snoozed, ringing: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final again = ringingState(
      snoozeCount: 1,
      reason: AlarmReasonMsg.snoozeEnd,
    );
    bridge
      ..active = ringingTrip(again)
      ..emit(TripStateUpdateMsg(state: again));
    await tester.pump(const Duration(milliseconds: 3900));
    expect(bridge.showAlarmScreenCalls, isEmpty);
    expect(h.location, AppRoutes.home);
    await tester.pump(const Duration(milliseconds: 200));
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
  });

  testWidgets('X4 launch action while /alarm is shown: screen 8 wins and '
      'stays when the ring ends', (tester) async {
    final state = ringingState(
      phase: TripPhaseMsg.overshot,
      overshootPastM: 1300,
      reason: AlarmReasonMsg.overshoot,
    );
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge);
    bridge
      ..active = ringingTrip(state)
      ..emit(TripStateUpdateMsg(state: state));
    await tester.pump(const Duration(seconds: 4));
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');

    // "Xem đường quay lại" was pressed on a native screen that came up late.
    bridge.launchAction = LaunchActionMsg(
      kind: LaunchActionKindMsg.overshootRoute,
      tripId: 'trip-1',
      pastM: 1300,
    );
    await _lifecycle(tester, AppLifecycleState.inactive);
    bridge
      ..active = null
      ..emit(
        TripStateUpdateMsg(
          state: ringingState(
            phase: TripPhaseMsg.ended,
            ringing: false,
            overshootPastM: 1300,
          ),
        ),
      );
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _frames(tester, 10);
    expect(uri(h), '/overshoot?trip=trip-1&past=1300&open=1');
    await tester.pump(const Duration(seconds: 20));
    await _frames(tester);
    expect(uri(h), '/overshoot?trip=trip-1&past=1300&open=1');
    expect(bridge.showAlarmScreenCalls, ['trip-1']);
  });

  testWidgets('X5 the end of another trip does not close the safety net', (
    tester,
  ) async {
    final state = ringingState();
    final bridge = FakeCoreBridge();
    final h = await pump(tester, bridge);
    bridge
      ..active = ringingTrip(state)
      ..emit(TripStateUpdateMsg(state: state));
    await tester.pump(const Duration(seconds: 4));
    await _frames(tester);
    expect(uri(h), '/alarm?trip=trip-1');
    bridge.emit(
      TripEndedMsg(
        atMs: 1700000000000,
        trip: FinishedTripMsg(
          tripId: 'other-trip',
          outcome: TripOutcomeMsg.cancelled,
          endReason: EndReasonMsg.userStop,
          endedAtMs: 1700000000000,
          startedAtMs: 1699990000000,
          snoozeCount: 0,
          travelledM: 0,
          vehicleGuess: VehicleKindMsg.unknown,
        ),
      ),
    );
    await _frames(tester, 10);
    expect(uri(h), '/alarm?trip=trip-1');
    expect(find.text('Vuốt hết thanh để tắt'), findsOneWidget);
  });
}
