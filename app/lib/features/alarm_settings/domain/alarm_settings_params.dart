/// The engine parameters screen 3 shows or uses (T25 §2.3): a subset of
/// T10 §5 read from the Remote Config override with the engine's rules, so
/// the warning and the texts on screen match what the engine will do.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/telemetry/remote_config/strict_json.dart';
import 'package:napstop/core/text/kotlin_blank.dart';

/// Name, default and valid range of one integer parameter (T10 §5, type I).
typedef _IntSpec = ({String key, int min, int max});

const List<_IntSpec> _specs = [
  (key: 'shortDistanceWarnS', min: 60, max: 600),
  (key: 'expectedSpeedKmhTrain', min: 5, max: 150),
  (key: 'expectedSpeedKmhCoach', min: 5, max: 150),
  (key: 'expectedSpeedKmhBus', min: 5, max: 150),
  (key: 'expectedSpeedKmhUnknown', min: 5, max: 150),
  (key: 'smartTargetS', min: 300, max: 1200),
  (key: 'preAlertLeadS', min: 600, max: 3600),
  (key: 'preAlertDistanceFactor', min: 2, max: 10),
  (key: 'preAlertMinDistanceM', min: 1000, max: 10000),
  (key: 'preAlertMinGapS', min: 0, max: 900),
  (key: 'lowBatteryAlarmPct', min: 2, max: 20),
  (key: 'lowBatteryEarlierPct', min: 5, max: 40),
  (key: 'snoozeS', min: 30, max: 600),
  (key: 'maxSnoozes', min: 0, max: 3),
  // T26 D11: screen 6 text "Còn dưới {minutes} phút là báo thức kêu luôn".
  (key: 'gpsLostAlarmEtaS', min: 300, max: 3600),
];

@immutable
final class AlarmSettingsParams {
  const new({
    this.shortDistanceWarnS = 240,
    this.expectedSpeedKmhTrain = 55,
    this.expectedSpeedKmhCoach = 60,
    this.expectedSpeedKmhBus = 20,
    this.expectedSpeedKmhUnknown = 60,
    this.smartTargetS = 600,
    this.preAlertLeadS = 1800,
    this.preAlertDistanceFactor = 5,
    this.preAlertMinDistanceM = 3000,
    this.preAlertMinGapS = 300,
    this.lowBatteryAlarmPct = 5,
    this.lowBatteryEarlierPct = 15,
    this.snoozeS = 60,
    this.maxSnoozes = 1,
    this.gpsLostAlarmEtaS = 1200,
  });

  /// Reads [json] like `EngineParamsFactory.fromOverrides` (T10 §5, T12
  /// §7.2 + C12) restricted to these keys:
  /// - null, blank (Kotlin `isBlank`), malformed for the engine grammar, or
  ///   not an object → [defaults];
  /// - per key: a number, finite, integral, inside its range → its value
  ///   (-0.0 → 0); anything else keeps the default; unknown keys are
  ///   ignored; a duplicate key keeps its last value;
  /// - G4: `lowBatteryAlarmPct >= lowBatteryEarlierPct` → both default.
  ///
  /// Never throws, never logs values.
  factory fromOverrideJson(String? json) {
    if (json == null || isBlankLikeKotlin(json)) {
      return defaults;
    }
    final Object? tree;
    try {
      tree = parseStrictJson(json);
    } on FormatException {
      return defaults;
    }
    if (tree is! Map<String, Object?>) {
      return defaults;
    }
    final values = <String, int>{
      for (final spec in _specs)
        spec.key: ?_parseI(tree[spec.key], spec.min, spec.max),
    };
    // G4 (T10 §5): the earlier battery alarm must come first.
    final alarmPct =
        values['lowBatteryAlarmPct'] ?? defaults.lowBatteryAlarmPct;
    final earlierPct =
        values['lowBatteryEarlierPct'] ?? defaults.lowBatteryEarlierPct;
    if (alarmPct >= earlierPct) {
      values
        ..remove('lowBatteryAlarmPct')
        ..remove('lowBatteryEarlierPct');
    }
    const d = defaults;
    return AlarmSettingsParams(
      shortDistanceWarnS: values['shortDistanceWarnS'] ?? d.shortDistanceWarnS,
      expectedSpeedKmhTrain:
          values['expectedSpeedKmhTrain'] ?? d.expectedSpeedKmhTrain,
      expectedSpeedKmhCoach:
          values['expectedSpeedKmhCoach'] ?? d.expectedSpeedKmhCoach,
      expectedSpeedKmhBus:
          values['expectedSpeedKmhBus'] ?? d.expectedSpeedKmhBus,
      expectedSpeedKmhUnknown:
          values['expectedSpeedKmhUnknown'] ?? d.expectedSpeedKmhUnknown,
      smartTargetS: values['smartTargetS'] ?? d.smartTargetS,
      preAlertLeadS: values['preAlertLeadS'] ?? d.preAlertLeadS,
      preAlertDistanceFactor:
          values['preAlertDistanceFactor'] ?? d.preAlertDistanceFactor,
      preAlertMinDistanceM:
          values['preAlertMinDistanceM'] ?? d.preAlertMinDistanceM,
      preAlertMinGapS: values['preAlertMinGapS'] ?? d.preAlertMinGapS,
      lowBatteryAlarmPct: values['lowBatteryAlarmPct'] ?? d.lowBatteryAlarmPct,
      lowBatteryEarlierPct:
          values['lowBatteryEarlierPct'] ?? d.lowBatteryEarlierPct,
      snoozeS: values['snoozeS'] ?? d.snoozeS,
      maxSnoozes: values['maxSnoozes'] ?? d.maxSnoozes,
      gpsLostAlarmEtaS: values['gpsLostAlarmEtaS'] ?? d.gpsLostAlarmEtaS,
    );
  }

