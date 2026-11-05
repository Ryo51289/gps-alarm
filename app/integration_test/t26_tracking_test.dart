// T26 I01-I04: screen 4 on simulated trips (T18) through the real runtime.
// Android emulator/device API 34+, dev flavor, permissions granted first
// (P = android.permission), screen unlocked and kept on:
//   adb shell pm grant app.napstop.dev P.ACCESS_FINE_LOCATION
//   adb shell pm grant app.napstop.dev P.ACCESS_COARSE_LOCATION
//   adb shell pm grant app.napstop.dev P.POST_NOTIFICATIONS
//   adb shell svc power stayon true
//   flutter test integration_test/t26_tracking_test.dart -d <device-id>
// The native alarm screen (AlarmActivity) may cover Flutter; finders still
// work on the widget tree and the alarm is dismissed through the bridge (R4).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/features/tracking/presentation/tracking_screen.dart';
import 'package:napstop/main.dart' as app;

import 'support/sim_expectations.dart';

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
}

/// Starts a simulated trip, then the app: `TripLaunchScope` opens screen 4.
Future<(CoreBridge, String)> _launchWithTrip(
  WidgetTester tester, {
  required String traceId,
  required double speed,
  required String prefix,
  int distanceThresholdM = 1000,
}) async {
  tester.platformDispatcher
    ..localesTestValue = const [Locale('vi', 'VN')]
    ..localeTestValue = const Locale('vi', 'VN');
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final setup = CoreBridge();
  await cleanSlate(setup);
  final trace = (await loadCatalog()).byId(traceId)!;
  final tripId = _id(prefix);
  await startSim(
    setup,
    simConfig(tripId, trace, distanceThresholdM: distanceThresholdM),
    trace,
    speed,
  );
  // Tester fix (T26 test report): a fresh install opens screen 0, where
  // TripLaunchScope rightly does not navigate (D12). Pass screen 0 first.
  await markOnboardingCompleted(createOnboardingStore());
  await app.main();
  await _pumpUntil(tester, find.byType(TrackingScreen));
  final bridge = ProviderScope.containerOf(
    tester.element(find.byType(TrackingScreen)),
  ).read(coreBridgeProvider);
  return (bridge, tripId);
}

Future<void> _finish(CoreBridge bridge, String tripId) async {
  final pending = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([
    for (final t in pending)
      if (t.tripId == tripId) t.tripId,
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'I01 train at 600x: screen 4 opens by itself, alarm, dismiss → home',
    timeout: const Timeout(Duration(minutes: 4)),
    (tester) async {
      final handle = tester.ensureSemantics();
      final (bridge, tripId) = await _launchWithTrip(
        tester,
        traceId: SimTraces.trainHnDh,
        speed: 600,
        prefix: 'i01',
      );
      expect(find.text('Chuyến giả lập · tốc độ 600×'), findsOneWidget);
      await _pumpUntil(tester, find.textContaining(' km'));
      expect(find.bySemanticsLabel(RegExp('Đã đi')), findsWidgets);
      await _pumpUntil(
        tester,
        find.text('Đang báo thức'),
        timeout: const Duration(minutes: 2),
      );
      await bridge.dismiss(tripId);
      await _pumpUntil(tester, find.byType(HomeScreen));
      expect(
        find.text('Đã tắt báo thức. Chúc bạn xuống xe an toàn.'),
        findsOneWidget,
      );
      expect(await bridge.currentTrip(), isNull);
      await _finish(bridge, tripId);
      handle.dispose();
    },
  );

  testWidgets(
    'I02 tunnel at 60x: estimated view without speed (screen 6)',
    timeout: const Timeout(Duration(minutes: 12)),
    (tester) async {
      final (bridge, tripId) = await _launchWithTrip(
        tester,
        traceId: SimTraces.coachDnLangcoTunnel,
        speed: 60,
        prefix: 'i02',
      );
      await _pumpUntil(
        tester,
        find.textContaining('Đang ước tính · sai số ±'),
        timeout: const Duration(minutes: 10),
      );
      expect(find.textContaining('~'), findsWidgets);
      expect(find.textContaining('km/h'), findsNothing);
      await bridge.stopTrip(tripId);
      await _pumpUntil(tester, find.byType(HomeScreen));
      await _finish(bridge, tripId);
    },
  );

  testWidgets(
    'I03 overshoot at 600x: "Đã qua điểm đến", dismiss → home',
    timeout: const Timeout(Duration(minutes: 9)),
    (tester) async {
      final (bridge, tripId) = await _launchWithTrip(
        tester,
        traceId: SimTraces.coachGbPhulyOvershoot,
        speed: 600,
        prefix: 'i03',
      );
      await _pumpUntil(
        tester,
        find.text('Đã qua điểm đến'),
        timeout: const Duration(minutes: 8),
      );
      expect(find.textContaining('Đã qua '), findsWidgets);
      await bridge.dismiss(tripId);
      await _pumpUntil(tester, find.byType(HomeScreen));
      final pending = await bridge.pendingFinishedTrips();
      expect(
        pending.singleWhere((t) => t.tripId == tripId).outcome,
        TripOutcomeMsg.missed,
      );
      await _finish(bridge, tripId);
    },
  );

  testWidgets('I04 bus at 60x: stop with confirmation → home', (tester) async {
    final (bridge, tripId) = await _launchWithTrip(
      tester,
      traceId: SimTraces.busHnBrt01,
      speed: 60,
      prefix: 'i04',
    );
    await tester.tap(find.text('Dừng theo dõi'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Dừng theo dõi'),
      ),
    );
    await _pumpUntil(tester, find.byType(HomeScreen));
    expect(find.text('Đã dừng theo dõi.'), findsOneWidget);
    expect(await bridge.currentTrip(), isNull);
    final pending = await bridge.pendingFinishedTrips();
    final finished = pending.singleWhere((t) => t.tripId == tripId);
    expect(finished.endReason, EndReasonMsg.userStop);
    expect(finished.outcome, TripOutcomeMsg.cancelled);
    await _finish(bridge, tripId);
  });
}
