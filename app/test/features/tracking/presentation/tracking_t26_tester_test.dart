// T26 tester (outside the spec list): risk areas of screen 4 that decide
// whether the user sees, in time, that the alarm may not wake them.
//   X01 ENDED view and TripEnded arrive in two frames (review #6)
//   X02 "Chưa có GPS" appears after 120 s of ACQUIRING with no new view
//   X03 "Cập nhật X phút trước" appears while no view arrives (D8 b)
//   X04 gpsLostAlarmEtaS of the trip drives the screen 6 copy (D11)
//   X05 screen 7 closes by itself when the alarm starts (phase change)
//   X06 resume on /home with an ALARMING (silenced) / SNOOZED trip → screen 4
//   X07 ALARMING while estimating: "Còn ~…", no speed
//   X08 Back while a silenced alarm waits: no dismiss / stop sent
//   X09 screen 7 open while the battery drops: the promised "Báo sớm hơn"
//       percent must follow the level the engine will use (T10 §4.9)
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
import '../tracking_harness.dart';

const _noGps = 'Chưa có GPS — báo thức chưa hoạt động';

/// Moves the harness clock and the fake timers together.
Future<void> _advance(WidgetTester tester, Duration d) async {
  trackingNowMs += d.inMilliseconds;
  await tester.pump(d);
}

