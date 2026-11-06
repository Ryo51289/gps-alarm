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
// The trip result is read from TripEndedMsg on the APP's bridge (T28.2 #1):
// since T28 the app's HistorySync drains and acks pendingFinishedTrips on
// every TripEndedMsg, so the queue is already empty when the test looks.
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

/// A launched trip: the app's bridge, the trip id and every update the
/// app's bridge delivered since screen 4 opened.
typedef _Launched = ({
  CoreBridge bridge,
  String tripId,
  List<TripUpdateMsg> received,
});

/// Starts a simulated trip, then the app: `TripLaunchScope` opens screen 4.
/// The setup bridge only calls methods before the app runs; updates are
/// followed on the app's own bridge (one native sink, T28.2 #2).
Future<_Launched> _launchWithTrip(
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
  final received = <TripUpdateMsg>[];
  final sub = bridge.updates.listen(received.add);
  addTearDown(sub.cancel);
  return (bridge: bridge, tripId: tripId, received: received);
}

/// The TripEndedMsg of the launched trip (the app acks the native queue).
Future<FinishedTripMsg> _ended(_Launched l, {int from = 0}) async =>
    (await waitForUpdate<TripEndedMsg>(
      l.received,
      from: from,
      test: (m) => m.trip.tripId == l.tripId,
    )).trip;

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
      final (:bridge, :tripId, received: _) = await _launchWithTrip(
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
      final (:bridge, :tripId, received: _) = await _launchWithTrip(
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
    'I03 overshoot at 60x: "Đã qua điểm đến", dismiss → home',
    timeout: const Timeout(Duration(minutes: 9)),
    (tester) async {
      // 60x, not 600x (T28.2): at 600x the emulator often rings GPS_LOST
      // within ~4 s (merge-phase3 #6, left to T18.2), the trip then runs at
      // 1x from too early a trace second and the overshoot comes after the
      // 8 min wait. The UI offers 60x at most anyway. After the first alarm
      // the trip runs at 1x (T18 D3): overshoot ~265-340 s after it.
      final launched = await _launchWithTrip(
        tester,
        traceId: SimTraces.coachGbPhulyOvershoot,
        speed: 60,
        prefix: 'i03',
      );
      await _pumpUntil(
        tester,
        find.text('Đã qua điểm đến'),
        timeout: const Duration(minutes: 8),
      );
      expect(find.textContaining('Đã qua '), findsWidgets);
      final (:bridge, :tripId, :received) = launched;
      final mark = received.length;
      await bridge.dismiss(tripId);
      await _pumpUntil(tester, find.byType(HomeScreen));
      final finished = await _ended(launched, from: mark);
      expect(finished.outcome, TripOutcomeMsg.missed);
      expect(finished.endReason, EndReasonMsg.dismissed);
      await _finish(bridge, tripId);
    },
  );

  testWidgets('I04 bus at 60x: stop with confirmation → home', (tester) async {
    final launched = await _launchWithTrip(
      tester,
      traceId: SimTraces.busHnBrt01,
      speed: 60,
      prefix: 'i04',
    );
    final (:bridge, :tripId, :received) = launched;
    final mark = received.length;
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
    final finished = await _ended(launched, from: mark);
    expect(finished.endReason, EndReasonMsg.userStop);
    expect(finished.outcome, TripOutcomeMsg.cancelled);
    await _finish(bridge, tripId);
  });
}
