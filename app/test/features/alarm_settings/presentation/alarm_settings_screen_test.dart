// T25 W01-W25 (+ muted alarm and currentTrip carry-overs): screen 3.
import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_screen.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/equal_chip_row.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/start_bar.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/nap_test_app.dart';
import '../../../helpers/trip_fixtures.dart';
import '../helpers/alarm_settings_harness.dart';

const _warningCoach1km =
    'Xe khách chạy khoảng 60 km/h: báo ở 1 km chỉ còn khoảng 1 phút để '
    'xuống. Nên chọn Thời gian hoặc Thông minh.';

Finder _warning() => find.textContaining('km/h: báo ở');

SemanticsNode _semanticsOf(WidgetTester tester, Finder f) =>
    tester.getSemantics(f);

Future<void> _start(WidgetTester tester) =>
    tapVisible(tester, find.text('Bắt đầu theo dõi'));

Future<void> hangAndTimeOutAt(WidgetTester tester, String start) async {
  await tester.ensureVisible(find.text(start));
  await tester.pumpAndSettle();
  await tester.tap(find.text(start));
  await tester.pump(kStartTripTimeout);
  await tester.pumpAndSettle();
}

/// The chip label [label] is neither ellipsized nor broken inside a word:
/// every word lies on a single line (T25.1 review #3: "50 / 0 m" has 2
/// lines for 2 words, so counting lines is not enough).
void expectLabelWhole(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: chip(label), matching: find.text(label)),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);
  var start = 0;
  for (final word in label.split(' ')) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    );
    final lineTops = {for (final b in boxes) b.top.round()};
    expect(lineTops, hasLength(1), reason: '"$word" of "$label" is split');
    start += word.length + 1;
  }
}

