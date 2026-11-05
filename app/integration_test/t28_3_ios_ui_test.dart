// T28.3 PI01-PI03 (docs/specs/T28.3.md): the Flutter screens on the iOS
// Simulator, real app and real bridge. Debug build (NAPSTOP_DIAG) with the
// fake alarm port of T17 (`napstop.diag.fakeAlarms`, set by
// app/ios/scripts/ci-sim.sh), location granted. The ios-sim job sets the
// simulated location to `_hereLat, _hereLng` (integration_test/ios_suite.txt):
// PI02 starts a real trip whose destination is that point (T17 IC04), so the
// alarm rings at once. Skipped on Android. Texts come from the ARB of the
// running locale; nothing logs a destination or a coordinate.
// By hand on a Mac:
//   xcrun simctl location <udid> set 17.4689199,106.5997285
//   flutter test integration_test/t28_3_ios_ui_test.dart -d <udid>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm/data/maps_launcher.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';
import 'package:napstop/features/alarm/presentation/alarm_fallback_screen.dart';
import 'package:napstop/features/alarm/presentation/overshoot_screen.dart';
import 'package:napstop/features/alarm/presentation/widgets/swipe_to_stop_bar.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/settings/presentation/settings_screen.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import 'support/sim_expectations.dart';

final bool _notIos = !Platform.isIOS;

/// Ga Đồng Hới (fixtures/traces/train_hn_dh.expect.json destination); must
/// match the point of this file in integration_test/ios_suite.txt.
const double _hereLat = 17.4689199;
const double _hereLng = 106.5997285;

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

/// The app's providers, disposed at tear-down. Its [coreBridgeProvider] is
/// the only bridge of the test (one native tripUpdates sink, T28.2 #2).
ProviderContainer _newContainer(
  String initialLocation, {
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      startupLocationProvider.overrideWithValue(initialLocation),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NapStopApp(flavor: AppFlavor.dev),
      ),
    );

/// Pumps frames until [done] or [timeout]; true when [done].
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      return false;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

AppLocalizations _l10n(WidgetTester tester, Finder screen) =>
    AppLocalizations.of(tester.element(screen.first));

