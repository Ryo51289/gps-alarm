/// Subtitle of the pre-alert row: when the soft buzz will come (T25 §2.4,
/// mirrors the zones of T10 §4.6).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';

/// Seconds to whole minutes, rounding half up.
int minutesOf(int seconds) => (seconds + 30) ~/ 60;

@immutable
sealed class PreAlertHint {
  const new();
}

/// "Rung khẽ khi còn N phút".
final class PreAlertAtMinutes extends PreAlertHint {
  const new(this.minutes);

  final int minutes;

  @override
  bool operator ==(Object other) =>
      other is PreAlertAtMinutes && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => 'PreAlertAtMinutes($minutes)';
}

/// "Rung khẽ khi còn N km".
final class PreAlertAtDistance extends PreAlertHint {
  const new(this.meters);

  final int meters;

  @override
  bool operator ==(Object other) =>
      other is PreAlertAtDistance && other.meters == meters;

  @override
  int get hashCode => meters.hashCode;

  @override
  String toString() => 'PreAlertAtDistance($meters)';
}

/// Time mode whose threshold is already early enough: no pre-alert.
final class PreAlertSkipped extends PreAlertHint {
  const new(this.thresholdMin);

  final int thresholdMin;

  @override
  bool operator ==(Object other) =>
      other is PreAlertSkipped && other.thresholdMin == thresholdMin;

  @override
  int get hashCode => thresholdMin.hashCode;

  @override
  String toString() => 'PreAlertSkipped($thresholdMin)';
}

PreAlertHint preAlertHint(TripSettings s, AlarmSettingsParams p) =>
    switch (s.mode) {
      AlarmModeMsg.distance => PreAlertAtDistance(
        math.max(
          p.preAlertDistanceFactor * s.distanceThresholdM,
          p.preAlertMinDistanceM,
        ),
      ),
      AlarmModeMsg.time =>
        p.preAlertLeadS - s.timeThresholdMin * 60 >= p.preAlertMinGapS
            ? PreAlertAtMinutes(minutesOf(p.preAlertLeadS))
            : PreAlertSkipped(s.timeThresholdMin),
      AlarmModeMsg.smart => PreAlertAtMinutes(minutesOf(p.preAlertLeadS)),
    };
