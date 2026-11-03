// G01, G02: screens 0 and 9 goldens (FlutterTest font, 390 px, dpr 1).
// Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_api.g.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/golden_harness.dart';

FakeCoreBridge _xiaomi(PermissionStatusMsg permissions) => FakeCoreBridge(
  deviceInfoValue: androidDevice(manufacturer: 'Xiaomi', brand: 'Redmi'),
  permissions: permissions,
);

void main() {
  testWidgets('G01 golden onboarding_light', (tester) async {
    await pumpAppHarness(
      tester,
      initialLocation: AppRoutes.onboarding,
      fontFamily: kGoldenFontFamily,
      bridge: _xiaomi(
        androidPermissions(
          location: LocationAccessMsg.notDetermined,
          precise: PermissionStateMsg.notDetermined,
          notifications: PermissionStateMsg.notDetermined,
          fullScreenIntent: PermissionStateMsg.denied,
          batteryOptimizationIgnored: PermissionStateMsg.denied,
        ),
      ),
    );
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/onboarding_light.png'),
    );
  });

  testWidgets('G02 golden battery_guide_light', (tester) async {
    final h = await pumpAppHarness(
      tester,
      fontFamily: kGoldenFontFamily,
      bridge: _xiaomi(androidPermissions()),
    );
    unawaited(h.router.push<void>(AppRoutes.batteryGuide));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(kAppHarnessBoundaryKey),
      matchesGoldenFile('goldens/battery_guide_light.png'),
    );
  });
}
