// T26 W01-W11, W16-W19, W23-W28: screen 4 (+ states 6) in the whole app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/presentation/tracking_screen.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../tracking_fixtures.dart';
import '../tracking_harness.dart';

final _sim = SimulationMsg(traceAsset: 'train_hn_dh', speedFactor: 60);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('W01 TRACKING, real trip: values, tiles, buttons', (
    tester,
  ) async {
    final h = await pumpTracking(tester);
    expect(h.location, AppRoutes.tracking);
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Còn'), findsOneWidget);
    expect(find.text('148 km'), findsOneWidget);
    expect(find.text('~2 giờ 10 phút'), findsOneWidget);
    expect(find.textContaining('Dự kiến tới lúc '), findsOneWidget);
    expect(find.text('58 km/h'), findsOneWidget);
    expect(find.textContaining('Dự kiến báo lúc '), findsOneWidget);
    expect(
      find.text('Sẽ báo khi còn khoảng 10 phút (tự tính)'),
      findsOneWidget,
    );
    expect(find.text('GPS tốt'), findsOneWidget);
    expect(find.text('±8 m'), findsOneWidget);
    expect(find.text('Pin 80%'), findsOneWidget);
    expect(find.text('Đủ tới nơi'), findsOneWidget);
    expect(find.text('Tai nghe'), findsOneWidget);
    expect(find.text('Đã cắm'), findsOneWidget);
    expect(find.text('Nghe thử báo thức'), findsOneWidget);
    expect(find.text('Dừng theo dõi'), findsOneWidget);
    expect(find.byType(NapBanner), findsNothing);
    expect(find.text('Tắt báo thức — tôi đã tỉnh'), findsNothing);
    expect(find.text('Chuyến giả lập · tốc độ 60×'), findsNothing);
  });

  testWidgets('W02 screen 6: estimated, error, banner, no speed', (
    tester,
  ) async {
    await pumpTracking(tester, bridge: trackingBridge(state: estimatedState()));
    expect(find.text('~148 km'), findsOneWidget);
    expect(find.text('Đang ước tính · sai số ±1,2 km'), findsOneWidget);
    expect(find.text('Mất tín hiệu GPS'), findsOneWidget);
    expect(find.textContaining('dưới 20 phút'), findsOneWidget);
    expect(find.textContaining('km/h'), findsNothing);
    expect(find.text('Mất GPS'), findsOneWidget);
    expect(find.text('Đang ước tính'), findsOneWidget);
  });

  testWidgets('W03 simulated: badge, relative alarm time only', (tester) async {
    await pumpTracking(tester, bridge: trackingBridge(simulation: _sim));
    expect(find.text('Chuyến giả lập · tốc độ 60×'), findsOneWidget);
    expect(find.textContaining('Dự kiến tới lúc'), findsNothing);
    expect(find.textContaining('Dự kiến báo lúc'), findsNothing);
    expect(find.text('Dự kiến báo sau ~2 giờ'), findsOneWidget);
  });

  testWidgets('W04 ACQUIRING, then GpsLost(neverAcquired) shows the banner', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final bridge = trackingBridge(
      state: stateMsg(
        phase: TripPhaseMsg.acquiring,
        gps: GpsStatusMsg.noFixYet,
      ),
    );
    await pumpTracking(tester, bridge: bridge);
    expect(find.text('Đang tìm vị trí…'), findsOneWidget);
    expect(find.text('Đang tìm GPS'), findsOneWidget);
    expect(find.text('Chưa có GPS — báo thức chưa hoạt động'), findsNothing);
    bridge.emit(
      GpsLostMsg(
        tripId: kTripId,
        atMs: kAtMs,
        cause: GpsLostCauseMsg.neverAcquired,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có GPS — báo thức chưa hoạt động'), findsOneWidget);
    final banner = tester.getSemantics(
      find.ancestor(
        of: find.text('Chưa có GPS — báo thức chưa hoạt động'),
        matching: find.byType(NapBanner),
      ),
    );
    expect(banner.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  group('W05 ALARMING, ringing (T10.2 / T10.6 copy)', () {
    for (final (reason, text) in [
      (
        AlarmReasonMsg.fallback,
        'Báo thức dự phòng — có thể sắp tới Ga Đồng Hới. Mở ứng dụng để xem '
            'còn bao xa',
      ),
      (AlarmReasonMsg.distance, 'Còn khoảng 900 m tới Ga Đồng Hới'),
      (
        AlarmReasonMsg.gpsLost,
        'Mất tín hiệu vị trí — có thể sắp tới Ga Đồng Hới. Mở ứng dụng để xem '
            'còn bao xa',
      ),
    ]) {
      testWidgets(reason.name, (tester) async {
        await pumpTracking(
          tester,
          bridge: trackingBridge(
            state: stateMsg(
              phase: TripPhaseMsg.alarming,
              alarmRinging: true,
              alarmReason: reason,
              distanceM: 900,
            ),
          ),
        );
        expect(find.text('Đang báo thức'), findsOneWidget);
        expect(find.text('Tắt trên màn hình báo thức.'), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.text('Tắt báo thức — tôi đã tỉnh'), findsNothing);
        expect(find.text('Nghe thử báo thức'), findsNothing);
      });
    }
  });

  testWidgets('W06 silenced alarm: dismiss, locked while waiting, ended', (
    tester,
  ) async {
    final bridge = trackingBridge(
      state: stateMsg(
        phase: TripPhaseMsg.alarming,
        alarmReason: AlarmReasonMsg.time,
        etaS: 600,
      ),
    )..actionGate = Completer<void>();
    final h = await pumpTracking(tester, bridge: bridge);
    expect(find.text('Báo thức đã tự ngừng'), findsOneWidget);
    await tester.tap(find.text('Tắt báo thức — tôi đã tỉnh'));
    await tester.pump();
    await tester.tap(find.text('Tắt báo thức — tôi đã tỉnh'));
    await tester.pump();
    expect(bridge.dismissCalls, [kTripId]);
    final button = tester.widget<NapButton>(
      find.widgetWithText(NapButton, 'Tắt báo thức — tôi đã tỉnh'),
    );
    expect(button.onPressed, isNull);
    bridge.actionGate!.complete();
    await tester.pump();
    bridge.emit(endedMsg());
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(
      find.text('Đã tắt báo thức. Chúc bạn xuống xe an toàn.'),
      findsOneWidget,
    );
  });

  testWidgets('W07 SNOOZED countdown; the 1 s timer stops after it', (
    tester,
  ) async {
    final bridge = trackingBridge(
      state: stateMsg(
        phase: TripPhaseMsg.snoozed,
        snoozeUntilMs: kAtMs + 1000 + 45000,
      ),
    );
    await pumpTracking(tester, bridge: bridge);
    expect(find.text('Đang báo lại'), findsOneWidget);
    expect(find.text('Báo lại sau 0:45'), findsOneWidget);
    expect(find.text('Tắt báo thức — tôi đã tỉnh'), findsOneWidget);
    for (final s in ['0:44', '0:43']) {
      trackingNowMs += 1000;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Báo lại sau $s'), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Báo lại sau 43 giây'), findsOneWidget);
    await emitState(
      tester,
      bridge,
      stateMsg(atMs: kAtMs + 3000, phase: TripPhaseMsg.alarming),
    );
    final before = trackingNowMs;
    trackingNowMs += 5000;
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Đang báo lại'), findsNothing);
    expect(trackingNowMs, before + 5000);
  });

  testWidgets('W08 OVERSHOT ringing', (tester) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(
        state: stateMsg(
          phase: TripPhaseMsg.overshot,
          alarmRinging: true,
          overshootPastM: 1350,
        ),
      ),
    );
    expect(find.text('Đã qua điểm đến'), findsOneWidget);
    expect(find.text('Đã qua 1,4 km'), findsOneWidget);
    expect(find.text('Tắt báo thức — tôi đã tỉnh'), findsNothing);
  });

  testWidgets('W09 stop asks first; confirmed stop ends the trip', (
    tester,
  ) async {
    final bridge = trackingBridge();
    final h = await pumpTracking(tester, bridge: bridge);
    await _tap(tester, find.text('Dừng theo dõi'));
    expect(find.text('Dừng theo dõi chuyến này?'), findsOneWidget);
    expect(
      find.text('NapStop sẽ không báo thức cho chuyến tới Ga Đồng Hới.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Tiếp tục theo dõi'));
    expect(bridge.stopTripCalls, isEmpty);

    await _tap(tester, find.text('Dừng theo dõi'));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Dừng theo dõi'),
      ),
    );
    expect(bridge.stopTripCalls, [kTripId]);
    bridge.emit(
      endedMsg(
        outcome: TripOutcomeMsg.cancelled,
        endReason: EndReasonMsg.userStop,
      ),
    );
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(find.text('Đã dừng theo dõi.'), findsOneWidget);
  });

  testWidgets('W10 stop fails: snack bar, still on screen 4', (tester) async {
    final bridge = trackingBridge()..stopTripError = channelError();
    final h = await pumpTracking(tester, bridge: bridge);
    await _tap(tester, find.text('Dừng theo dõi'));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Dừng theo dõi'),
      ),
    );
    expect(find.text('Chưa thực hiện được. Thử lại.'), findsOneWidget);
    expect(h.location, AppRoutes.tracking);
  });

  testWidgets('W11 sound test: 10 s, stop on tap, stop when hidden', (
    tester,
  ) async {
    final bridge = trackingBridge();
    await pumpTracking(tester, bridge: bridge);
    await _tap(tester, find.text('Nghe thử báo thức'));
    expect(bridge.previewSoundCalls.single, (soundId: 'default', volume: 0.8));
    expect(find.text('Dừng nghe thử'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Nghe thử báo thức'), findsOneWidget);
    expect(bridge.callCount('stopPreview'), 0, reason: 'native stops itself');

    await _tap(tester, find.text('Nghe thử báo thức'));
    await _tap(tester, find.text('Dừng nghe thử'));
    expect(bridge.callCount('stopPreview'), 1);

    await _tap(tester, find.text('Nghe thử báo thức'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(bridge.callCount('stopPreview'), 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });

  testWidgets('W11 vibrate-only trip: no sound test', (tester) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(config: configMsg(alarm: alarmMsg(volume: 0))),
    );
    expect(find.text('Nghe thử báo thức'), findsNothing);
    expect(find.text('Báo thức'), findsNothing, reason: 'headphones known');
  });

  testWidgets('W16 permission and fallback banners open settings', (
    tester,
  ) async {
    final bridge = trackingBridge(state: w01State().copyWithFallbackFailed())
      ..permissions = androidPermissions(
        precise: PermissionStateMsg.denied,
        locationServicesEnabled: false,
      );
    await pumpTracking(tester, bridge: bridge);
    expect(find.text('Mất quyền'), findsOneWidget);
    expect(
      find.text('Mất quyền vị trí — mở Cài đặt để bật lại'),
      findsOneWidget,
    );
    expect(
      find.text('Định vị đang tắt — bật lại để báo đúng lúc'),
      findsOneWidget,
    );
    expect(
      find.text('Chưa đặt được báo thức dự phòng. Mở Cài đặt để cấp quyền.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Mở Cài đặt').first);
    await _tap(tester, find.text('Bật định vị'));
    await _tap(tester, find.text('Mở Cài đặt').last);
    expect(bridge.openSettingsCalls, [
      SettingsTargetMsg.appDetails,
      SettingsTargetMsg.locationServices,
      SettingsTargetMsg.exactAlarm,
    ]);
  });

  testWidgets('W17 a real view older than 3 min says so', (tester) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(state: w01State(atMs: kAtMs + 1000 - 360000)),
    );
    expect(find.text('Cập nhật 6 phút trước'), findsOneWidget);
  });

  group('W18 end, no trip, error', () {
    testWidgets('ENDED view (cancelled) → home + stopped', (tester) async {
      final bridge = trackingBridge();
      final h = await pumpTracking(tester, bridge: bridge);
      await emitState(
        tester,
        bridge,
        stateMsg(
          atMs: kAtMs + 5,
          phase: TripPhaseMsg.ended,
          outcome: TripOutcomeMsg.cancelled,
        ),
      );
      // No TripEnded event follows: home after kEndReasonWait.
      await tester.pump(kEndReasonWait);
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.home);
      expect(find.text('Đã dừng theo dõi.'), findsOneWidget);
    });

    testWidgets('no trip → home, no snack bar', (tester) async {
      final h = await pumpTracking(tester, bridge: FakeCoreBridge());
      expect(h.location, AppRoutes.home);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('read error → message, retry reads again', (tester) async {
      final bridge = FakeCoreBridge()..currentTripError = channelError();
      final h = await pumpTracking(tester, bridge: bridge);
      expect(find.text('Không đọc được chuyến đi.'), findsOneWidget);
      expect(h.location, AppRoutes.tracking);
      final reads = bridge.callCount('currentTrip');
      bridge
        ..currentTripError = null
        ..active = activeMsg(state: w01State());
      await _tap(tester, find.text('Thử lại'));
      expect(bridge.callCount('currentTrip'), reads + 1);
      expect(find.text('148 km'), findsOneWidget);
    });
  });

  testWidgets('W19 Back (system and header) goes home, trip untouched', (
    tester,
  ) async {
    final bridge = trackingBridge();
    final h = await pumpTracking(tester, bridge: bridge);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    h.router.go(AppRoutes.tracking);
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.home);
    expect(bridge.stopTripCalls, isEmpty);
  });

  testWidgets('W23 no history call from screen 4 (D15)', (tester) async {
    final bridge = trackingBridge();
    await pumpTracking(tester, bridge: bridge);
    bridge.emit(endedMsg());
    await tester.pumpAndSettle();
    expect(bridge.calls, isNot(contains('pendingFinishedTrips')));
    expect(bridge.calls, isNot(contains('ackFinishedTrips')));
  });

  testWidgets('W24 crash keys only on change; none at the end', (tester) async {
    final bridge = trackingBridge();
    await pumpTracking(tester, bridge: bridge);
    await tester.pump();
    expect(trackingCrash.keys['trip_phase'], 'tracking');
    expect(trackingCrash.keys['sampling_tier'], 'sparse');
    expect(trackingCrash.keys['trip_active'], true);
    final before = trackingCrash.calls.length;
    await emitState(tester, bridge, w01State(atMs: kAtMs + 10));
    await tester.pump();
    expect(trackingCrash.calls.length, before, reason: 'nothing changed');
    await emitState(
      tester,
      bridge,
      stateMsg(atMs: kAtMs + 20, samplingTier: SamplingTierMsg.dense),
    );
    await tester.pump();
    expect(trackingCrash.keys['sampling_tier'], 'dense');
    expect(trackingCrash.calls.length, before + 1);
    await emitState(
      tester,
      bridge,
      stateMsg(
        atMs: kAtMs + 30,
        phase: TripPhaseMsg.alarming,
        samplingTier: SamplingTierMsg.dense,
      ),
    );
    await tester.pump();
    expect(trackingCrash.keys['trip_phase'], 'alarming');
    bridge.emit(endedMsg());
    await tester.pumpAndSettle();
    expect(trackingCrash.keys, {
      'trip_active': false,
      'trip_phase': 'none',
      'sampling_tier': 'none',
    });
    for (final text in trackingCrash.allText) {
      expect(text, isNot(contains('Đồng Hới')));
      expect(text, isNot(contains('148')));
    }
  });

  testWidgets('W27 device status every 30 s while visible', (tester) async {
    final bridge = trackingBridge();
    await pumpTracking(tester, bridge: bridge);
    expect(bridge.callCount('deviceStatus'), 1);
    await tester.pump(const Duration(seconds: 95));
    expect(bridge.callCount('deviceStatus'), 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 120));
    expect(bridge.callCount('deviceStatus'), 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(bridge.callCount('deviceStatus'), 5, reason: 'read again on show');
    expect(bridge.callCount('permissionStatus'), 2);
  });

  testWidgets('stop sheet closes by itself when the trip ends (review #5)', (
    tester,
  ) async {
    final bridge = trackingBridge();
    final h = await pumpTracking(tester, bridge: bridge);
    await _tap(tester, find.text('Dừng theo dõi'));
    expect(find.text('Dừng theo dõi chuyến này?'), findsOneWidget);
    bridge.emit(endedMsg());
    await tester.pumpAndSettle();
    expect(find.text('Dừng theo dõi chuyến này?'), findsNothing);
    expect(h.location, AppRoutes.home);
    expect(bridge.stopTripCalls, isEmpty);
  });

  testWidgets('no device status poll while covered by /alarm (review #7)', (
    tester,
  ) async {
    final bridge = trackingBridge();
    final h = await pumpTracking(tester, bridge: bridge);
    unawaited(h.router.push<void>('${AppRoutes.alarm}?trip=$kTripId'));
    await tester.pumpAndSettle();
    final covered = bridge.callCount('deviceStatus');
    await tester.pump(const Duration(seconds: 95));
    expect(bridge.callCount('deviceStatus'), covered);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(bridge.callCount('deviceStatus'), covered + 1, reason: 'on top');
    await tester.pump(const Duration(seconds: 31));
    expect(bridge.callCount('deviceStatus'), covered + 2);
  });

  group('W28 T27 contract: /alarm above screen 4', () {
    testWidgets('ended while covered: nothing; after pop: home once', (
      tester,
    ) async {
      final bridge = trackingBridge();
      final h = await pumpTracking(tester, bridge: bridge);
      unawaited(h.router.push<void>('${AppRoutes.alarm}?trip=$kTripId'));
      await tester.pumpAndSettle();
      bridge.emit(endedMsg());
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.alarm);
      expect(find.byType(SnackBar), findsNothing);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.home);
      expect(
        find.text('Đã tắt báo thức. Chúc bạn xuống xe an toàn.'),
        findsOneWidget,
      );
    });

    testWidgets('replaced by /overshoot: stays there', (tester) async {
      final bridge = trackingBridge();
      final h = await pumpTracking(tester, bridge: bridge);
      unawaited(h.router.push<void>('${AppRoutes.alarm}?trip=$kTripId'));
      await tester.pumpAndSettle();
      bridge.emit(endedMsg());
      await tester.pumpAndSettle();
      h.router.go('${AppRoutes.overshoot}?trip=$kTripId&past=1500&open=1');
      await tester.pumpAndSettle();
      expect(h.router.state.uri.path, AppRoutes.overshoot);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('W26 text scale 2.0', () {
    for (final size in const [Size(320, 568), Size(390, 844)]) {
      for (final (name, state) in [
        ('W01', w01State()),
        ('W02', estimatedState()),
        (
          'W05',
          stateMsg(
            phase: TripPhaseMsg.alarming,
            alarmRinging: true,
            alarmReason: AlarmReasonMsg.fallback,
            distanceM: 900,
          ),
        ),
        (
          'banners',
          stateMsg(
            phase: TripPhaseMsg.acquiring,
            gps: GpsStatusMsg.noFixYet,
            locationCause: AvailabilityCauseMsg.permissionRevoked,
            fallbackStatus: FallbackStatusMsg.failed,
            batteryRisk: true,
            batteryPct: 18,
          ),
        ),
      ]) {
        testWidgets('$name ${size.width.toInt()}x${size.height.toInt()}', (
          tester,
        ) async {
          await pumpTracking(
            tester,
            bridge: trackingBridge(state: state),
            size: size,
            textScale: 2,
          );
          // The battery sheet may open by itself: check it as it is first
          // (review T26 #3), then close it.
          expect(tester.takeException(), isNull);
          if (find.byType(BottomSheet).evaluate().isNotEmpty) {
            final apply = find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Áp dụng'),
            );
            await tester.ensureVisible(apply);
            await tester.pumpAndSettle();
            expect(apply.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _tap(tester, find.text('Để sau'));
          }
          expect(tester.takeException(), isNull);
          final stop = find.widgetWithText(NapButton, 'Dừng theo dõi');
          expect(stop.hitTestable(), findsOneWidget);
          final tiles = find.byType(NapStatusTile);
          expect(
            tester.getTopLeft(tiles.at(0)).dx,
            tester.getTopLeft(tiles.at(1)).dx,
            reason: 'tiles stacked',
          );
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('W25 a11y', () {
    for (final theme in NapThemeKind.values.where(
      (t) => t == NapThemeKind.light || t == NapThemeKind.dark,
    )) {
      for (final (name, state) in [
        ('W01', w01State()),
        ('W02', estimatedState()),
        (
          'W05',
          stateMsg(
            phase: TripPhaseMsg.alarming,
            alarmRinging: true,
            alarmReason: AlarmReasonMsg.fallback,
          ),
        ),
      ]) {
        testWidgets('$name ${theme.name}', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpTracking(
            tester,
            bridge: trackingBridge(state: state),
            theme: theme,
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          if (name == 'W01') {
            expect(
              find.bySemanticsLabel('Đã đi 62%. Mốc báo ở 97%.'),
              findsOneWidget,
            );
            expect(
              find.bySemanticsLabel(RegExp(r'GPS tốt\s+±8 m')),
              findsOneWidget,
            );
          }
          handle.dispose();
        });
      }
    }
  });
}

extension on TripStateMsg {
  TripStateMsg copyWithFallbackFailed() =>
      this..fallbackStatus = FallbackStatusMsg.failed;
}
