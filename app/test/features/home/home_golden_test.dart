// G01-G05: screen 1 goldens (FlutterTest font, 390 px, dpr 1, 19:30).
// Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/golden_harness.dart';
import '../../helpers/trip_fixtures.dart';

void main() {
  final cases = <(String, Future<AppHarness> Function(WidgetTester))>[
    (
      'home_light',
      (t) => pumpAppHarness(t, seed: seedW01, fontFamily: kGoldenFontFamily),
    ),
    (
      'home_dark',
      (t) => pumpAppHarness(
        t,
        seed: seedW01,
        theme: NapThemeKind.dark,
        fontFamily: kGoldenFontFamily,
      ),
    ),
    (
      'home_empty_light',
      (t) => pumpAppHarness(t, fontFamily: kGoldenFontFamily),
    ),
    (
      'home_blocked_light',
      (t) => pumpAppHarness(
        t,
        fontFamily: kGoldenFontFamily,
        bridge: FakeCoreBridge(
          permissions: androidPermissions(location: LocationAccessMsg.denied),
        ),
      ),
    ),
    (
      'home_light_x2',
      (t) => pumpAppHarness(
        t,
        seed: seedW01,
        textScale: 2,
        size: const Size(390, 2400),
        fontFamily: kGoldenFontFamily,
      ),
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
