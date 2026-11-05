// T01.2 CI05: iOS smoke test on the Simulator. The app starts and the
// Pigeon bridge answers (CoreBridgeStub before T17, the real runtime after).
// Run by the ios-sim job of .github/workflows/ios-compile.yml through
// integration_test/ios_suite.txt; skipped on Android. By hand on a Mac:
//   flutter test integration_test/ios_smoke_test.dart -d <simulator-udid>
// Touches no permission dialog and logs no coordinates.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/main.dart' as app;

/// Android runs nothing here: the same checks live in bridge_smoke_test.dart.
final bool _notIos = !Platform.isIOS;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts', skip: _notIos, (tester) async {
    await app.main();
    for (
      var i = 0;
      i < 100 && find.byType(NapStopApp).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NapStopApp), findsOneWidget);
    // A few frames past the first one: startup work must not throw.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deviceInfo reports iOS', skip: _notIos, (tester) async {
    final device = await CoreBridge().deviceInfo();
    expect(device.platform, PlatformMsg.ios);
    expect(device.androidSdkInt, isNull);
  });

  testWidgets('currentTrip answers', skip: _notIos, (tester) async {
    // Null (no trip) or a trip left by an earlier run: either way no error.
    await expectLater(CoreBridge().currentTrip(), completes);
  });

  testWidgets('pendingFinishedTrips answers', skip: _notIos, (tester) async {
    final pending = await CoreBridge().pendingFinishedTrips();
    expect(pending, isA<List<FinishedTripMsg>>());
  });
}