void main() {
  testWidgets('X01 ENDED view, one frame, then TripEnded(dismissed): '
      'the snack bar says the alarm was turned off', (tester) async {
    final bridge = trackingBridge(
      state: stateMsg(
        phase: TripPhaseMsg.alarming,
        alarmReason: AlarmReasonMsg.distance,
        distanceM: 900,
      ),
    );
    final h = await pumpTracking(tester, bridge: bridge);
    // Native order (T10 §2.3): the view of the Step, then its event. On a
    // device the two platform messages may land in different frames.
    bridge.emit(
      TripStateUpdateMsg(
        state: stateMsg(
          atMs: kAtMs + 500,
          phase: TripPhaseMsg.ended,
          outcome: TripOutcomeMsg.onTime,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    bridge.emit(endedMsg());
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(
      find.text('Đã tắt báo thức. Chúc bạn xuống xe an toàn.'),
      findsOneWidget,
    );
    expect(find.text('Chuyến đi đã kết thúc.'), findsNothing);
    // Bug #1 of docs/test-reports/T26.md: remove the skip with the fix.
  });

  testWidgets('X02 ACQUIRING with no new view: the no-GPS warning shows by '
      '120 s (+ one 30 s poll at most)', (tester) async {
    final bridge = trackingBridge(
      state: stateMsg(
        atMs: kAtMs + 1000,
        phase: TripPhaseMsg.acquiring,
        gps: GpsStatusMsg.noFixYet,
      ),
    );
    await pumpTracking(tester, bridge: bridge);
    expect(find.text(_noGps), findsNothing);
    await _advance(tester, const Duration(seconds: 90));
    expect(find.text(_noGps), findsNothing, reason: '90 s < 120 s');
    await _advance(tester, const Duration(seconds: 60));
    expect(find.text(_noGps), findsOneWidget, reason: '150 s ≥ 120 s + poll');
  });

  testWidgets('X03 real trip, views stop coming: "Cập nhật 3 phút trước" '
      'shows within one poll after 3 min', (tester) async {
    final bridge = trackingBridge(state: w01State(atMs: kAtMs + 1000));
    await pumpTracking(tester, bridge: bridge);
    expect(find.textContaining('phút trước'), findsNothing);
    await _advance(tester, const Duration(seconds: 150));
    expect(find.textContaining('phút trước'), findsNothing);
    await _advance(tester, const Duration(seconds: 60));
    expect(find.text('Cập nhật 3 phút trước'), findsOneWidget);
  });

  testWidgets('X04 screen 6 copy uses gpsLostAlarmEtaS of the trip (D11)', (
    tester,
  ) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(
        state: estimatedState(),
        config: configMsg(engineParamsJson: '{"gpsLostAlarmEtaS":900}'),
      ),
    );
    expect(
      find.text(
        'NapStop đang ước tính theo tốc độ cuối, sai số ±1,2 km. Còn dưới 15 '
        'phút là báo thức kêu luôn.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('km/h'), findsNothing);
  });

  testWidgets('X05 screen 7 open, the alarm starts: the sheet closes and '
      '"Đang báo thức" is on screen', (tester) async {
    final bridge = trackingBridge(
      state: stateMsg(
        distanceM: 60000,
        etaS: 3600,
        batteryPct: 18,
        batteryRisk: true,
      ),
    );
    await pumpTracking(tester, bridge: bridge);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    bridge.emit(
      TripStateUpdateMsg(
        state: stateMsg(
          atMs: kAtMs + 10,
          phase: TripPhaseMsg.alarming,
          alarmRinging: true,
          alarmReason: AlarmReasonMsg.lowBattery,
          batteryPct: 5,
          batteryRisk: true,
          distanceM: 30000,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Đang báo thức'), findsOneWidget);
    expect(find.textContaining('5%'), findsWidgets);
    expect(bridge.batteryChoiceCalls, isEmpty);
  });

  group('X06 resume on /home with a trip that needs the user', () {
    for (final (name, state) in [
      (
        'ALARMING silenced',
        stateMsg(
          phase: TripPhaseMsg.alarming,
          alarmReason: AlarmReasonMsg.time,
          etaS: 600,
        ),
      ),
      (
        'SNOOZED',
        stateMsg(phase: TripPhaseMsg.snoozed, snoozeUntilMs: kAtMs + 45000),
      ),
      (
        'ACQUIRING',
        stateMsg(phase: TripPhaseMsg.acquiring, gps: GpsStatusMsg.noFixYet),
      ),
    ]) {
      testWidgets(name, (tester) async {
        tester.platformDispatcher
          ..localesTestValue = const [Locale('vi', 'VN')]
          ..localeTestValue = const Locale('vi', 'VN');
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final bridge = FakeCoreBridge();
        final h = await pumpAppHarness(tester, bridge: bridge, settle: false);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: const NapStopApp(flavor: AppFlavor.dev),
          ),
        );
        await tester.pumpAndSettle();
        expect(h.location, AppRoutes.home);
        bridge.active = activeMsg(state: state);
        tester.binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(h.location, AppRoutes.tracking);
        if (state.phase != TripPhaseMsg.acquiring) {
          expect(find.text('Tắt báo thức — tôi đã tỉnh'), findsOneWidget);
        }
      });
    }
  });

  testWidgets('X07 ALARMING while estimating: "~" distance, no speed', (
    tester,
  ) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(
        state: stateMsg(
          phase: TripPhaseMsg.alarming,
          alarmRinging: true,
          alarmReason: AlarmReasonMsg.gpsLost,
          gps: GpsStatusMsg.lost,
          isEstimated: true,
          distanceM: 9000,
          distanceErrorM: 1500,
          speedKmh: 60,
        ),
      ),
    );
    expect(find.text('~9 km'), findsOneWidget);
    expect(find.textContaining('km/h'), findsNothing);
    expect(find.text('Tắt báo thức — tôi đã tỉnh'), findsNothing);
  });

  testWidgets('X08 Back with a silenced alarm: home, nothing sent', (
    tester,
  ) async {
    final bridge = trackingBridge(
      state: stateMsg(
        phase: TripPhaseMsg.alarming,
        alarmReason: AlarmReasonMsg.time,
        etaS: 600,
      ),
    );
    final h = await pumpTracking(tester, bridge: bridge);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(bridge.dismissCalls, isEmpty);
    expect(bridge.stopTripCalls, isEmpty);
  });

  testWidgets('X09 screen 7 open, battery 12 % → 11 %: "Báo sớm hơn" '
      'promises what the engine sets (level − 1 at Apply)', (tester) async {
    TripStateMsg risk(int pct, int atMs) => stateMsg(
      atMs: atMs,
      distanceM: 60000,
      etaS: 3600,
      batteryPct: pct,
      batteryRisk: true,
    );
    final bridge = trackingBridge(state: risk(12, kAtMs));
    await pumpTracking(tester, bridge: bridge);
    await tester.pumpAndSettle();
    expect(find.text('Báo sớm hơn, khi pin còn 11%'), findsOneWidget);
    bridge.emit(TripStateUpdateMsg(state: risk(11, kAtMs + 60000)));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    // Engine (BatteryRule.kt): choicePct = max(5, min(15, level − 1)) with
    // the level at Apply time = 11 → 10 %.
    expect(find.text('Báo sớm hơn, khi pin còn 10%'), findsOneWidget);
    expect(
      find.text('Pin còn 11%. Chọn cách để NapStop vẫn kịp đánh thức bạn.'),
      findsWidgets,
    );
    // Bug #2 of docs/test-reports/T26.md: remove the skip with the fix.
  });
}