  static const AlarmSettingsParams defaults = AlarmSettingsParams();

  final int shortDistanceWarnS;
  final int expectedSpeedKmhTrain;
  final int expectedSpeedKmhCoach;
  final int expectedSpeedKmhBus;
  final int expectedSpeedKmhUnknown;
  final int smartTargetS;
  final int preAlertLeadS;
  final int preAlertDistanceFactor;
  final int preAlertMinDistanceM;
  final int preAlertMinGapS;
  final int lowBatteryAlarmPct;
  final int lowBatteryEarlierPct;
  final int snoozeS;
  final int maxSnoozes;

  /// T10 §5: while GPS is lost, an estimated ETA below this rings (T26).
  final int gpsLostAlarmEtaS;

  int expectedSpeedKmh(VehicleKindMsg vehicle) => switch (vehicle) {
    VehicleKindMsg.train => expectedSpeedKmhTrain,
    VehicleKindMsg.coach => expectedSpeedKmhCoach,
    VehicleKindMsg.bus => expectedSpeedKmhBus,
    VehicleKindMsg.unknown => expectedSpeedKmhUnknown,
  };

  @override
  bool operator ==(Object other) =>
      other is AlarmSettingsParams &&
      other.shortDistanceWarnS == shortDistanceWarnS &&
      other.expectedSpeedKmhTrain == expectedSpeedKmhTrain &&
      other.expectedSpeedKmhCoach == expectedSpeedKmhCoach &&
      other.expectedSpeedKmhBus == expectedSpeedKmhBus &&
      other.expectedSpeedKmhUnknown == expectedSpeedKmhUnknown &&
      other.smartTargetS == smartTargetS &&
      other.preAlertLeadS == preAlertLeadS &&
      other.preAlertDistanceFactor == preAlertDistanceFactor &&
      other.preAlertMinDistanceM == preAlertMinDistanceM &&
      other.preAlertMinGapS == preAlertMinGapS &&
      other.lowBatteryAlarmPct == lowBatteryAlarmPct &&
      other.lowBatteryEarlierPct == lowBatteryEarlierPct &&
      other.snoozeS == snoozeS &&
      other.maxSnoozes == maxSnoozes &&
      other.gpsLostAlarmEtaS == gpsLostAlarmEtaS;

  @override
  int get hashCode => Object.hash(
    shortDistanceWarnS,
    expectedSpeedKmhTrain,
    expectedSpeedKmhCoach,
    expectedSpeedKmhBus,
    expectedSpeedKmhUnknown,
    smartTargetS,
    preAlertLeadS,
    preAlertDistanceFactor,
    preAlertMinDistanceM,
    preAlertMinGapS,
    lowBatteryAlarmPct,
    lowBatteryEarlierPct,
    snoozeS,
    maxSnoozes,
    gpsLostAlarmEtaS,
  );

  @override
  String toString() => 'AlarmSettingsParams(<values>)';
}

/// Type I of T10 §5: only a JSON number that is finite, integral and inside
/// [min, max] (checked before the conversion, so -0.0 gives 0).
int? _parseI(Object? v, int min, int max) {
  if (v is! JsonNumberLexeme) {
    return null;
  }
  final d = v.asDouble();
  if (!d.isFinite || d != d.truncateToDouble() || d < min || d > max) {
    return null;
  }
  return d.toInt();
}

/// T10 §4.7, integers only (bit-identical to Kotlin/Swift `TripRules`): the
/// time to cover [thresholdM] at the expected speed is below
/// `shortDistanceWarnS`.
bool shortDistanceWarning(
  int thresholdM,
  VehicleKindMsg vehicle,
  AlarmSettingsParams p,
) => thresholdM * 36 < p.shortDistanceWarnS * p.expectedSpeedKmh(vehicle) * 10;

/// Seconds to cover [thresholdM] at [speedKmh], rounded down (display only).
int shortDistanceLeadS(int thresholdM, int speedKmh) =>
    (thresholdM * 36) ~/ (speedKmh * 10);