void main() {
  testWidgets('W01 defaults: smart, pre-alert, ring, swipe, snooze', (
    tester,
  ) async {
    final h = await pumpAlarmSettings(tester, extra: kDraftCoach);
    expect(h.location, AppRoutes.alarmSettings);
    expect(find.text('Cài đặt báo thức'), findsOneWidget);
    expect(find.text('Bến xe Mỹ Đình'), findsOneWidget);
    expect(find.text('Bến xe khách · Hà Nội'), findsOneWidget);
    expect(
      _semanticsOf(tester, find.text('Thông minh')),
      isSemantics(label: 'Thông minh', isSelected: true, isButton: true),
    );
    expect(find.text('App tự chọn lúc báo'), findsOneWidget);
    expect(find.textContaining('khoảng 10 phút để tỉnh ngủ'), findsOneWidget);
    expect(summaryText('còn khoảng 10 phút (tự tính)'), findsOneWidget);
    expect(
      find.text('Rung khẽ khi còn 30 phút, rồi mới báo chính'),
      findsOneWidget,
    );
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isTrue,
      reason: 'pre-alert on by default',
    );
    expect(
      _semanticsOf(tester, find.widgetWithText(NapOptionCard, 'Chuông + rung')),
      isSemantics(label: 'Chuông + rung', isChecked: true),
    );
    expect(
      find.text('Kêu to cả khi máy để im lặng, âm lượng tăng dần.'),
      findsOneWidget,
    );
    expect(
      _semanticsOf(tester, chip('Vuốt hết thanh')),
      isSemantics(label: 'Vuốt hết thanh', isSelected: true),
    );
    expect(find.text('Báo lại tối đa 1 lần, sau 1 phút'), findsOneWidget);
    expect(find.byType(NapBanner), findsNothing);
    expect(h.reader.calls, 1);
    expect(h.bridge.callCount('startTrip'), 0);
  });

  testWidgets('W02 distance: 1 km, chip, slider, coach warning', (
    tester,
  ) async {
    await pumpAlarmSettings(tester, extra: kDraftCoach);
    await tapVisible(tester, find.text('Khoảng cách'));
    expect(bigValue('1 km'), findsOneWidget);
    expect(find.text('Còn cách'), findsOneWidget);
    expect(
      _semanticsOf(tester, chip('1 km')),
      isSemantics(label: '1 km', isSelected: true),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1000);
    expect(find.text(_warningCoach1km), findsOneWidget);
    expect(summaryText('còn 1 km'), findsOneWidget);
  });

  testWidgets('W03 chip 5 km: no warning, summary, pre-alert 25 km', (
    tester,
  ) async {
    await pumpAlarmSettings(tester, extra: kDraftCoach);
    await tapVisible(tester, find.text('Khoảng cách'));
    await tapVisible(tester, chip('5 km'));
    expect(_warning(), findsNothing);
    expect(summaryText('còn 5 km'), findsOneWidget);
    expect(
      find.text('Rung khẽ khi còn 25 km, rồi mới báo chính'),
      findsOneWidget,
    );
    expect(bigValue('5 km'), findsOneWidget);
  });

  testWidgets('W04 train 3600/3700, bus 1300/1400', (tester) async {
    await pumpAlarmSettings(tester);
    await tapVisible(tester, find.text('Khoảng cách'));
    await slideTo(tester, 3600);
    expect(bigValue('3,6 km'), findsOneWidget);
    expect(find.textContaining('Tàu chạy khoảng 55 km/h'), findsOneWidget);
    expect(find.textContaining('khoảng 3 phút để xuống'), findsOneWidget);
    await slideTo(tester, 3700);
    expect(_warning(), findsNothing);
  });

  testWidgets('W04 bus 1300 / 1400', (tester) async {
    await pumpAlarmSettings(tester, extra: kDraftBus);
    await tapVisible(tester, find.text('Khoảng cách'));
    await slideTo(tester, 1300);
    expect(find.textContaining('Xe buýt chạy khoảng 20 km/h'), findsOneWidget);
    await slideTo(tester, 1400);
    expect(_warning(), findsNothing);
  });

  testWidgets('W05 Places (unknown vehicle): 3900 / 4000', (tester) async {
    await pumpAlarmSettings(tester, extra: kDraftPlaces);
    expect(find.text('Đống Đa, Hà Nội'), findsOneWidget);
    await tapVisible(tester, find.text('Khoảng cách'));
    await slideTo(tester, 3900);
    expect(find.textContaining('Xe chạy khoảng 60 km/h'), findsOneWidget);
    await slideTo(tester, 4000);
    expect(_warning(), findsNothing);
  });

  testWidgets('slider values snap to 100 m', (tester) async {
    await pumpAlarmSettings(tester);
    await tapVisible(tester, find.text('Khoảng cách'));
    await slideTo(tester, 1249);
    expect(bigValue('1,2 km'), findsOneWidget);
    await slideTo(tester, 850);
    expect(bigValue('900 m'), findsOneWidget);
  });

  testWidgets('W06 override read once; bus 2400 / 2500', (tester) async {
    final h = await pumpAlarmSettings(
      tester,
      extra: kDraftBus,
      params: const EngineParamsOverride(
        json: '{"shortDistanceWarnS":300,"expectedSpeedKmhBus":30}',
        id: 'abcd1234',
      ),
    );
    await tapVisible(tester, find.text('Khoảng cách'));
    await slideTo(tester, 2400);
    expect(find.textContaining('Xe buýt chạy khoảng 30 km/h'), findsOneWidget);
    await slideTo(tester, 2500);
    expect(_warning(), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tapVisible(tester, find.text('Thời gian'));
      await tapVisible(tester, find.text('Thông minh'));
      await tapVisible(tester, find.text('Khoảng cách'));
    }
    expect(h.reader.calls, 1);
  });

  testWidgets('W07 invalid override values: engine defaults', (tester) async {
    await pumpAlarmSettings(
      tester,
      extra: kDraftCoach,
      params: const EngineParamsOverride(
        json: '{"shortDistanceWarnS":"240x","expectedSpeedKmhCoach":200}',
        id: 'ffff0000',
      ),
    );
    await tapVisible(tester, find.text('Khoảng cách'));
    await slideTo(tester, 3900);
    expect(find.textContaining('Xe khách chạy khoảng 60 km/h'), findsOneWidget);
    await slideTo(tester, 4000);
    expect(_warning(), findsNothing);
  });

  testWidgets('W08 time: 15 by default, 30 skips the pre-alert', (
    tester,
  ) async {
    await pumpAlarmSettings(tester, extra: kDraftCoach);
    await tapVisible(tester, find.text('Thời gian'));
    expect(bigValue('15 phút'), findsOneWidget);
    expect(find.text('Trước'), findsOneWidget);
    expect(
      _semanticsOf(tester, chip('15')),
      isSemantics(label: '15 phút', isSelected: true),
    );
    expect(find.textContaining('Tính theo tốc độ thực tế'), findsOneWidget);
    expect(_warning(), findsNothing);
    await tapVisible(tester, chip('30'));
    expect(
      find.text('Báo trước 30 phút đã đủ sớm, không nhắc thêm'),
      findsOneWidget,
    );
    expect(summaryText('còn 30 phút'), findsOneWidget);
    expect(
      _semanticsOf(tester, chip('30')),
      isSemantics(label: '30 phút', isSelected: true),
    );
  });

  testWidgets('W09 smartTargetS 900: 15 minutes', (tester) async {
    await pumpAlarmSettings(
      tester,
      params: const EngineParamsOverride(
        json: '{"smartTargetS":900}',
        id: '12345678',
      ),
    );
    expect(find.textContaining('khoảng 15 phút để tỉnh ngủ'), findsOneWidget);
    expect(summaryText('còn khoảng 15 phút (tự tính)'), findsOneWidget);
  });

  testWidgets('W10 style hints and one checked card', (tester) async {
    await pumpAlarmSettings(tester);
    await tapVisible(tester, find.text('Chỉ rung'));
    expect(
      find.text('Rung mạnh liên tục. Hợp khi để máy trong túi áo.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Chỉ tai nghe'));
    expect(find.textContaining('Chỉ phát trong tai nghe'), findsOneWidget);
    var checked = 0;
    for (final label in ['Chuông + rung', 'Chỉ rung', 'Chỉ tai nghe']) {
      final node = _semanticsOf(
        tester,
        find.widgetWithText(NapOptionCard, label),
      );
      if (node.flagsCollection.isChecked == CheckedState.isTrue) {
        checked++;
      }
    }
    expect(checked, 1);
    expect(
      _semanticsOf(tester, find.widgetWithText(NapOptionCard, 'Chỉ tai nghe')),
      isSemantics(label: 'Chỉ tai nghe', isChecked: true),
    );
  });

  testWidgets('W11 no ramp-up', (tester) async {
    await pumpAlarmSettings(tester, prefs: {PreferenceKeys.alarmRampUp: 0});
    expect(find.text('Kêu to cả khi máy để im lặng.'), findsOneWidget);
  });

  testWidgets('W11 iOS 26 without AlarmKit: may stay quiet', (tester) async {
    await pumpAlarmSettings(
      tester,
      bridge: FakeCoreBridge(
        permissions: iosPermissions(alarmKit: PermissionStateMsg.denied),
        deviceInfoValue: iosDevice(),
      ),
    );
    expect(
      find.text(
        'Kêu theo âm lượng thông báo. Khi máy để Im lặng có thể không kêu.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('W12 start: config, row, telemetry, screen 4', (tester) async {
    final h = await pumpAlarmSettings(
      tester,
      bridge: FakeCoreBridge(
        deviceStatusValue: deviceStatusMsg(batteryPct: 80),
      ),
      params: const EngineParamsOverride(json: '{"x":1}', id: 'abcd1234'),
    );
    await tapVisible(tester, find.text('Khoảng cách'));
    await tapVisible(tester, chip('2 km'));
    await tapVisible(tester, find.byType(Switch));
    await tapVisible(tester, find.text('Chỉ rung'));
    await tapVisible(tester, chip('Lắc máy'));
    await _start(tester);

    final call = h.bridge.startTripCalls.single;
    final c = call.config;
    expect(c.tripId, kTestTripId);
    expect(c.mode, AlarmModeMsg.distance);
    expect(c.distanceThresholdM, 2000);
    expect(c.timeThresholdMin, isNull);
    expect(c.preAlertEnabled, isFalse);
    expect(c.vehicleHint, VehicleKindMsg.train);
    expect(c.destinationName, 'Ga Đồng Hới');
    expect(c.alarm.volume, 0.0);
    expect(c.alarm.vibration, VibrationMsg.strong);
    expect(c.alarm.preferHeadphones, isFalse);
    expect(c.alarm.dismissMethod, DismissMethodMsg.shake);
    expect(c.alarm.soundId, 'default');
    expect(c.alarm.rampUp, isTrue);
    expect(c.alarm.flash, isFalse);
    expect(c.engineParamsJson, '{"x":1}');
    expect(call.destLat, kGaDongHoi.lat);
    expect(call.destLng, kGaDongHoi.lng);
    expect(call.simulation, isNull);

    final row = await h.app.read(tripsRepositoryProvider).byId(kTestTripId);
    expect(row, isNotNull);
    expect(row!.destination, kGaDongHoi);
    expect(row.alarm.mode, AlarmModeMsg.distance);
    expect(row.alarm.distanceThresholdM, 2000);
    expect(row.startedAtMs, kHarnessNow.millisecondsSinceEpoch);

    final facts = h.reporter.startedFacts.single;
    expect(facts.shortDistanceWarning, isTrue);
    expect(facts.paramsId, 'abcd1234');
    expect(facts.batteryPct, 80);
    expect(h.location, AppRoutes.tracking);
    expect(h.reader.calls, 1);
  });

  testWidgets('W13 starting: one call, label, Back ignored', (tester) async {
    final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
    final h = await pumpAlarmSettings(tester, bridge: bridge);
    await tester.ensureVisible(find.text('Bắt đầu theo dõi'));
    await tester.tap(find.text('Bắt đầu theo dõi'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Đang bắt đầu…'), findsOneWidget);
    await tester.tap(find.text('Đang bắt đầu…'), warnIfMissed: false);
    await tester.pump();
    expect(bridge.callCount('startTrip'), 1);
    // System Back while starting: nothing happens.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(h.location, AppRoutes.alarmSettings);
    // T26: screen 4 is real now and reads the started trip (native snapshot).
    bridge
      ..active = activeTrip(tripId: kTestTripId)
      ..startTripGate!.complete();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.tracking);
    expect(bridge.callCount('startTrip'), 1);
  });

  for (final (name, permissions, device, row, reason) in [
    (
      'location denied',
      androidPermissions(location: LocationAccessMsg.denied),
      androidDevice(),
      'Cho phép dùng vị trí khi dùng ứng dụng',
      TripStartBlockReason.locationDenied,
    ),
    (
      'approximate',
      androidPermissions(precise: PermissionStateMsg.denied),
      androidDevice(),
      'Bật vị trí chính xác',
      TripStartBlockReason.locationApproximate,
    ),
    (
      'services off',
      androidPermissions(locationServicesEnabled: false),
      androidDevice(),
      'Bật định vị của máy',
      TripStartBlockReason.locationServicesOff,
    ),
    (
      'iOS 25 without notifications',
      iosPermissions(notifications: PermissionStateMsg.denied),
      iosDevice(major: 25),
      'Cho phép báo thức hoặc thông báo',
      TripStartBlockReason.noAlarmChannel,
    ),
  ]) {
    testWidgets('W14 blocked: $name', (tester) async {
      final h = await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge(
          permissions: permissions,
          deviceInfoValue: device,
        ),
      );
      await _start(tester);
      expect(find.text('Chưa thể bắt đầu theo dõi'), findsOneWidget);
      expect(find.text(row), findsOneWidget);
      expect(h.bridge.callCount('startTrip'), 0);
      expect(h.reporter.blockedEvents, [(reason, false)]);
      await tapVisible(tester, find.text('Cấp quyền'));
      expect(h.location, AppRoutes.onboarding);
      // Back from screen 0: screen 3 again, nothing started by itself.
      h.app.router.pop();
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.alarmSettings);
      expect(h.bridge.callCount('startTrip'), 0);
    });
  }

  for (final (code, message) in [
    (
      BridgeErrorCode.notForeground,
      'Hãy mở NapStop trên màn hình rồi bấm lại.',
    ),
    (BridgeErrorCode.simulationUnavailable, 'Không mở được chuyến giả lập.'),
    (
      BridgeErrorCode.startFailed,
      'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
    ),
    (
      BridgeErrorCode.invalidConfig,
      'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
    ),
    (
      BridgeErrorCode.internal,
      'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
    ),
  ]) {
    testWidgets('W15 startTrip ${code.wire}: banner', (tester) async {
      final h = await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge()
          ..startTripError = BridgeException(code, rawCode: code.wire),
      );
      await _start(tester);
      expect(find.text(message), findsOneWidget);
      expect(h.location, AppRoutes.alarmSettings);
      // The history row was removed again.
      expect(
        await h.app.read(tripsRepositoryProvider).byId(kTestTripId),
        isNull,
      );
    });
  }

  testWidgets('W15 trip-active: "Xem chuyến" opens the running trip', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..startTripError = const BridgeException(
        BridgeErrorCode.tripActive,
        rawCode: 'trip-active',
      );
    final h = await pumpAlarmSettings(tester, bridge: bridge);
    await _start(tester);
    expect(find.text('Đang có một chuyến được theo dõi.'), findsOneWidget);
    bridge.active = activeTrip(tripId: 't-old');
    await tapVisible(tester, find.text('Xem chuyến'));
    expect(h.location, AppRoutes.tracking);
  });

  testWidgets('W15 trip-active, no trip any more: banner goes away', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..startTripError = const BridgeException(
        BridgeErrorCode.tripActive,
        rawCode: 'trip-active',
      );
    final h = await pumpAlarmSettings(tester, bridge: bridge);
    await _start(tester);
    await tapVisible(tester, find.text('Xem chuyến'));
    expect(find.text('Đang có một chuyến được theo dõi.'), findsNothing);
    expect(h.location, AppRoutes.alarmSettings);
  });

  testWidgets('W15 permission-missing with details: sheet', (tester) async {
    final h = await pumpAlarmSettings(
      tester,
      bridge: FakeCoreBridge()
        ..startTripError = const BridgeException(
          BridgeErrorCode.permissionMissing,
          rawCode: 'permission-missing',
          details: ['precise'],
        ),
    );
    await _start(tester);
    expect(find.text('Bật vị trí chính xác'), findsOneWidget);
    expect(h.reporter.blockedEvents, [
      (TripStartBlockReason.locationApproximate, false),
    ]);
  });

  testWidgets('W15 unexpected error: generic, "Thử lại" starts again', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()..startTripError = StateError('boom');
    final h = await pumpAlarmSettings(tester, bridge: bridge);
    await _start(tester);
    expect(
      find.text('Chưa bắt đầu được theo dõi. Thử lại sau giây lát.'),
      findsOneWidget,
    );
    bridge.startTripError = null;
    await tapVisible(tester, find.text('Thử lại'));
    expect(bridge.callCount('startTrip'), 2);
    expect(h.location, AppRoutes.tracking);
  });

  testWidgets('T22 carry-over: running trip found before startTrip', (
    tester,
  ) async {
    final h = await pumpAlarmSettings(
      tester,
      bridge: FakeCoreBridge(active: activeTrip(tripId: 't-old')),
    );
    await _start(tester);
    expect(find.text('Đang có một chuyến được theo dõi.'), findsOneWidget);
    expect(h.bridge.callCount('startTrip'), 0);
    expect(await h.app.read(tripsRepositoryProvider).byId(kTestTripId), isNull);
    await tapVisible(tester, find.text('Xem chuyến'));
    expect(h.location, AppRoutes.tracking);
  });

  for (final (name, status, params, title) in [
    ('5 %, not charging', deviceStatusMsg(batteryPct: 5), null, 'Pin còn 5%'),
    (
      '5 %, charging',
      deviceStatusMsg(batteryPct: 5, charging: true),
      null,
      null,
    ),
    ('6 %', deviceStatusMsg(batteryPct: 6), null, null),
    (
      'override 10, 8 %',
      deviceStatusMsg(batteryPct: 8),
      '{"lowBatteryAlarmPct":10}',
      'Pin còn 8%',
    ),
    (
      'override 16 (G4), 8 %',
      deviceStatusMsg(batteryPct: 8),
      '{"lowBatteryAlarmPct":16}',
      null,
    ),
    ('unknown', deviceStatusMsg(batteryPct: null), null, null),
  ]) {
    testWidgets('W16 battery $name', (tester) async {
      await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge(deviceStatusValue: status),
        params: params == null
            ? EngineParamsOverride.defaults
            : EngineParamsOverride(json: params, id: 'x'),
      );
      if (title == null) {
        expect(find.textContaining('Pin còn'), findsNothing);
      } else {
        expect(find.text(title), findsOneWidget);
        expect(
          find.text(
            'Máy có thể tắt trước khi tới nơi. Hãy cắm sạc trước khi ngủ.',
          ),
          findsOneWidget,
        );
      }
    });
  }

  for (final (name, status, shown) in [
    (
      'DND total silence (alarmMuted)',
      deviceStatusMsg(
        alarmMuted: true,
        alarmVolumePct: 0,
        interruptionFilter: InterruptionFilterMsg.none,
      ),
      true,
    ),
    (
      'muted, volume unknown',
      deviceStatusMsg(alarmMuted: true, alarmVolumePct: null),
      true,
    ),
    (
      'priority without alarms',
      deviceStatusMsg(
        interruptionFilter: InterruptionFilterMsg.priority,
        priorityAllowsAlarms: false,
      ),
      true,
    ),
    ('normal', deviceStatusMsg(), false),
  ]) {
    testWidgets('T14.1 O1 muted alarm warning: $name', (tester) async {
      final h = await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge(deviceStatusValue: status),
      );
      expect(
        find.text('Báo thức có thể không kêu'),
        shown ? findsOneWidget : findsNothing,
      );
      // A warning, never a blocker.
      await _start(tester);
      expect(h.bridge.callCount('startTrip'), 1);
    });
  }

  testWidgets('muted warning follows the device on resume', (tester) async {
    final bridge = FakeCoreBridge();
    await pumpAlarmSettings(tester, bridge: bridge);
    expect(find.text('Báo thức có thể không kêu'), findsNothing);
    bridge.deviceStatusValue = deviceStatusMsg(alarmMuted: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Báo thức có thể không kêu'), findsOneWidget);
  });

  testWidgets('W17 simulation: banner, passed to startTrip', (tester) async {
    final sim = SimulationMsg(
      traceAsset: SimTraces.busHnBrt01,
      speedFactor: 60,
    );
    final h = await pumpAlarmSettings(
      tester,
      extra: AlarmSettingsArgs(draft: kDraftTrain, simulation: sim),
    );
    expect(find.text('Chuyến giả lập · tốc độ 60×'), findsOneWidget);
    await _start(tester);
    expect(h.bridge.startTripCalls.single.simulation, same(sim));
    expect(h.reporter.startedFacts.single.simulated, isTrue);
    final row = await h.app.read(tripsRepositoryProvider).byId(kTestTripId);
    expect(row!.simulated, isTrue);
  });

  testWidgets('W18 preset wins over stored defaults', (tester) async {
    await pumpAlarmSettings(
      tester,
      prefs: {
        PreferenceKeys.tripMode: 'distance',
        PreferenceKeys.tripDistanceM: 5000,
      },
      extra: AlarmSettingsArgs(
        draft: kDraftTrain,
        preset: TripSettings.defaults.copyWith(
          mode: AlarmModeMsg.time,
          timeThresholdMin: 25,
          distanceThresholdM: 1234,
        ),
      ),
    );
    expect(bigValue('30 phút'), findsOneWidget);
    await tapVisible(tester, find.text('Khoảng cách'));
    expect(bigValue('1,2 km'), findsOneWidget);
  });

  testWidgets('W18 draft choice (restart) on top of the defaults', (
    tester,
  ) async {
    await pumpAlarmSettings(
      tester,
      prefs: {PreferenceKeys.tripDismiss: 'math'},
      extra: const TripDraft(
        destination: kGaDongHoi,
        source: DestinationSource.recentTrip,
        alarm: TripAlarmChoice(
          mode: AlarmModeMsg.distance,
          distanceThresholdM: 1500,
          preAlertEnabled: false,
        ),
      ),
    );
    expect(bigValue('1,5 km'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      _semanticsOf(tester, chip('Giải phép tính')),
      isSemantics(label: 'Giải phép tính', isSelected: true),
    );
  });

  testWidgets('W19 stored defaults: time 20, math', (tester) async {
    await pumpAlarmSettings(
      tester,
      prefs: {
        PreferenceKeys.tripMode: 'time',
        PreferenceKeys.tripTimeMin: 20,
        PreferenceKeys.tripDismiss: 'math',
      },
    );
    expect(bigValue('20 phút'), findsOneWidget);
    expect(
      _semanticsOf(tester, chip('Giải phép tính')),
      isSemantics(label: 'Giải phép tính', isSelected: true),
    );
  });

  testWidgets('W19 broken stored mode: smart', (tester) async {
    await pumpAlarmSettings(tester, prefs: {PreferenceKeys.tripMode: 'xyz'});
    expect(find.text('App tự chọn lúc báo'), findsOneWidget);
  });

  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    for (final mode in ['Khoảng cách', 'Thời gian', 'Thông minh']) {
      testWidgets('W20 a11y ${theme.name} $mode', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpAlarmSettings(tester, extra: kDraftCoach, theme: theme);
        await tapVisible(tester, find.text(mode));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  testWidgets('W21 text scale 2.0: no overflow, start button visible', (
    tester,
  ) async {
    await pumpAlarmSettings(
      tester,
      textScale: 2,
      extra: kDraftCoach,
      bridge: FakeCoreBridge(deviceStatusValue: deviceStatusMsg(batteryPct: 4)),
    );
    expect(tester.takeException(), isNull);
    for (final mode in ['Khoảng cách', 'Thời gian', 'Thông minh']) {
      await tapVisible(tester, find.text(mode));
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.text('Bắt đầu theo dõi'));
      expect(button.bottom, lessThanOrEqualTo(kHarnessSize.height));
    }
    await tapVisible(tester, find.text('Khoảng cách'));
    expect(_warning(), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final extra in <Object?>[null, 42]) {
    testWidgets('W22 extra $extra: back to home', (tester) async {
      final h = await pumpAlarmSettings(tester, extra: extra);
      expect(h.location, AppRoutes.home);
    });
  }

  testWidgets('W23 "Đổi" from screen 2 pops', (tester) async {
    final h = await pumpAlarmSettings(tester);
    expect(find.bySemanticsLabel('Đổi điểm đến'), findsOneWidget);
    await tapVisible(tester, find.text('Đổi'));
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W23 "Đổi" from screen 1 opens screen 2 in its place', (
    tester,
  ) async {
    final h = await pumpAlarmSettings(
      tester,
      extra: const TripDraft(
        destination: kGaDongHoi,
        source: DestinationSource.savedPlace,
      ),
    );
    await tapVisible(tester, find.text('Đổi'));
    expect(h.location, AppRoutes.destination);
    h.app.router.pop();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W23 Back always pops', (tester) async {
    final h = await pumpAlarmSettings(
      tester,
      extra: const TripDraft(
        destination: kGaDongHoi,
        source: DestinationSource.recentTrip,
      ),
    );
    await tapVisible(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W24 the error banner goes away on any change', (tester) async {
    final bridge = FakeCoreBridge()
      ..startTripError = const BridgeException(
        BridgeErrorCode.notForeground,
        rawCode: 'not-foreground',
      );
    await pumpAlarmSettings(tester, bridge: bridge);
    await _start(tester);
    expect(
      find.text('Hãy mở NapStop trên màn hình rồi bấm lại.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Khoảng cách'));
    await tapVisible(tester, chip('2 km'));
    expect(
      find.text('Hãy mở NapStop trên màn hình rồi bấm lại.'),
      findsNothing,
    );
  });

  testWidgets('W25 invalid destination: banner, no start', (tester) async {
    final h = await pumpAlarmSettings(
      tester,
      extra: const TripDraft(
        destination: TripDestination(
          name: 'Ghim',
          lat: 91,
          lng: 106,
          kind: DestinationKind.pin,
        ),
        source: DestinationSource.mapPin,
      ),
    );
    await _start(tester);
    expect(find.text('Điểm đến không hợp lệ. Hãy chọn lại.'), findsOneWidget);
    expect(h.bridge.callCount('startTrip'), 0);
    expect(h.reporter.rejected, ['destLat: out of range']);
  });

  testWidgets('English strings', (tester) async {
    await pumpAlarmSettings(
      tester,
      extra: kDraftCoach,
      locale: const Locale('en'),
    );
    expect(find.text('Alarm settings'), findsOneWidget);
    await tapVisible(tester, find.text('Distance'));
    expect(
      find.text(
        "Coaches go about 60 km/h: at 1 km you'd have only about 1 min to "
        'get off. Try Time or Smart.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Alarm when 1 km left', findRichText: true),
      findsOneWidget,
    );
  });

  group('round 2', () {
    const timeoutMessage =
        'Việc bắt đầu theo dõi lâu hơn bình thường. Bấm Thử lại để kiểm tra.';

    testWidgets('startTrip hangs: timeout banner, retry finds the trip', (
      tester,
    ) async {
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      final h = await pumpAlarmSettings(tester, bridge: bridge);
      await tester.ensureVisible(find.text('Bắt đầu theo dõi'));
      await tester.tap(find.text('Bắt đầu theo dõi'));
      await tester.pump();
      expect(find.text('Đang bắt đầu…'), findsOneWidget);
      await tester.pump(kStartTripTimeout - const Duration(seconds: 1));
      expect(find.text('Đang bắt đầu…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(timeoutMessage), findsOneWidget);
      expect(find.text('Bắt đầu theo dõi'), findsOneWidget);
      expect(h.location, AppRoutes.alarmSettings);
      // Back works again after the timeout.
      final scope = find.descendant(
        of: find.byType(AlarmSettingsScreen),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(tester.widget<PopScope<Object?>>(scope.first).canPop, isTrue);

      // The late answer arrives: the trip runs natively.
      bridge
        ..active = activeTrip(tripId: kTestTripId)
        ..startTripGate!.complete();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Thử lại'));
      expect(find.text('Đang có một chuyến được theo dõi.'), findsOneWidget);
      expect(bridge.callCount('startTrip'), 1, reason: 'no duplicate trip');
      await tapVisible(tester, find.text('Xem chuyến'));
      expect(h.location, AppRoutes.tracking);
    });

    testWidgets('retry while the first call still hangs: timeout again', (
      tester,
    ) async {
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      await pumpAlarmSettings(tester, bridge: bridge);
      await tapVisible(tester, find.text('Bắt đầu theo dõi'));
      await tester.pump(kStartTripTimeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(find.text('Đang bắt đầu…'), findsOneWidget);
      await tester.pump(kStartTripTimeout);
      await tester.pumpAndSettle();
      expect(find.text(timeoutMessage), findsOneWidget);
      expect(bridge.callCount('startTrip'), 1);
      bridge.startTripGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('muted and low-battery banners are live regions', (
      tester,
    ) async {
      await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge(
          deviceStatusValue: deviceStatusMsg(batteryPct: 4, alarmMuted: true),
        ),
      );
      for (final title in ['Báo thức có thể không kêu', 'Pin còn 4%']) {
        expect(
          tester.getSemantics(
            find.ancestor(
              of: find.text(title),
              matching: find.byType(NapBanner),
            ),
          ),
          isSemantics(isLiveRegion: true),
          reason: title,
        );
      }
    });

    test('en snooze note uses a plural', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        en.alarmSettingsSnoozeNote(1, '1 min'),
        'Snooze once, after 1 min',
      );
      expect(
        en.alarmSettingsSnoozeNote(2, '1 min'),
        'Snooze up to 2 times, after 1 min',
      );
      final vi = lookupAppLocalizations(const Locale('vi'));
      expect(
        vi.alarmSettingsSnoozeNote(1, '1 phút'),
        'Báo lại tối đa 1 lần, sau 1 phút',
      );
    });
  });

  group('T25.1', () {
    Future<void> hangAndTimeOut(WidgetTester tester, String start) async {
      await tester.ensureVisible(find.text(start));
      await tester.pumpAndSettle();
      await tester.tap(find.text(start));
      await tester.pump(kStartTripTimeout);
      await tester.pumpAndSettle();
    }

    void expectStartFullyVisible(WidgetTester tester, String start, Size size) {
      final button = find.ancestor(
        of: find.text(start),
        matching: find.byType(NapButton),
      );
      final rect = tester.getRect(button);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(find.text(start).hitTestable(), findsOneWidget);
    }

    for (final (locale, start, retry, size, scale) in [
      ('vi', 'Bắt đầu theo dõi', 'Thử lại', const Size(360, 640), 2.0),
      ('en', 'Start tracking', 'Retry', const Size(360, 640), 2.0),
      ('vi', 'Bắt đầu theo dõi', 'Thử lại', const Size(320, 568), 2.0),
      ('vi', 'Bắt đầu theo dõi', 'Thử lại', const Size(320, 568), 1.75),
    ]) {
      testWidgets(
        '#1 $locale ${size.width.toInt()}x${size.height.toInt()} x$scale: '
        'timeout banner scrolls in the bar, Start fully visible',
        (tester) async {
          final bridge = FakeCoreBridge(
            deviceStatusValue: deviceStatusMsg(batteryPct: 3, alarmMuted: true),
          )..startTripGate = Completer<void>();
          await pumpAlarmSettings(
            tester,
            bridge: bridge,
            size: size,
            textScale: scale,
            locale: Locale(locale),
            extra: kDraftCoach,
          );
          await hangAndTimeOut(tester, start);
          expect(tester.takeException(), isNull);
          expectStartFullyVisible(tester, start, size);
          // The content above keeps room to scroll.
          final content = tester.getRect(
            find.byType(SingleChildScrollView).first,
          );
          expect(content.height, greaterThan(size.height * 0.25));
          // "Retry" is reachable by scrolling inside the bar, and works.
          bridge.startTripError = null;
          await tester.ensureVisible(find.text(retry));
          await tester.pumpAndSettle();
          expect(find.text(retry).hitTestable(), findsOneWidget);
          bridge.startTripGate!.complete();
          await tester.pumpAndSettle();
          await tester.tap(find.text(retry));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('#1 generic banner at 320x568 x2.0 fits', (tester) async {
      const size = Size(320, 568);
      await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge()..startTripError = StateError('boom'),
        size: size,
        textScale: 2,
      );
      await tapVisible(tester, find.text('Bắt đầu theo dõi'));
      expect(
        find.text('Chưa bắt đầu được theo dõi. Thử lại sau giây lát.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expectStartFullyVisible(tester, 'Bắt đầu theo dõi', size);
    });

    for (final (size, scale) in [
      (const Size(411, 891), 2.0),
      (const Size(360, 640), 2.0),
      (const Size(320, 568), 1.75),
      (const Size(390, 844), 1.0),
    ]) {
      testWidgets('#2 chip labels are never cut at '
          '${size.width.toInt()}x${size.height.toInt()} x$scale', (
        tester,
      ) async {
        await pumpAlarmSettings(tester, size: size, textScale: scale);
        for (final (mode, labels) in [
          ('Khoảng cách', ['500 m', '1 km', '2 km', '5 km']),
          ('Thời gian', ['5', '10', '15', '20', '30']),
        ]) {
          await tapVisible(tester, find.text(mode));
          expect(tester.takeException(), isNull);
          for (final label in labels) {
            expectLabelWhole(tester, label);
          }
        }
      });
    }

    testWidgets('#2 equal widths on one line when the labels fit', (
      tester,
    ) async {
      await pumpAlarmSettings(tester, size: const Size(800, 1000));
      await tapVisible(tester, find.text('Khoảng cách'));
      final rects = [
        for (final label in ['500 m', '1 km', '2 km', '5 km'])
          tester.getRect(chip(label)),
      ];
      for (final r in rects) {
        expect(r.width, moreOrLessEquals(rects.first.width, epsilon: 0.5));
        expect(r.top, rects.first.top);
      }
    });

    testWidgets('#3 en timeout copy names the real button', (tester) async {
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      await pumpAlarmSettings(
        tester,
        bridge: bridge,
        locale: const Locale('en'),
      );
      await hangAndTimeOut(tester, 'Start tracking');
      expect(
        find.text('Starting is taking longer than usual. Tap Retry to check.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      bridge.startTripGate!.complete();
      await tester.pumpAndSettle();
    });

    test('review #1 chipLabelStyle applies what Text applies', () {
      const base = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
      expect(chipLabelStyle(base, boldText: false), base);
      expect(chipLabelStyle(base, boldText: true).fontWeight, FontWeight.bold);
      final spaced = chipLabelStyle(
        base,
        boldText: false,
        letterSpacing: 2,
        wordSpacing: 3,
        lineHeightScaleFactor: 1.5,
      );
      expect(
        (spaced.letterSpacing, spaced.wordSpacing, spaced.height),
        (2.0, 3.0, 1.5),
      );
    });

    testWidgets('review #1 bold text 360x640 x2.0: measured = rendered', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(boldText: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpAlarmSettings(tester, size: const Size(360, 640), textScale: 2);
      await tapVisible(tester, find.text('Khoảng cách'));
      final context = tester.element(find.byType(EqualChipRow).first);
      expect(MediaQuery.boldTextOf(context), isTrue);
      final measured = chipLabelStyle(
        context.napText.labelMedium!,
        boldText: true,
      );
      for (final label in ['500 m', '1 km', '2 km', '5 km']) {
        expectLabelWhole(tester, label);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: chip(label), matching: find.text(label)),
        );
        final rendered = (paragraph.text as TextSpan).style!;
        expect(rendered.fontWeight, FontWeight.bold, reason: label);
        expect(measured.fontWeight, rendered.fontWeight);
        expect(measured.fontSize, rendered.fontSize);
        expect(measured.letterSpacing, rendered.letterSpacing);
        expect(measured.fontFamily, rendered.fontFamily);
      }
    });

    for (final (spacing, rowExpected) in [(null, true), (2.0, false)]) {
      testWidgets(
        'review #1 near the threshold (320 px), letter spacing $spacing',
        (tester) async {
          // FlutterTest glyphs are 14 px: "500" = 42 px = exactly the share
          // left after the chip padding at 320 px. Extra letter spacing
          // pushes it over, so the row must wrap instead of cutting.
          const labels = ['500 m', '1 km', '2 km', '5 km'];
          await pumpNap(
            tester,
            MediaQuery.applyTextStyleOverrides(
              lineHeightScaleFactorOverride: null,
              letterSpacingOverride: spacing,
              wordSpacingOverride: null,
              paragraphSpacingOverride: null,
              child: EqualChipRow(
                labels: labels,
                chipBuilder: (i) =>
                    NapChip(label: labels[i], selected: i == 0, onTap: () {}),
              ),
            ),
            width: 320,
          );
          expect(tester.takeException(), isNull);
          final tops = {
            for (final label in labels) tester.getRect(chip(label)).top,
          };
          expect(tops.length == 1, rowExpected, reason: '$tops');
          for (final label in labels) {
            expectLabelWhole(tester, label);
          }
        },
      );
    }

    testWidgets('review #2 bar scrollbar shows only when it can scroll; '
        'TalkBack reaches Retry', (tester) async {
      final handle = tester.ensureSemantics();
      const size = Size(320, 568);
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      await pumpAlarmSettings(tester, bridge: bridge, size: size, textScale: 2);
      final barScrollbar = find.descendant(
        of: find.byType(StartBar),
        matching: find.byType(Scrollbar),
      );
      ScrollPosition barPosition() =>
          tester.widget<Scrollbar>(barScrollbar).controller!.position;
      // Summary only: nothing to scroll, so no thumb is painted.
      expect(barPosition().maxScrollExtent, 0);
      await hangAndTimeOutAt(tester, 'Bắt đầu theo dõi');
      expect(barPosition().maxScrollExtent, greaterThan(0));
      expect(tester.widget<Scrollbar>(barScrollbar).thumbVisibility, isTrue);
      // A screen reader brings Retry on screen and activates it.
      bridge.startTripGate!.complete();
      await tester.pumpAndSettle();
      final retry = find.semantics.byLabel('Thử lại');
      tester.semantics.showOnScreen(retry);
      await tester.pumpAndSettle();
      expect(find.text('Thử lại').hitTestable(), findsOneWidget);
      tester.semantics.tap(retry);
      await tester.pumpAndSettle();
      expect(bridge.callCount('startTrip'), 2);
      handle.dispose();
    });
  });
}
