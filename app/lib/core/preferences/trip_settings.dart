/// Per-trip alarm choices of screen 3, shared by T22, T25 and T28 (T25 §2.1).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

/// How the alarm rings. Stored by enum name.
enum AlarmStyle { ringAndVibrate, vibrateOnly, headphonesOnly }

/// Distance chips of screen 3, metres (PRD §4).
const List<int> kDistanceChipsM = [500, 1000, 2000, 5000];

/// Time chips of screen 3, minutes (PRD §4).
const List<int> kTimeChipsMin = [5, 10, 15, 20, 30];

/// Distance slider step, metres.
const int kDistanceStepM = 100;

/// Rounds half up to a multiple of 100 m, then clamps to 200..10000 m.
int normalizeDistanceM(int m) => (((m + 50) ~/ kDistanceStepM) * kDistanceStepM)
    .clamp(kMinDistanceThresholdM, kMaxDistanceThresholdM);

/// The nearest chip of [kTimeChipsMin]; a tie picks the larger chip (earlier
/// alarm, the safe side).
int normalizeTimeMin(int t) {
  var best = kTimeChipsMin.first;
  for (final chip in kTimeChipsMin) {
    if ((chip - t).abs() <= (best - t).abs()) {
      best = chip;
    }
  }
  return best;
}

/// Choices for one trip. Both thresholds are kept, so switching mode keeps
/// them.
@immutable
final class TripSettings {
  const new({
    required this.mode,
    required this.distanceThresholdM,
    required this.timeThresholdMin,
    required this.preAlertEnabled,
    required this.alarmStyle,
    required this.dismissMethod,
  });

  final AlarmModeMsg mode;

  /// 200..10000, multiple of 100 after [normalized].
  final int distanceThresholdM;

  /// One of [kTimeChipsMin] after [normalized].
  final int timeThresholdMin;
  final bool preAlertEnabled;
  final AlarmStyle alarmStyle;
  final DismissMethodMsg dismissMethod;

  /// T10 §2.1 + PRD §4: smart, 1 km, 15 min, pre-alert on; sound + vibrate,
  /// swipe.
  static const TripSettings defaults = TripSettings(
    mode: AlarmModeMsg.smart,
    distanceThresholdM: 1000,
    timeThresholdMin: 15,
    preAlertEnabled: true,
    alarmStyle: AlarmStyle.ringAndVibrate,
    dismissMethod: DismissMethodMsg.swipe,
  );

  TripSettings normalized() => copyWith(
    distanceThresholdM: normalizeDistanceM(distanceThresholdM),
    timeThresholdMin: normalizeTimeMin(timeThresholdMin),
  );

  /// The mode and thresholds of [choice] on top of these settings (restart
  /// of a recent trip, T22), normalized.
  TripSettings withChoice(TripAlarmChoice choice) => copyWith(
    mode: choice.mode,
    distanceThresholdM: choice.distanceThresholdM,
    timeThresholdMin: choice.timeThresholdMin,
    preAlertEnabled: choice.preAlertEnabled,
  ).normalized();

  /// Stored in the history row (T22 `TripRecord`): both thresholds, so a
  /// restart keeps them.
  TripAlarmChoice toAlarmChoice() => TripAlarmChoice(
    mode: mode,
    distanceThresholdM: distanceThresholdM,
    timeThresholdMin: timeThresholdMin,
    preAlertEnabled: preAlertEnabled,
  );

  TripSettings copyWith({
    AlarmModeMsg? mode,
    int? distanceThresholdM,
    int? timeThresholdMin,
    bool? preAlertEnabled,
    AlarmStyle? alarmStyle,
    DismissMethodMsg? dismissMethod,
  }) => TripSettings(
    mode: mode ?? this.mode,
    distanceThresholdM: distanceThresholdM ?? this.distanceThresholdM,
    timeThresholdMin: timeThresholdMin ?? this.timeThresholdMin,
    preAlertEnabled: preAlertEnabled ?? this.preAlertEnabled,
    alarmStyle: alarmStyle ?? this.alarmStyle,
    dismissMethod: dismissMethod ?? this.dismissMethod,
  );

  @override
  bool operator ==(Object other) =>
      other is TripSettings &&
      other.mode == mode &&
      other.distanceThresholdM == distanceThresholdM &&
      other.timeThresholdMin == timeThresholdMin &&
      other.preAlertEnabled == preAlertEnabled &&
      other.alarmStyle == alarmStyle &&
      other.dismissMethod == dismissMethod;

  @override
  int get hashCode => Object.hash(
    mode,
    distanceThresholdM,
    timeThresholdMin,
    preAlertEnabled,
    alarmStyle,
    dismissMethod,
  );

  @override
  String toString() =>
      'TripSettings(${mode.name}, $distanceThresholdM, $timeThresholdMin, '
      '$preAlertEnabled, ${alarmStyle.name}, ${dismissMethod.name})';
}
