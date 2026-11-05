import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Display strings of screens 4, 6 and 7 (T26 §8). Values come formatted
/// from the domain layer; units and words only come from ARB.
extension TrackingStrings on AppLocalizations {
  /// "850 m" / "12,3 km".
  String distanceOf(FormattedDistance d) => d.isKm
      ? commonDistanceKm(d.value)
      : commonDistanceMeters(int.parse(d.value));

  /// "~148 km" when [estimated].
  String maybeApprox(String value, {required bool estimated}) =>
      estimated ? trackingApprox(value) : value;

  /// "45 phút", "2 giờ", "2 giờ 10 phút" (§5).
  String durationOf(int minutes) {
    final hm = splitHm(minutes);
    if (hm.hours == 0) {
      return commonMinutes(hm.minutes);
    }
    return hm.minutes == 0
        ? trackingDurationH(hm.hours)
        : trackingDurationHm(hm.hours, hm.minutes);
  }

  /// The reason line of an alarm (T10 §10).
  String alarmCopyText(AlarmCopy copy, String destination) {
    final distance = copy.distance;
    final minutes = copy.minutes;
    final percent = copy.percent;
    return switch (copy.kind) {
      AlarmCopyKind.distance when distance != null => alarmReasonDistance(
        distanceOf(distance),
        destination,
      ),
      AlarmCopyKind.time when minutes != null => alarmReasonTime(
        '$minutes',
        destination,
      ),
      AlarmCopyKind.lowBattery when percent != null => alarmReasonLowBattery(
        '$percent',
      ),
      AlarmCopyKind.gpsLost => alarmReasonGpsLost(destination),
      AlarmCopyKind.passedClosest => alarmReasonPassedClosest(destination),
      AlarmCopyKind.overshoot => alarmReasonOvershoot(destination),
      AlarmCopyKind.snoozeEnd => alarmReasonSnoozeEnd(destination),
      AlarmCopyKind.timeout => alarmReasonTimeout(destination),
      AlarmCopyKind.fallback => alarmReasonFallback(destination),
      AlarmCopyKind.fallbackMissed => alarmReasonFallbackMissed(destination),
      _ => notifAlarmTitle(destination),
    };
  }

  /// "Sẽ báo khi còn …" value of the trip's rule (T25 summary strings).
  String ruleValue(TripConfigMsg c, AlarmSettingsParams p) => switch (c.mode) {
    AlarmModeMsg.distance => alarmSettingsSummaryDistance(
      distanceOf(formatTripDistance(c.distanceThresholdM ?? 0, localeName)),
    ),
    AlarmModeMsg.time => alarmSettingsSummaryTime(c.timeThresholdMin ?? 0),
    AlarmModeMsg.smart => alarmSettingsSummarySmart(minutesOf(p.smartTargetS)),
  };

  String styleLabelOf(AlarmStyleKind style) => switch (style) {
    AlarmStyleKind.ring => alarmSettingsStyleRing,
    AlarmStyleKind.vibrateOnly => alarmSettingsStyleVibrate,
    AlarmStyleKind.headphonesOnly => alarmSettingsStyleHeadphones,
  };

  String batteryNoteOf(TrackingView v) => switch (v.batteryNote) {
    BatteryTileNote.none => '',
    BatteryTileNote.charging => trackingBatteryCharging,
    BatteryTileNote.risk => trackingBatteryRisk,
    BatteryTileNote.enough => trackingBatteryEnough,
    BatteryTileNote.maxSaving => batteryMaxSavingTitle,
    BatteryTileNote.alarmAt5 => trackingBatteryAt(
      v.batteryNotePct ?? v.params.lowBatteryAlarmPct,
    ),
    BatteryTileNote.alarmEarlier => trackingBatteryEarlier,
    BatteryTileNote.low => trackingBatteryLow,
  };
}