TripConfigMsg _config(String tripId) => TripConfigMsg(
  tripId: tripId,
  destinationName: 'Ga Đồng Hới',
  mode: AlarmModeMsg.distance,
  distanceThresholdM: 1000,
  preAlertEnabled: false,
  vehicleHint: VehicleKindMsg.train,
  alarm: AlarmSettingsMsg(
    soundId: 'default',
    volume: 0.8,
    rampUp: true,
    vibration: VibrationMsg.medium,
    flash: false,
    preferHeadphones: false,
    // Android-only on iOS (D4): sent, ignored by the native side.
    dismissMethod: DismissMethodMsg.shake,
  ),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PI01 screen 12: no volume slider, iOS notes; "Nghe thử" horn plays',
    skip: _notIos,
    (tester) async {
      final container = _newContainer(AppRoutes.settings);
      await _pumpApp(tester, container);
      expect(
        await _pumpUntil(
          tester,
          () =>
              find.byType(SettingsScreen).evaluate().isNotEmpty &&
              container.read(appSettingsProvider).loaded,
        ),
        isTrue,
      );
      final settings = container.read(appSettingsProvider.notifier);
      final alarm = container.read(appSettingsProvider).alarm;
      if (alarm.soundId != 'horn') {
        settings.setAlarm(alarm.copyWith(soundId: 'horn'));
        await settings.flush();
      }
      await tester.pumpAndSettle();
      final l = _l10n(tester, find.byType(SettingsScreen));

      expect(find.byType(Slider), findsNothing);
      expect(find.text(l.settingsVolumeIosNote), findsOneWidget);
      expect(find.text(l.settingsAlarmIosOptionsNote), findsOneWidget);
      expect(find.text(l.settingsRampUp), findsNothing);
      expect(find.text(l.settingsDismiss), findsNothing);

      await tester.tap(find.text(l.settingsPreview));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l.settingsPreviewFailed), findsNothing);
      expect(find.text(l.settingsPreviewStop), findsOneWidget);
      await tester.tap(find.text(l.settingsPreviewStop));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(l.settingsPreview), findsOneWidget);
    },
  );

  testWidgets(
    'PI02 alarm while the app is open: Flutter screen 5 within 6 s, no '
    '"Mở màn báo thức"; swipe → TripEndedMsg',
    skip: _notIos,
    timeout: const Timeout(Duration(minutes: 4)),
    (tester) async {
      final container = _newContainer(AppRoutes.home);
      final bridge = container.read(coreBridgeProvider);
      await cleanSlate(bridge);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);
      await _pumpApp(tester, container);
      await tester.pump(const Duration(seconds: 1));

      final tripId = _id('pi02');
      addTearDown(() async {
        if ((await bridge.currentTrip())?.config.tripId == tripId) {
          await bridge.stopTrip(tripId);
        }
      });
      await bridge.startTrip(
        _config(tripId),
        destLat: _hereLat,
        destLng: _hereLng,
      );

      AlarmMsg? alarm;
      expect(
        await _pumpUntil(tester, () {
          alarm ??= received
              .whereType<AlarmMsg>()
              .where((a) => a.tripId == tripId && a.ringNow)
              .firstOrNull;
          return alarm != null;
        }, timeout: const Duration(seconds: 90)),
        isTrue,
        reason: 'no AlarmMsg',
      );
      final alarmSeen = DateTime.now();
      // Review T28.3 (note for tester, T17.2 AM07): record whether the app
      // stays `resumed` while the AlarmKit alert is up. If the system UI
      // takes the app out of `resumed`, screen 5 is not pushed (T27 D1) and
      // PI02 fails on a wrong assumption, not on an app bug.
      final lifecycle = <String>['atAlarm:${binding.lifecycleState?.name}'];
      final listener = AppLifecycleListener(
        onStateChange: (s) => lifecycle.add(s.name),
      );
      addTearDown(listener.dispose);
      // T27 D1: 4 s grace, then showAlarmScreen = false (T17.2 D9) → /alarm.
      final shown = await _pumpUntil(
        tester,
        () => find.byType(AlarmFallbackScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 6),
      );
      binding.reportData = {'pi02Lifecycle': lifecycle};
      // One line in the CI log (it-*.tail.log), pass or fail; no location.
      debugPrint('T28_3_PI02_LIFECYCLE shown=$shown $lifecycle');
      expect(
        shown,
        isTrue,
        reason:
            'screen 5 not shown within 6 s; lifecycle since AlarmMsg: '
            '$lifecycle',
      );
      expect(
        DateTime.now().difference(alarmSeen),
        lessThanOrEqualTo(const Duration(seconds: 6)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final l = _l10n(tester, find.byType(AlarmFallbackScreen));
      expect(find.text(l.alarmOpenAlarmScreen), findsNothing);
      expect(find.text(l.alarmFallbackNoteIos), findsOneWidget);

      final bar = find.byType(SwipeToStopBar);
      await tester.ensureVisible(bar);
      await tester.pump(const Duration(milliseconds: 300));
      final mark = received.length;
      final rect = tester.getRect(bar);
      await tester.dragFrom(
        Offset(rect.left + 36, rect.center.dy),
        Offset((rect.width - 72) * 1.1, 0),
      );
      TripEndedMsg? ended;
      expect(
        await _pumpUntil(tester, () {
          ended ??= received
              .skip(mark)
              .whereType<TripEndedMsg>()
              .where((e) => e.trip.tripId == tripId)
              .firstOrNull;
          return ended != null;
        }),
        isTrue,
        reason: 'no TripEndedMsg after the swipe',
      );
      expect(await bridge.currentTrip(), isNull);
      await _pumpUntil(
        tester,
        () => find.byType(AlarmFallbackScreen).evaluate().isEmpty,
        timeout: const Duration(seconds: 5),
      );
      expect(find.byType(AlarmFallbackScreen), findsNothing);
      await bridge.ackFinishedTrips([tripId]);
    },
  );

  testWidgets(
    'PI03 screen 8: "Chỉ đường quay lại" opens the Google Maps URL (T27 D8)',
    skip: _notIos,
    (tester) async {
      final opened = <Uri>[];
      final container = _newContainer(
        AppRoutes.home,
        overrides: [
          mapsLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      final tripId = _id('pi03');
      const destination = TripDestination(
        name: 'Ga Đồng Hới',
        lat: _hereLat,
        lng: _hereLng,
        kind: DestinationKind.train,
      );
      await container
          .read(tripsRepositoryProvider)
          .insertStarted(
            TripRecord.started(
              id: tripId,
              draft: const TripDraft(
                destination: destination,
                source: DestinationSource.station,
              ),
              alarm: const TripAlarmChoice(
                mode: AlarmModeMsg.distance,
                distanceThresholdM: 1000,
                preAlertEnabled: false,
              ),
              startedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      addTearDown(() => container.read(tripsRepositoryProvider).delete(tripId));
      await _pumpApp(tester, container);
      await tester.pump(const Duration(seconds: 1));
      container
          .read(appRouterProvider)
          .go(OvershootArgs(tripId: tripId, pastM: 1300).toLocation());
      expect(
        await _pumpUntil(
          tester,
          () => find.byType(OvershootScreen).evaluate().isNotEmpty,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      final l = _l10n(tester, find.byType(OvershootScreen));
      final button = find.text(l.overshootRouteBack);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(opened, [routeBackUri(_hereLat, _hereLng)]);
      expect(opened.single.toString(), contains('%2C'));
    },
  );
}
