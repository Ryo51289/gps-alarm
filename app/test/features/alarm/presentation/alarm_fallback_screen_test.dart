// T27 W18–W22: the Flutter fallback of screen 5 (/alarm?trip=…).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/alarm/presentation/widgets/swipe_to_stop_bar.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../helpers/alarm_fakes.dart';

/// Pumps frames without settling (the glow pulses forever).
Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  /// Screen 1, then /alarm pushed on top (as the coordinator does).
  Future<AppHarness> open(
    WidgetTester tester,
    TripStateMsg state, {
    FakeCoreBridge? bridge,
    String? engineParamsJson,
    DismissMethodMsg dismissMethod = DismissMethodMsg.swipe,
    Size size = kHarnessSize,
    double textScale = 1,
    Locale locale = const Locale('vi'),
    String initialLocation = AppRoutes.home,
  }) async {
    final fake =
        bridge ??
        FakeCoreBridge(
          active: ringingTrip(
            state,
            engineParamsJson: engineParamsJson,
            dismissMethod: dismissMethod,
          ),
        );
    final h = await pumpAppHarness(
      tester,
      bridge: fake,
      size: size,
      textScale: textScale,
      locale: locale,
      initialLocation: initialLocation,
    );
    unawaited(h.router.push('/alarm?trip=${state.tripId}'));
    await _frames(tester);
    return h;
  }

  Future<void> swipe(WidgetTester tester, double fraction) async {
    final bar = find.byType(SwipeToStopBar);
    final rect = tester.getRect(bar);
    // Knob 60 px + 2 × 6 px insets.
    final travel = rect.width - 72;
    await tester.dragFrom(
      Offset(rect.left + 36, rect.center.dy),
      Offset(travel * fraction, 0),
    );
    await _frames(tester, 3);
  }

  testWidgets('W18 arriving: reason, snooze, swipe bar whatever the dismiss '
      'method, a11y', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await open(
      tester,
      ringingState(),
      dismissMethod: DismissMethodMsg.math,
    );
    expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');
    expect(find.text('SẮP TỚI NƠI'), findsOneWidget);
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Còn khoảng 1,2 km tới Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Báo lại sau 1 phút'), findsOneWidget);
    expect(find.text('Vuốt hết thanh để tắt'), findsOneWidget);
    expect(find.text('Mở màn báo thức'), findsOneWidget);
    expect(
      find.text('Màn báo thức chưa hiện được. Bạn có thể tắt ngay tại đây.'),
      findsOneWidget,
    );
    expect(find.text('Xem đường quay lại'), findsNothing);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.backgroundColor, const Color(0xFF0F1115));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  for (final locale in const [Locale('vi'), Locale('en')]) {
    testWidgets('W18 320×568, text ×2: no overflow ($locale)', (tester) async {
      await open(
        tester,
        ringingState(phase: TripPhaseMsg.overshot, overshootPastM: 1300),
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byType(SwipeToStopBar),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await _frames(tester, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('W19 swipe 94 % does nothing, 100 % stops; a11y tap stops', (
    tester,
  ) async {
    final h = await open(tester, ringingState());
    await swipe(tester, 0.94);
    expect(h.bridge.dismissCalls, isEmpty);
    await swipe(tester, 1.1);
    expect(h.bridge.dismissCalls, ['trip-1']);

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(SwipeToStopBar)).label,
      'Tắt báo thức',
    );
    tester.semantics.tap(find.semantics.byLabel('Tắt báo thức'));
    await _frames(tester, 2);
    expect(h.bridge.dismissCalls, ['trip-1', 'trip-1']);
    handle.dispose();
  });

  testWidgets('W19 a failing stop: SnackBar, the knob slides back', (
    tester,
  ) async {
    final h = await open(tester, ringingState());
    h.bridge.dismissError = channelError();
    await swipe(tester, 1);
    expect(h.bridge.dismissCalls, ['trip-1']);
    expect(find.text('Chưa làm được. Thử lại.'), findsOneWidget);
    final knob = find.descendant(
      of: find.byType(SwipeToStopBar),
      matching: find.byIcon(Icons.arrow_forward_rounded),
    );
    final bar = tester.getRect(find.byType(SwipeToStopBar));
    expect(tester.getRect(knob).left, lessThan(bar.left + 10));
    // It works again at once (the SnackBar floats above the bar).
    h.bridge.dismissError = null;
    await swipe(tester, 1);
    expect(h.bridge.dismissCalls, ['trip-1', 'trip-1']);
  });

  testWidgets('W20 snooze once; after one snooze the button is gone', (
    tester,
  ) async {
    final h = await open(tester, ringingState());
    await tester.tap(find.text('Báo lại sau 1 phút'));
    await _frames(tester, 2);
    expect(h.bridge.snoozeCalls, ['trip-1']);

    h.bridge.emit(
      TripStateUpdateMsg(
        state: ringingState(snoozeCount: 1, reason: AlarmReasonMsg.snoozeEnd),
      ),
    );
    await _frames(tester, 2);
    expect(find.textContaining('Báo lại sau'), findsNothing);
    expect(find.text('Hết giờ báo lại — sắp tới Ga Đồng Hới'), findsOneWidget);
  });

  testWidgets('W20 snoozeS 90 from the trip parameters', (tester) async {
    await open(tester, ringingState(), engineParamsJson: '{"snoozeS":90}');
    expect(find.text('Báo lại sau 90 giây'), findsOneWidget);
  });

  testWidgets('W21 overshoot: no snooze; "Xem đường quay lại" stops then '
      'screen 8', (tester) async {
    final h = await open(
      tester,
      ringingState(phase: TripPhaseMsg.overshot, overshootPastM: 1300),
    );
    expect(find.text('ĐÃ QUA ĐIỂM ĐẾN'), findsOneWidget);
    expect(find.text('Có thể bạn đã đi quá Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Đã qua 1,3 km'), findsOneWidget);
    expect(find.textContaining('Báo lại'), findsNothing);
    await tester.ensureVisible(find.text('Xem đường quay lại'));
    await _frames(tester, 2);
    await tester.tap(find.text('Xem đường quay lại'));
    await _frames(tester);
    expect(h.bridge.dismissCalls, ['trip-1']);
    expect(
      h.router.state.uri.toString(),
      '/overshoot?trip=trip-1&past=1300&open=1',
    );
  });

  testWidgets('W21 "Xem đường quay lại" with a failing stop stays', (
    tester,
  ) async {
    final h = await open(
      tester,
      ringingState(phase: TripPhaseMsg.overshot, overshootPastM: 1300),
    );
    h.bridge.dismissError = StateError('x');
    final reported = ReportedErrors();
    addTearDown(reported.restore);
    await tester.ensureVisible(find.text('Xem đường quay lại'));
    await _frames(tester, 2);
    await tester.tap(find.text('Xem đường quay lại'));
    await _frames(tester);
    reported.restore();
    expect(reported.texts.single, contains('StateError'));
    expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');
    expect(find.text('Chưa làm được. Thử lại.'), findsOneWidget);
  });

  testWidgets('"Mở màn báo thức": false → SnackBar', (tester) async {
    final h = await open(tester, ringingState());
    await tester.ensureVisible(find.text('Mở màn báo thức'));
    await _frames(tester, 2);
    await tester.tap(find.text('Mở màn báo thức'));
    await _frames(tester, 2);
    expect(h.bridge.showAlarmScreenCalls, ['trip-1']);
    expect(find.text('Chưa làm được. Thử lại.'), findsOneWidget);
  });

  for (final (label, update) in <(String, TripUpdateMsg)>[
    ('not ringing', TripStateUpdateMsg(state: ringingState(ringing: false))),
    (
      'snoozed',
      TripStateUpdateMsg(state: ringingState(phase: TripPhaseMsg.snoozed)),
    ),
    ('trip ended', tripEnded()),
  ]) {
    testWidgets('W22 closes itself: $label', (tester) async {
      final h = await open(tester, ringingState());
      expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');
      h.bridge.emit(update);
      await _frames(tester, 8);
      expect(h.location, AppRoutes.home);
    });
  }

  testWidgets('W22 another trip / no trip: closes at once', (tester) async {
    final h = await open(
      tester,
      ringingState(),
      bridge: FakeCoreBridge(active: ringingTrip(ringingState(tripId: 'x'))),
    );
    expect(h.location, AppRoutes.home);
    unawaited(h.router.push('/alarm?trip=trip-1'));
    h.bridge.active = null;
    await _frames(tester, 8);
    expect(h.location, AppRoutes.home);
  });

  testWidgets('review #2: a failed currentTrip keeps the screen; the stream '
      'still closes it', (tester) async {
    final reported = ReportedErrors();
    addTearDown(reported.restore);
    final h = await open(
      tester,
      ringingState(),
      bridge: FakeCoreBridge()..currentTripError = channelError(),
    );
    expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');
    // No config: generic name, swipe bar still there.
    expect(find.text('nơi đến'), findsOneWidget);
    expect(find.text('Vuốt hết thanh để tắt'), findsOneWidget);
    h.bridge.emit(TripStateUpdateMsg(state: ringingState()));
    await _frames(tester, 2);
    expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');
    await swipe(tester, 1);
    expect(h.bridge.dismissCalls, ['trip-1']);
    h.bridge.emit(TripStateUpdateMsg(state: ringingState(ringing: false)));
    await _frames(tester, 8);
    expect(h.location, AppRoutes.home);

    // An unexpected error is reported (type only) and keeps the screen too.
    h.bridge.currentTripError = StateError('Ga Đồng Hới');
    unawaited(h.router.push('/alarm?trip=trip-1'));
    await _frames(tester, 8);
    reported.restore();
    expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');
    expect(reported.texts.single, contains('StateError'));
    expect(reported.texts.single, isNot(contains('Đồng Hới')));
  });

  testWidgets('review #4: no updates while the app is not visible; back in '
      'front, a ring that ended closes the screen', (tester) async {
    // Screen 12 placeholder below: nothing else listens to the updates.
    final h = await open(
      tester,
      ringingState(),
      initialLocation: AppRoutes.settings,
    );
    expect(h.bridge.hasListener, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _frames(tester, 2);
    expect(h.bridge.hasListener, isFalse);
    expect(h.router.state.uri.toString(), '/alarm?trip=trip-1');

    // Stopped on the native screen meanwhile.
    h.bridge.active = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester, 8);
    expect(h.location, AppRoutes.settings);
  });

  testWidgets('review #5: a cancelled drag past 95 % does not stop', (
    tester,
  ) async {
    final h = await open(tester, ringingState());
    final rect = tester.getRect(find.byType(SwipeToStopBar));
    final gesture = await tester.startGesture(
      Offset(rect.left + 36, rect.center.dy),
    );
    await gesture.moveBy(Offset(rect.width, 0));
    await tester.pump();
    await gesture.cancel();
    await _frames(tester, 3);
    expect(h.bridge.dismissCalls, isEmpty);
    final knob = find.descendant(
      of: find.byType(SwipeToStopBar),
      matching: find.byIcon(Icons.arrow_forward_rounded),
    );
    expect(tester.getRect(knob).left, lessThan(rect.left + 10));
  });
}
