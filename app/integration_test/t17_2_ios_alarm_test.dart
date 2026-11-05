// T17.2 AC04 (docs/specs/T17.2.md): the request of the "now" alarm on the
// Simulator carries the snooze button and the default sound, and a snooze from
// Flutter answers SnoozedMsg. Debug build (NAPSTOP_DIAG), fake alarm port
// (`napstop.diag.fakeAlarms`, set by app/ios/scripts/ci-sim.sh): the fake port
// writes a summary of each request (kind, button, sound file; never a title or
// a position) to the standard user defaults, read here through
// shared_preferences. The ios-sim job sets the simulated location to
// `_hereLat, _hereLng` (integration_test/ios_suite.txt). Skipped on Android.
// By hand on a Mac:
//   xcrun simctl location <udid> set 17.4689199,106.5997285
//   flutter test integration_test/t17_2_ios_alarm_test.dart -d <udid>
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

final bool _notIos = !Platform.isIOS;

/// Ga Đồng Hới (fixtures/traces/train_hn_dh.expect.json destination); must
/// match the point of this file in integration_test/ios_suite.txt.
const double _hereLat = 17.4689199;
const double _hereLng = 106.5997285;

/// Written by FakeSystemAlarmsIOS.schedule (NapStopIOS) for kind `now`.
const String _nowSummaryKey = 'flutter.napstop.diag.lastAlarm.now';

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
    dismissMethod: DismissMethodMsg.swipe,
  ),
);

Future<T> _waitFor<T extends TripUpdateMsg>(
  List<TripUpdateMsg> received, {
  bool Function(T)? test,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final item in received) {
      if (item is T && (test == null || test(item))) {
        return item;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('no $T within $timeout');
}

/// Stops a trip left by an earlier test and acknowledges old records.
Future<void> _cleanSlate(CoreBridge bridge) async {
  final leftover = await bridge.currentTrip();
  if (leftover != null) {
    await bridge.stopTrip(leftover.config.tripId);
  }
  final old = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([for (final t in old) t.tripId]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'AC04 now alarm: snooze button + default sound; snooze → SnoozedMsg',
    skip: _notIos,
    (tester) async {
      final bridge = CoreBridge();
      await _cleanSlate(bridge);
      final prefs = SharedPreferencesAsync();
      await prefs.remove(_nowSummaryKey);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);
      final tripId = 'ac04-${DateTime.now().millisecondsSinceEpoch}';
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
      final alarm = await _waitFor<AlarmMsg>(
        received,
        test: (a) => a.tripId == tripId && a.ringNow,
      );
      expect(alarm.snoozeAllowed, isTrue);
      expect(
        await prefs.getString(_nowSummaryKey),
        'secondary=snooze:1;sound=alarm_horn.wav',
      );

      await bridge.snooze(tripId);
      final snoozed = await _waitFor<SnoozedMsg>(
        received,
        test: (s) => s.tripId == tripId,
      );
      expect(snoozed.untilMs - snoozed.atMs, 60000);
      expect(await bridge.consumeLaunchAction(), isNull);
      expect(await bridge.showAlarmScreen(tripId), isFalse);
    },
  );
}
