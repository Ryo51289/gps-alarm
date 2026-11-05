// T28 I01, I03 (I02 is manual: see the end of this file). Android emulator or
// device API 34+, dev flavor, location granted beforehand
// (P = android.permission):
//   adb shell pm grant app.napstop.dev P.ACCESS_FINE_LOCATION
//   adb shell pm grant app.napstop.dev P.ACCESS_COARSE_LOCATION
//   adb shell pm grant app.napstop.dev P.POST_NOTIFICATIONS
//   flutter test integration_test/t28_history_settings_test.dart -d <id>
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';

import 'support/sim_expectations.dart';

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  String initialLocation = AppRoutes.settings,
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [startupLocationProvider.overrideWithValue(initialLocation)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NapStopApp(flavor: AppFlavor.dev),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Pumps frames until [f] is found or [timeout] passes.
Future<void> _waitFor(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TimeoutException('not found: $f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final bridge = CoreBridge();

  testWidgets(
    'I01 hidden entry → bus 60× → alarm → dismiss → history (English)',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      await cleanSlate(bridge);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);
      final container = await _pumpApp(tester);

      await _tap(tester, find.text('English'));
      final logo = find.text('NapStop');
      await tester.ensureVisible(logo);
      await tester.pumpAndSettle();
      final g = await tester.startGesture(tester.getCenter(logo));
      await tester.pump(const Duration(milliseconds: 3100));
      await g.up();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('BRT01 bus (Hanoi)'));
      await _tap(tester, find.text('60×'));
      await _tap(tester, find.text('Continue'));
      await _tap(tester, find.text('Distance'));
      await _tap(tester, find.text('Start tracking'));

      final alarm = await waitForUpdate<AlarmMsg>(
        received,
        timeout: const Duration(minutes: 2),
      );
      final alarmT = traceSecond(received, alarm.atMs);
      expect(alarm.reason, AlarmReasonMsg.distance);
      expect(
        alarmT,
        inInclusiveRange(kBusAlarmNotBefore, kBusAlarmNotAfter + kFgsSlackS),
      );
      final trip = (await bridge.currentTrip())!;
      await bridge.dismiss(trip.config.tripId);
      await waitForUpdate<TripEndedMsg>(received);

      // Back to the app (the native alarm screen may have covered it).
      container.read(appRouterProvider).go(AppRoutes.history);
      await _waitFor(tester, find.text('Woke up on time'));
      expect(find.text('Nhà chờ BRT Yên Nghĩa'), findsOneWidget);
      expect(find.text('Simulated'), findsOneWidget);
      expect(find.byTooltip('Set up this trip again'), findsNothing);
      expect(await bridge.pendingFinishedTrips(), isEmpty);
    },
  );

  testWidgets('I03 an orphan row is marked "Không rõ kết quả"', (tester) async {
    await cleanSlate(bridge);
    // The app's real database: the row is deleted at the end.
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [startupLocationProvider.overrideWithValue(AppRoutes.history)],
    );
    addTearDown(container.dispose);
    final id = 'i03-${DateTime.now().millisecondsSinceEpoch}';
    final startedAt = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .millisecondsSinceEpoch;
    await container
        .read(tripsRepositoryProvider)
        .insertStarted(
          TripRecord.started(
            id: id,
            draft: const TripDraft(
              destination: TripDestination(
                name: 'Ga I03',
                lat: 21,
                lng: 105.8,
                kind: DestinationKind.train,
              ),
              source: DestinationSource.station,
            ),
            alarm: const TripAlarmChoice(
              mode: AlarmModeMsg.smart,
              preAlertEnabled: true,
            ),
            startedAtMs: startedAt,
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NapStopApp(flavor: AppFlavor.dev),
      ),
    );
    await _waitFor(tester, find.text('Không rõ kết quả'));
    final row = await container.read(tripsRepositoryProvider).byId(id);
    expect(row!.endedAtMs, isNotNull);
    expect(row.result, isNull);
    await container.read(tripsRepositoryProvider).delete(id);
  });
}

// I02 (manual, needs `dumpsys`): app in English, start a simulated
// `coach_md_tb` trip at 60× from screen 12, then
//   adb shell dumpsys notification --noredact | grep -A3 napstop
// → the ongoing title starts with "Simulated trip to", and
//   adb shell dumpsys notification | grep -A2 napstop_alarm
// → channel `napstop_alarm` is named "Alarm".
