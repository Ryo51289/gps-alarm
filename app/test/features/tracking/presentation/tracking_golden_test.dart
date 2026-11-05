// T26 G01-G03: screen 4, state 6 and the screen 7 sheet (FlutterTest font,
// 390x844, dpr 1). Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/golden_harness.dart';
import '../tracking_fixtures.dart';
import '../tracking_harness.dart';

/// 03:30 local time on every machine, so "05:40" is the same on Windows and
/// on CI (UTC).
final int _at = DateTime(2026, 11, 5, 3, 30).millisecondsSinceEpoch;

void main() {
  testWidgets('G01 tracking, light', (tester) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(state: w01State(atMs: _at)),
      nowMs: _at + 1000,
      fontFamily: kGoldenFontFamily,
    );
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/tracking_light.png'),
    );
  });

  testWidgets('G02 estimated (screen 6), dark', (tester) async {
    await pumpTracking(
      tester,
      bridge: trackingBridge(state: estimatedState(atMs: _at)),
      nowMs: _at + 1000,
      theme: NapThemeKind.dark,
      fontFamily: kGoldenFontFamily,
    );
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/tracking_estimated_dark.png'),
    );
  });

  testWidgets('G03 battery sheet (screen 7), light', (tester) async {
    final bridge = trackingBridge(
      state: stateMsg(
        atMs: _at,
        distanceM: 60000,
        etaS: 3600,
        progress: 0.4,
        batteryPct: 18,
        batteryRisk: true,
      ),
    );
    await pumpTracking(
      tester,
      bridge: bridge,
      nowMs: _at + 1000,
      fontFamily: kGoldenFontFamily,
    );
    bridge.emit(lowBatteryMsg());
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/battery_sheet_light.png'),
    );
  });
}
