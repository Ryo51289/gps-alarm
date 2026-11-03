// T25 G01, G02: screen 3 goldens (FlutterTest font, 390x1300, dpr 1).
// Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/golden_harness.dart';
import '../helpers/alarm_settings_harness.dart';

const Size _size = Size(390, 1300);

void main() {
  testWidgets('G01 distance warning, light', (tester) async {
    await pumpAlarmSettings(tester, size: _size, fontFamily: kGoldenFontFamily);
    await tapVisible(tester, find.text('Khoảng cách'));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/alarm_settings_distance_warning_light.png'),
    );
  });

  testWidgets('G02 smart default, dark', (tester) async {
    await pumpAlarmSettings(
      tester,
      size: _size,
      theme: NapThemeKind.dark,
      fontFamily: kGoldenFontFamily,
    );
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/alarm_settings_smart_dark.png'),
    );
  });
}
