/// T29.2 §4.2: on-device telemetry probe of the "fb" test IPA. Compiled in
/// only with `--dart-define=NAPSTOP_TELEMETRY_PROBE=true` (CI branches
/// `ci/ios-ipa-fb-*`); otherwise [kTelemetryProbe] is a false constant and
/// the call in `main.dart` is tree-shaken away. No Firebase import: it goes
/// through [Telemetry] like every other caller.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/telemetry/telemetry.dart';

/// `--dart-define=NAPSTOP_TELEMETRY_PROBE=true`.
const bool kTelemetryProbe = bool.fromEnvironment('NAPSTOP_TELEMETRY_PROBE');

/// Delay before the probe raises [TelemetryProbeFatal].
const Duration kTelemetryProbeFatalDelay = Duration(seconds: 20);

/// One event per catalog entry (8), fixed values, `simulated = 1` where the
/// event has it.
List<AnalyticsEvent> telemetryProbeEvents() => [
  const TripStartEvent(
    mode: AlarmModeTag.distance,
    threshold: ThresholdTag.d1000,
    vehicleHint: VehicleTag.train,
    destSource: DestSourceTag.station,
    preAlert: true,
    shortDistanceWarning: false,
    battery: BatteryBucket.gt50,
    charging: false,
    simulated: true,
    paramsId: 'default',
  ),
  const TripStartBlockedEvent(
    reason: StartBlockedReason.locationDenied,
    simulated: true,
  ),
  TripEndEvent(
    outcome: TripOutcomeTag.onTime,
    endReason: EndReasonTag.dismissed,
    alarmReason: AlarmReasonTag.distance,
    snoozeCount: 0,
    mode: AlarmModeTag.distance,
    vehicleGuess: VehicleTag.train,
    duration: DurationBucket.lt2h,
    distance: DistanceBucket.lt50km,
    simulated: true,
  ),
  const LowBatteryChoiceEvent(
    choice: BatteryChoiceTag.alarmAt5,
    simulated: true,
  ),
  const OvershootActionEvent(
    action: OvershootActionTag.dismiss,
    simulated: true,
  ),
  const DestinationSelectedEvent(
    source: DestSourceTag.station,
    kind: DestKindTag.train,
  ),
  const PermissionSnapshotEvent(
    location: LocationPermTag.whileInUse,
    precise: true,
    locationServices: true,
    notifications: TriStateTag.granted,
    fullScreenIntent: TriStateTag.na,
    exactAlarm: TriStateTag.na,
    batteryOptIgnored: YesNoNaTag.na,
    alarmKit: AlarmKitTag.granted,
  ),
  const BatteryGuideTestEvent(oem: OemTag.other, result: GuideTestResult.pass),
];

/// Non-fatal of the probe. Its message holds a number shaped like a
/// coordinate on purpose: Crashlytics must show it redacted
/// (`T29.2 probe <num>,<num>`).
final class TelemetryProbeMarker implements SafeDiagnostic {
  const new();

  @override
  String toString() => 'T29.2 probe 21.0285123,105.8542';
}

/// Raised uncaught on purpose; only its type reaches Crashlytics (T29
/// review #1).
final class TelemetryProbeFatal implements Exception {
  const new();
}

bool _ran = false;

/// Lets a test run the probe again in the same isolate.
@visibleForTesting
void resetTelemetryProbe() => _ran = false;

void _raiseUncaughtLater(Duration delay) => unawaited(
  Future<void>.delayed(delay, () => throw const TelemetryProbeFatal()),
);

/// Runs at most once per process. Does nothing (returns false) unless
/// [flavor] is dev, telemetry is configured (not a no-op) and the effective
/// collection has both crash reports and analytics. Otherwise logs
/// [telemetryProbeEvents], records a [TelemetryProbeMarker] non-fatal and a
/// breadcrumb, then asks [raiseLater] to raise [TelemetryProbeFatal] after
/// [fatalDelay] (default: an unawaited delayed future that throws, i.e. an
/// uncaught async error). Returns true when it ran.
bool runTelemetryProbe(
  Telemetry telemetry, {
  required AppFlavor flavor,
  Duration fatalDelay = kTelemetryProbeFatalDelay,
  void Function(Duration delay)? raiseLater,
}) {
  if (_ran || flavor != AppFlavor.dev || telemetry.isNoop) {
    return false;
  }
  final effective = telemetry.consent.effective;
  if (!effective.crash || !effective.analytics) {
    return false;
  }
  _ran = true;
  telemetryProbeEvents().forEach(telemetry.analytics.log);
  telemetry.crash
    ..recordNonFatal(
      const TelemetryProbeMarker(),
      StackTrace.current,
      NonFatalReason.other,
    )
    ..breadcrumb('T29.2 probe');
  (raiseLater ?? _raiseUncaughtLater)(fatalDelay);
  return true;
}
