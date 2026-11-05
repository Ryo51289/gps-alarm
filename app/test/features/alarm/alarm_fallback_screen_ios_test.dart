// T28.3 PW05, PW07 (screen 5 on iOS, D6): no "Mở màn báo thức" (iOS has no
// app alarm screen, T17.2 D9) and the iOS note; the rest as on Android.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/alarm/presentation/widgets/swipe_to_stop_bar.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import 'helpers/alarm_fakes.dart';

const _iosNote = 'Báo thức đang kêu. Bạn có thể tắt ngay tại đây.';
const _androidNote =
    'Màn báo thức chưa hiện được. Bạn có thể tắt ngay tại đây.';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

/// Pumps frames without settling (the glow pulses forever).
Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Screen 1, then /alarm pushed on top (as the coordinator does).
Future<AppHarness> _open(
  WidgetTester tester,
  TripStateMsg state, {
  Size size = kHarnessSize,
  double textScale = 1,
  Locale locale = const Locale('vi'),
}) async {
  final h = await pumpAppHarness(
    tester,
    bridge: FakeCoreBridge(
      active: ringingTrip(state, dismissMethod: DismissMethodMsg.shake),
      permissions: iosPermissions(),
      deviceInfoValue: iosDevice(major: 27),
    ),
    size: size,
    textScale: textScale,
    locale: locale,
  );
  unawaited(h.router.push('/alarm?trip=${state.tripId}'));
  await _frames(tester);
  return h;
}

Future<void> _swipeAll(WidgetTester tester) async {
  final bar = find.byType(SwipeToStopBar);
  await tester.ensureVisible(bar);
  await _frames(tester, 2);
  final rect = tester.getRect(bar);
  await tester.dragFrom(
    Offset(rect.left + 36, rect.center.dy),
    Offset((rect.width - 72) * 1.1, 0),
  );
  await _frames(tester, 3);
}

void main() {
  testWidgets('PW05 iOS arriving: iOS note, snooze, swipe; no "Mở màn báo '
      'thức"', (tester) async {
    final h = await _open(tester, ringingState());
    expect(find.text('SẮP TỚI NƠI'), findsOneWidget);
    expect(find.text(_iosNote), findsOneWidget);
    expect(find.text(_androidNote), findsNothing);
    expect(find.text('Mở màn báo thức'), findsNothing);
    expect(find.text('Báo lại sau 1 phút'), findsOneWidget);
    expect(find.text('Vuốt hết thanh để tắt'), findsOneWidget);
    expect(find.text('Xem đường quay lại'), findsNothing);

    await _swipeAll(tester);
    expect(h.bridge.dismissCalls, ['trip-1']);
    expect(h.bridge.showAlarmScreenCalls, isEmpty);
  }, variant: _ios);

  testWidgets('PW05 iOS snooze goes through Pigeon', (tester) async {
    final h = await _open(tester, ringingState());
    await tester.tap(find.text('Báo lại sau 1 phút'));
    await _frames(tester, 2);
    expect(h.bridge.snoozeCalls, ['trip-1']);
  }, variant: _ios);

  testWidgets('PW05 iOS overshoot: "Xem đường quay lại", no extra button', (
    tester,
  ) async {
    final h = await _open(
      tester,
      ringingState(phase: TripPhaseMsg.overshot, overshootPastM: 1300),
    );
    expect(find.text('ĐÃ QUA ĐIỂM ĐẾN'), findsOneWidget);
    expect(find.text(_iosNote), findsOneWidget);
    expect(find.text('Mở màn báo thức'), findsNothing);
    expect(find.byType(SwipeToStopBar), findsOneWidget);
    await tester.ensureVisible(find.text('Xem đường quay lại'));
    await _frames(tester, 2);
    await tester.tap(find.text('Xem đường quay lại'));
    await _frames(tester);
    expect(h.bridge.dismissCalls, ['trip-1']);
    expect(
      h.router.state.uri.toString(),
      '/overshoot?trip=trip-1&past=1300&open=1',
    );
  }, variant: _ios);

  testWidgets('PW05 Android: the button and note as before', (tester) async {
    await _open(tester, ringingState());
    expect(find.text('Mở màn báo thức'), findsOneWidget);
    expect(find.text(_androidNote), findsOneWidget);
    expect(find.text(_iosNote), findsNothing);
  }, variant: _android);

  for (final locale in const [Locale('vi'), Locale('en')]) {
    for (final phase in const [TripPhaseMsg.alarming, TripPhaseMsg.overshot]) {
      testWidgets('PW07 screen 5 iOS 320 px, text ×2, $locale, ${phase.name}: '
          'no overflow', (tester) async {
        await _open(
          tester,
          ringingState(
            phase: phase,
            overshootPastM: phase == TripPhaseMsg.overshot ? 1300 : null,
          ),
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
      }, variant: _ios);
    }
  }
}
