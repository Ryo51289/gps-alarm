// T25 I01, I02: screen 3 starts a trip through the real platform channels
// (Android stub of T14), on an emulator or device, dev flavor. Forces the vi
// locale. Unlock the screen first:
//   flutter test integration_test/alarm_settings_start_test.dart -d <device-id>
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_screen.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/main.dart' as app;

const TripDraft _dongHoi = TripDraft(
  destination: TripDestination(
    name: 'Ga Đồng Hới',
    lat: 17.4783,
    lng: 106.6003,
    kind: DestinationKind.train,
    detail: 'Quảng Trị',
  ),
  source: DestinationSource.station,
);

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Starts the app on screen 1 and returns its bridge, with no trip running.
Future<CoreBridge> _launch(WidgetTester tester) async {
  tester.platformDispatcher
    ..localesTestValue = const [Locale('vi', 'VN')]
    ..localeTestValue = const Locale('vi', 'VN');
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await app.main();
  await _pumpUntil(tester, find.byType(HomeScreen));
  final bridge = ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).read(coreBridgeProvider);
  final running = await bridge.currentTrip();
  if (running != null) {
    await bridge.stopTrip(running.config.tripId);
  }
  return bridge;
}

Future<void> _openScreen3(WidgetTester tester, Object extra) async {
  unawaited(
    GoRouter.of(tester.element(find.byType(HomeScreen)))
        .push<void>(AppRoutes.alarmSettings, extra: extra),
  );
  await _pumpUntil(tester, find.byType(AlarmSettingsScreen));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('I01 distance 2 km: screen 4, same trip on the native side', (
    tester,
  ) async {
    final bridge = await _launch(tester);
    await _openScreen3(tester, _dongHoi);
    await _tap(tester, find.text('Khoảng cách'));
    await _tap(tester, find.text('2 km'));
    await _tap(tester, find.text('Bắt đầu theo dõi'));
    await _pumpUntil(tester, find.text('Đang theo dõi'));
    expect(find.byType(AlarmSettingsScreen), findsNothing);

    final trip = await bridge.currentTrip();
    expect(trip, isNotNull);
    final config = trip!.config;
    expect(config.tripId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(config.destinationName, 'Ga Đồng Hới');
    expect(config.mode, AlarmModeMsg.distance);
    expect(config.distanceThresholdM, 2000);
    expect(config.timeThresholdMin, isNull);
    expect(config.vehicleHint, VehicleKindMsg.train);
    expect(config.engineParamsJson, isNull);
    await bridge.stopTrip(config.tripId);
  });

  testWidgets('I02 time 30 already in the alarm zone: rings at once', (
    tester,
  ) async {
    final bridge = await _launch(tester);
    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);
    await _openScreen3(
      tester,
      AlarmSettingsArgs(
        draft: _dongHoi,
        simulation: SimulationMsg(
          traceAsset: StubTraces.normal,
          speedFactor: 60,
        ),
      ),
    );
    expect(find.text('Chuyến giả lập · tốc độ 60×'), findsOneWidget);
    await _tap(tester, find.text('Thời gian'));
    await _tap(tester, find.text('30'));
    await _tap(tester, find.text('Bắt đầu theo dõi'));
    final started = DateTime.now();
    AlarmMsg? alarm;
    while (alarm == null &&
        DateTime.now().difference(started) < const Duration(seconds: 3)) {
      await tester.pump(const Duration(milliseconds: 100));
      alarm = received.whereType<AlarmMsg>().firstOrNull;
    }
    expect(alarm, isNotNull, reason: 'AlarmMsg within 3 s');
    expect(alarm!.reason, AlarmReasonMsg.time);
    expect(alarm.ringNow, isTrue);
    final trip = await bridge.currentTrip();
    if (trip != null) {
      await bridge.stopTrip(trip.config.tripId);
    }
  });
}
