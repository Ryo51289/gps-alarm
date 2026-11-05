// T26 W12-W15 (+ W25/W26 of the sheet): screen 7 on screen 4.
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../tracking_fixtures.dart';
import '../tracking_harness.dart';

TripStateMsg _risk({
  int atMs = kAtMs,
  int pct = 18,
  BatteryChoiceMsg? choice,
}) => stateMsg(
  atMs: atMs,
  distanceM: 60000,
  etaS: 3600,
  batteryPct: pct,
  batteryRisk: true,
  batteryChoice: choice,
);

Future<FakeCoreBridge> _open(WidgetTester tester, {int pct = 18}) async {
  final bridge = trackingBridge(state: _risk(pct: pct));
  await pumpTracking(tester, bridge: bridge);
  // Like native: the event comes after the view that raised the risk.
  bridge.emit(lowBatteryMsg(levelPct: pct));
  await tester.pumpAndSettle();
  return bridge;
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  testWidgets('W12 opens once by itself with the estimate and 3 choices', (
    tester,
  ) async {
    await _open(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_inSheet(find.text('Pin có thể không đủ tới nơi')), findsOneWidget);
    expect(
      find.text('Pin còn 18%. Chọn cách để NapStop vẫn kịp đánh thức bạn.'),
      findsWidgets,
    );
    expect(
      find.text('Pin còn dùng được khoảng 1 giờ 10 phút, cần khoảng 2 giờ.'),
      findsOneWidget,
    );
    final options = tester
        .widgetList<NapOptionCard>(find.byType(NapOptionCard))
        .toList();
    expect(options.map((o) => o.title), [
      'Tiết kiệm tối đa',
      'Báo sớm khi pin còn 5%',
      'Báo sớm hơn, khi pin còn 15%',
    ]);
    expect(options.map((o) => o.selected), [true, false, false]);
  });

  testWidgets('W13 apply "Báo sớm hơn": one call, analytics, sheet closes', (
    tester,
  ) async {
    final bridge = await _open(tester);
    await tester.tap(find.text('Báo sớm hơn, khi pin còn 15%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();
    expect(bridge.batteryChoiceCalls, [
      (tripId: kTripId, choice: BatteryChoiceMsg.alarmEarlier),
    ]);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pump();
    final (name, params) = trackingAnalytics.events.single;
    expect(name, 'low_battery_choice');
    expect(params, {'choice': 'alarm_earlier', 'simulated': 0});
    bridge.emit(
      TripStateUpdateMsg(
        state: _risk(atMs: kAtMs + 5, choice: BatteryChoiceMsg.alarmEarlier),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chọn cách'), findsNothing);
    expect(find.text('Báo sớm hơn'), findsOneWidget);
  });

  testWidgets('W14 "Để sau": no reopen; banner reopens; failure keeps it', (
    tester,
  ) async {
    final bridge = await _open(tester);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    for (var i = 1; i <= 3; i++) {
      bridge.emit(TripStateUpdateMsg(state: _risk(atMs: kAtMs + i)));
      await tester.pumpAndSettle();
    }
    expect(find.byType(BottomSheet), findsNothing);
    expect(bridge.batteryChoiceCalls, isEmpty);
    expect(find.text('Pin có thể không đủ tới nơi'), findsOneWidget);

    await tester.ensureVisible(find.text('Chọn cách'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn cách'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    bridge.setBatteryChoiceError = channelError();
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    // Inside the sheet and visible (review T26 #1), not a snack bar under it.
    final error = _inSheet(find.text('Chưa thực hiện được. Thử lại.'));
    expect(error.hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(trackingAnalytics.events, isEmpty);
    // A successful retry closes the sheet.
    bridge.setBatteryChoiceError = null;
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(bridge.batteryChoiceCalls, hasLength(2));
  });

  group('W25 sheet a11y', () {
    for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
      testWidgets(theme.name, (tester) async {
        final handle = tester.ensureSemantics();
        final bridge = trackingBridge(state: _risk());
        await pumpTracking(tester, bridge: bridge, theme: theme);
        bridge.emit(lowBatteryMsg());
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        final checked = tester.getSemantics(
          find.widgetWithText(NapOptionCard, 'Tiết kiệm tối đa'),
        );
        expect(checked.flagsCollection.isChecked, CheckedState.isTrue);
        handle.dispose();
      });
    }
  });

  group('W26 sheet at text scale 2.0', () {
    for (final size in const [Size(320, 568), Size(390, 844)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        final bridge = trackingBridge(state: _risk());
        await pumpTracking(tester, bridge: bridge, size: size, textScale: 2);
        bridge.emit(lowBatteryMsg());
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
        final apply = _inSheet(find.text('Áp dụng'));
        await tester.ensureVisible(apply);
        await tester.pumpAndSettle();
        expect(apply.hitTestable(), findsOneWidget);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(bridge.batteryChoiceCalls, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('W15 battery 13 %: "Báo sớm hơn" at 12 %', (tester) async {
    await _open(tester, pct: 13);
    expect(find.text('Báo sớm hơn, khi pin còn 12%'), findsOneWidget);
  });

  testWidgets('closes by itself once a choice arrives from elsewhere', (
    tester,
  ) async {
    final bridge = await _open(tester);
    bridge.emit(
      TripStateUpdateMsg(
        state: _risk(atMs: kAtMs + 9, choice: BatteryChoiceMsg.maxSaving),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Tiết kiệm tối đa'), findsOneWidget, reason: 'tile note');
  });
}
