// T23 TG01–TG02, T23.2: screen 2 goldens (FlutterTest font, 390x844, dpr 1,
// fake map, no real tiles). Update with:
// flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/golden_harness.dart';
import 'destination_harness.dart';

Future<void> selectDongHoi(WidgetTester tester) async {
  await typeQuery(tester, 'dong hoi');
  await tapVisible(tester, find.text('Ga Đồng Hới').first);
}

void main() {
  final cases = <(String, Future<void> Function(WidgetTester))>[
    (
      'destination_selected_light',
      (t) async {
        await pumpDestination(t, fontFamily: kGoldenFontFamily);
        await selectDongHoi(t);
      },
    ),
    (
      'destination_selected_dark',
      (t) async {
        await pumpDestination(
          t,
          theme: NapThemeKind.dark,
          fontFamily: kGoldenFontFamily,
        );
        await selectDongHoi(t);
      },
    ),
    (
      // T23.2: no map builder (every platform until T23.3), 3 chips.
      'destination_no_map_light',
      (t) async {
        await pumpDestination(t, withMap: false, fontFamily: kGoldenFontFamily);
        await typeQuery(t, 'dong hoi');
      },
    ),
  ];

  for (final (name, pump) in cases) {
    testWidgets('golden $name', (tester) async {
      await pump(tester);
      await expectLater(
        find.byKey(kAppHarnessBoundaryKey),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
