// T28 I01, I03 (I02 is manual: see the end of this file). Android emulator or
// device API 34+, dev flavor, location granted beforehand
// (P = android.permission):
//   adb shell pm grant app.napstop.dev P.ACCESS_FINE_LOCATION
//   adb shell pm grant app.napstop.dev P.ACCESS_COARSE_LOCATION
//   adb shell pm grant app.napstop.dev P.POST_NOTIFICATIONS
//   flutter test integration_test/t28_history_settings_test.dart -d <id>
// Any device language (T28.2 #4): I03 forces vi and reads its text from the
// ARB. Every bridge call goes through the app container's bridge: a second
// CoreBridge would take the one native tripUpdates sink (T28.2 #2).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/tracking/presentation/tracking_screen.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import 'support/sim_expectations.dart';

/// The app's providers, disposed at tear-down. Its [coreBridgeProvider] is
/// the only bridge of the test.
ProviderContainer _newContainer(String initialLocation) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [startupLocationProvider.overrideWithValue(initialLocation)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Sets the app language and waits until it is on disk (the next test of
/// this file starts from what is saved).
Future<void> _setLanguage(
  ProviderContainer container,
  AppLanguage language,
) async {
  final settings = container.read(appSettingsProvider.notifier)
    ..setDisplay(
      container.read(appSettingsProvider).display.copyWith(language: language),
    );
  await settings.flush();
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NapStopApp(flavor: AppFlavor.dev),
    ),
  );
  await tester.pumpAndSettle();
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

/// Pumps frames until [f] is gone or [timeout] passes (a route transition
/// only runs while the test pumps).
Future<void> _waitGone(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (f.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(f, findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'I01 hidden entry → bus 60× → alarm → dismiss → history (English)',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      final container = _newContainer(AppRoutes.settings);
      final bridge = container.read(coreBridgeProvider);
      await cleanSlate(bridge);
      await _pumpApp(tester, container);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      // LIFO: the language goes back to "system" and the subscription is
      // cancelled before the container is disposed.
      addTearDown(sub.cancel);
      addTearDown(() => _setLanguage(container, AppLanguage.system));

      // Screen 12 is a lazy list: the language rows are below the fold.
      final english = find.text('English');
      await tester.scrollUntilVisible(
        english,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await _tap(tester, english);
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
      // Screen 4 opens on StartSucceeded; screen 3 must leave the tree now,
      // while the test still pumps: later waits are futures only, and a
      // half-done `go` transition kept its destination card in the tree
      // next to the history row (T28.2 test report #1).
      await _waitFor(tester, find.byType(TrackingScreen));
      await _waitGone(tester, find.byType(AlarmSettingsScreen));

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
    tester.platformDispatcher
      ..localesTestValue = const [Locale('vi', 'VN')]
      ..localeTestValue = const Locale('vi', 'VN');
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    // The app's real database: the row is deleted at the end.
    final container = _newContainer(AppRoutes.history);
    await cleanSlate(container.read(coreBridgeProvider));
    // "Theo ngôn ngữ máy" (= vi above), whatever an earlier test saved.
    await _setLanguage(container, AppLanguage.system);
    final unknown = lookupAppLocalizations(const Locale('vi'))
        .historyOutcomeUnknown;
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
    await _waitFor(tester, find.text(unknown));
    // Screen 11 derives "unknown" before HistorySync stamps endedAt (D4):
    // poll the row (T28.2 test report #4).
    final repo = container.read(tripsRepositoryProvider);
    var row = await repo.byId(id);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (row?.endedAtMs == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      row = await repo.byId(id);
    }
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
