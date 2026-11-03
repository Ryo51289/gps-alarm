// Tester T25: screen 3 through the real router and app shell, adversarial
// paths around "will the user be woken": late native answers, warnings that
// must not block, refresh on resume, large text, logs.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../helpers/alarm_settings_harness.dart';

const _startVi = 'Bắt đầu theo dõi';
const _timeoutVi =
    'Việc bắt đầu theo dõi lâu hơn bình thường. Bấm Thử lại để kiểm tra.';
const _mutedVi = 'Báo thức có thể không kêu';

Future<void> _tapStart(WidgetTester tester, {String label = _startVi}) =>
    tapVisible(tester, find.text(label));

/// Taps Start and lets the 15 s timeout of a hung `startTrip` expire.
Future<void> _startAndTimeOut(
  WidgetTester tester, {
  String label = _startVi,
}) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(kStartTripTimeout);
  await tester.pumpAndSettle();
}

/// System Back (respects PopScope).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

BridgeException _err(BridgeErrorCode c) => BridgeException(c, rawCode: c.wire);

void main() {
  group('late answer of startTrip (review round 2, tester note 1)', () {
    testWidgets('late success: home shows the trip; screen 3 again says a '
        'trip is running, never starts a 2nd one', (tester) async {
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      final h = await pumpAlarmSettings(tester, bridge: bridge);
      await _startAndTimeOut(tester);
      expect(find.text(_timeoutVi), findsOneWidget);
      expect(h.location, AppRoutes.alarmSettings);

      // The user gives up and goes back to screen 1.
      await _back(tester);
      expect(h.location, AppRoutes.home);
      expect(find.text('Đang theo dõi chuyến đi'), findsNothing);

      // Native finally starts the trip and says so.
      bridge
        ..active = activeTrip(tripId: kTestTripId)
        ..startTripGate!.complete()
        ..emit(TripStateUpdateMsg(state: tripState(tripId: kTestTripId)));
      await tester.pumpAndSettle();
      expect(find.text('Đang theo dõi chuyến đi'), findsOneWidget);
      final row = await h.app.read(tripsRepositoryProvider).byId(kTestTripId);
      expect(row, isNotNull, reason: 'late success keeps the history row');

      // Screen 3 again (as T23/T22 push it) and Start.
      unawaited(
        h.app.router.push<void>(AppRoutes.alarmSettings, extra: kDraftTrain),
      );
      await tester.pumpAndSettle();
      await _tapStart(tester);
      expect(find.text('Đang có một chuyến được theo dõi.'), findsOneWidget);
      expect(bridge.callCount('startTrip'), 1);
      await tapVisible(tester, find.text('Xem chuyến'));
      expect(h.location, AppRoutes.tracking);
    });

    testWidgets('late failure: row removed, no trip on home, retry starts '
        'normally', (tester) async {
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      final h = await pumpAlarmSettings(tester, bridge: bridge);
      await _startAndTimeOut(tester);
      final repo = h.app.read(tripsRepositoryProvider);
      expect(
        await repo.byId(kTestTripId),
        isNotNull,
        reason:
            'kept while '
            'the answer is pending',
      );

      bridge
        ..startTripError = _err(BridgeErrorCode.startFailed)
        ..startTripGate!.complete();
      await tester.pumpAndSettle();
      expect(await repo.byId(kTestTripId), isNull);

      // Retry from the banner: a normal start.
      bridge
        ..startTripGate = null
        ..startTripError = null;
      await tapVisible(tester, find.text('Thử lại'));
      expect(bridge.callCount('startTrip'), 2);
      expect(h.location, AppRoutes.tracking);
      expect(await repo.byId(kTestTripId), isNotNull);
    });

    testWidgets('timeout then late success while still on screen 3: Back '
        'is allowed, retry reports the running trip', (tester) async {
      final bridge = FakeCoreBridge()..startTripGate = Completer<void>();
      await pumpAlarmSettings(tester, bridge: bridge);
      await _startAndTimeOut(tester);
      // Retry: still inside its wait, answer arrives at +5 s.
      await tester.tap(find.text('Thử lại'));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Đang bắt đầu…'), findsOneWidget);
      bridge
        ..active = activeTrip(tripId: kTestTripId)
        ..startTripGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đang có một chuyến được theo dõi.'), findsOneWidget);
      expect(bridge.callCount('startTrip'), 1);
    });
  });

  group('error banners = T25 §3.4', () {
    const copy = {
      BridgeErrorCode.tripActive: 'Đang có một chuyến được theo dõi.',
      BridgeErrorCode.notForeground:
          'Hãy mở NapStop trên màn hình rồi bấm lại.',
      BridgeErrorCode.simulationUnavailable: 'Không mở được chuyến giả lập.',
      BridgeErrorCode.invalidConfig:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
      BridgeErrorCode.permissionMissing:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
      BridgeErrorCode.startFailed:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
      BridgeErrorCode.requestInProgress:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
      BridgeErrorCode.internal:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
      BridgeErrorCode.channelError:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
      BridgeErrorCode.unknown:
          'Chưa bắt đầu được theo dõi. Thử lại sau giây lát.',
    };
    test('table covers every code', () {
      expect(copy.keys.toSet(), BridgeErrorCode.values.toSet());
    });
    for (final MapEntry(key: code, value: text) in copy.entries) {
      testWidgets('${code.wire}: banner + action', (tester) async {
        final h = await pumpAlarmSettings(
          tester,
          bridge: FakeCoreBridge()..startTripError = _err(code),
        );
        await _tapStart(tester);
        expect(find.text(text), findsOneWidget);
        expect(h.location, AppRoutes.alarmSettings);
        expect(
          find.text('Thử lại'),
          text.startsWith('Chưa bắt đầu') ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Xem chuyến'),
          code == BridgeErrorCode.tripActive ? findsOneWidget : findsNothing,
        );
        // Not stuck on "starting": Start is enabled again.
        expect(find.text(_startVi), findsOneWidget);
        expect(
          await h.app.read(tripsRepositoryProvider).byId(kTestTripId),
          isNull,
        );
      });
    }
  });

  group('"may not ring" warning: warns, never blocks', () {
    for (final (name, status, shown) in <(String, DeviceStatusMsg, bool)>[
      ('volume 0', deviceStatusMsg(alarmVolumePct: 0), true),
      ('muted', deviceStatusMsg(alarmMuted: true), true),
      (
        'DND none',
        deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.none),
        true,
      ),
      (
        'priority, alarms not allowed',
        deviceStatusMsg(
          interruptionFilter: InterruptionFilterMsg.priority,
          priorityAllowsAlarms: false,
        ),
        true,
      ),
      // Not warned: alarms still pass, or the state is unknown.
      (
        'priority, alarms allowed',
        deviceStatusMsg(
          interruptionFilter: InterruptionFilterMsg.priority,
          priorityAllowsAlarms: true,
        ),
        false,
      ),
      (
        'priority, unknown',
        deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.priority),
        false,
      ),
      (
        'DND alarms only',
        deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.alarms),
        false,
      ),
      (
        'filter unknown',
        deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.unknown),
        false,
      ),
      ('volume 1 %', deviceStatusMsg(alarmVolumePct: 1), false),
      (
        'all unknown',
        deviceStatusMsg(alarmVolumePct: null, alarmMuted: null),
        false,
      ),
    ]) {
      testWidgets('$name: banner ${shown ? 'shown' : 'hidden'}, start runs', (
        tester,
      ) async {
        final h = await pumpAlarmSettings(
          tester,
          bridge: FakeCoreBridge(deviceStatusValue: status),
        );
        expect(find.text(_mutedVi), shown ? findsOneWidget : findsNothing);
        await _tapStart(tester);
        expect(h.bridge.callCount('startTrip'), 1);
        expect(h.location, AppRoutes.tracking);
      });
    }

    testWidgets('shade pulled (inactive → resumed only) refreshes both ways', (
      tester,
    ) async {
      final bridge = FakeCoreBridge();
      await pumpAlarmSettings(tester, bridge: bridge);
      expect(find.text(_mutedVi), findsNothing);
      final before = bridge.callCount('deviceStatus');

      bridge.deviceStatusValue = deviceStatusMsg(
        alarmMuted: true,
        interruptionFilter: InterruptionFilterMsg.none,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_mutedVi), findsOneWidget);
      expect(bridge.callCount('deviceStatus'), before + 1);

      // DND turned off again from the shade.
      bridge.deviceStatusValue = deviceStatusMsg();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_mutedVi), findsNothing);
    });

    testWidgets('status read fails on resume: warning hidden (unknown), '
        'start still allowed', (tester) async {
      final bridge = FakeCoreBridge(
        deviceStatusValue: deviceStatusMsg(alarmMuted: true),
      );
      final h = await pumpAlarmSettings(tester, bridge: bridge);
      expect(find.text(_mutedVi), findsOneWidget);
      bridge.deviceStatusError = StateError('read');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // Observation: an unreadable state clears the warning (it is a hint).
      expect(find.text(_mutedVi), findsNothing);
      await _tapStart(tester);
      expect(h.location, AppRoutes.tracking);
    });
  });

  group('text scale 2.0, every banner at once', () {
    const locales = [
      (
        'vi',
        'Bắt đầu theo dõi',
        ['Khoảng cách', 'Thời gian', 'Thông minh'],
        'Thử lại',
      ),
      ('en', 'Start tracking', ['Distance', 'Time', 'Smart'], 'Retry'),
    ];

    Future<FakeCoreBridge> pumpAllBanners(
      WidgetTester tester,
      Size size,
      String locale,
    ) async {
      final bridge = FakeCoreBridge(
        deviceStatusValue: deviceStatusMsg(
          batteryPct: 3,
          alarmMuted: true,
          interruptionFilter: InterruptionFilterMsg.none,
        ),
      )..startTripGate = Completer<void>();
      await pumpAlarmSettings(
        tester,
        textScale: 2,
        size: size,
        locale: Locale(locale),
        extra: kDraftCoach,
        bridge: bridge,
      );
      expect(tester.takeException(), isNull);
      return bridge;
    }

    void expectStartReachable(WidgetTester tester, String start, Size size) {
      final button = find.text(start).hitTestable();
      expect(button, findsOneWidget);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
    }

    for (final (locale, start, modes, retry) in locales) {
      testWidgets('$locale 390x844: every mode with the timeout banner', (
        tester,
      ) async {
        const size = Size(390, 844);
        final bridge = await pumpAllBanners(tester, size, locale);
        for (final mode in modes) {
          await tapVisible(tester, find.text(mode));
          // The longest error banner (timeout) in the fixed bottom bar.
          await _startAndTimeOut(tester, label: start);
          expect(tester.takeException(), isNull, reason: mode);
          expectStartReachable(tester, start, size);
          expect(find.text(retry).hitTestable(), findsOneWidget);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -4000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: mode);
        }
        bridge.startTripGate!.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('$locale 360x640: every mode, all status banners', (
        tester,
      ) async {
        const size = Size(360, 640);
        final bridge = await pumpAllBanners(tester, size, locale);
        for (final mode in modes) {
          await tapVisible(tester, find.text(mode));
          expect(tester.takeException(), isNull, reason: mode);
          expectStartReachable(tester, start, size);
        }
        bridge.startTripGate!.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('$locale 360x640 smart + timeout banner: bottom bar fits', (
        tester,
      ) async {
        const size = Size(360, 640);
        final bridge = await pumpAllBanners(tester, size, locale);
        await _startAndTimeOut(tester, label: start);
        expect(tester.takeException(), isNull);
        expectStartReachable(tester, start, size);
        bridge.startTripGate!.complete();
        await tester.pumpAndSettle();
      });
    }
  });

  testWidgets('nothing is printed during starts and failures (no coordinates '
      'or names)', (tester) async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      final bridge = FakeCoreBridge()
        ..startTripError = _err(BridgeErrorCode.internal);
      await pumpAlarmSettings(tester, bridge: bridge);
      await tapVisible(tester, find.text('Khoảng cách'));
      await _tapStart(tester);
      bridge.startTripError = null;
      await tapVisible(tester, find.text('Thử lại'));
      await tester.pumpAndSettle();
    } finally {
      debugPrint = previous;
    }
    for (final line in logs) {
      expect(line, isNot(contains('17.47')));
      expect(line, isNot(contains('106.60')));
      expect(line, isNot(contains('Đồng Hới')));
    }
    expect(logs, isEmpty);
  });
}
