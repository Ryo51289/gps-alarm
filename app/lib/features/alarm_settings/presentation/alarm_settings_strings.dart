import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Enum to display string mappings of screen 3 (T25 §6).
extension AlarmSettingsStrings on AppLocalizations {
  /// "1 km", "850 m", "1,5 km" (T22 `formatDistanceShort`).
  String distance(int meters) => formatDistanceShort(meters, localeName);

  /// Under a minute: seconds; otherwise whole minutes, rounded down.
  String leadDuration(int seconds) =>
      seconds < 60 ? commonSeconds(seconds) : commonMinutes(seconds ~/ 60);

  String modeLabel(AlarmModeMsg mode) => switch (mode) {
    AlarmModeMsg.distance => alarmSettingsModeDistance,
    AlarmModeMsg.time => alarmSettingsModeTime,
    AlarmModeMsg.smart => alarmSettingsModeSmart,
  };

  String styleLabel(AlarmStyle style) => switch (style) {
    AlarmStyle.ringAndVibrate => alarmSettingsStyleRing,
    AlarmStyle.vibrateOnly => alarmSettingsStyleVibrate,
    AlarmStyle.headphonesOnly => alarmSettingsStyleHeadphones,
  };

  String styleHint(AlarmStyleHint hint) => switch (hint) {
    AlarmStyleHint.ring => alarmSettingsStyleRingHint,
    AlarmStyleHint.ringNoRamp => alarmSettingsStyleRingHintNoRamp,
    AlarmStyleHint.ringNoSilent => alarmSettingsStyleRingHintNoSilent,
    AlarmStyleHint.vibrate => alarmSettingsStyleVibrateHint,
    AlarmStyleHint.headphones => alarmSettingsStyleHeadphonesHint,
  };

  String dismissLabel(DismissMethodMsg method) => switch (method) {
    DismissMethodMsg.swipe => alarmSettingsDismissSwipe,
    DismissMethodMsg.shake => alarmSettingsDismissShake,
    DismissMethodMsg.math => alarmSettingsDismissMath,
  };

  String preAlertSubtitle(PreAlertHint hint) => switch (hint) {
    PreAlertAtMinutes(:final minutes) => alarmSettingsPreAlertMinutes(minutes),
    PreAlertAtDistance(:final meters) => alarmSettingsPreAlertDistance(
      distance(meters),
    ),
    PreAlertSkipped(:final thresholdMin) => alarmSettingsPreAlertSkipped(
      thresholdMin,
    ),
  };

  /// "Báo lại tối đa 1 lần, sau 1 phút" or "Không có báo lại".
  String snoozeNote(AlarmSettingsParams p) {
    if (p.maxSnoozes == 0) {
      return alarmSettingsSnoozeNone;
    }
    final interval = p.snoozeS % 60 == 0
        ? commonMinutes(p.snoozeS ~/ 60)
        : commonSeconds(p.snoozeS);
    return alarmSettingsSnoozeNote(p.maxSnoozes, interval);
  }

  /// Bold value of the summary line.
  String summaryValue(TripSettings s, AlarmSettingsParams p) =>
      switch (s.mode) {
        AlarmModeMsg.distance => alarmSettingsSummaryDistance(
          distance(s.distanceThresholdM),
        ),
        AlarmModeMsg.time => alarmSettingsSummaryTime(s.timeThresholdMin),
        AlarmModeMsg.smart => alarmSettingsSummarySmart(
          minutesOf(p.smartTargetS),
        ),
      };

  String shortDistanceWarning(ShortDistanceInfo info) =>
      alarmSettingsShortDistanceWarning(
        info.vehicle.name,
        info.speedKmh,
        distance(info.thresholdM),
        leadDuration(info.leadS),
      );

  String requirementLabel(StartRequirement r) => switch (r) {
    StartRequirement.location => alarmSettingsBlockedLocation,
    StartRequirement.precise => alarmSettingsBlockedPrecise,
    StartRequirement.locationServices => alarmSettingsBlockedServices,
    StartRequirement.alarmChannel => alarmSettingsBlockedAlarmChannel,
  };

  String startError(StartError e) => switch (e) {
    StartError.tripActive => alarmSettingsErrorTripActive,
    StartError.notForeground => alarmSettingsErrorNotForeground,
    StartError.simulationUnavailable => alarmSettingsErrorSimulation,
    StartError.invalidDestination => alarmSettingsErrorInvalidDestination,
    StartError.timeout => alarmSettingsErrorTimeout,
    StartError.generic => alarmSettingsErrorGeneric,
  };
}

/// Subtitle of the destination card: "Ga tàu · Quảng Trị", the kind alone,
/// the detail alone (address, pin) or null.
String? destinationSubtitle(
  AppLocalizations l,
  DestinationKind kind,
  String? detail,
) {
  final kindLabel = switch (kind) {
    DestinationKind.train => l.stationKindTrain,
    DestinationKind.coach => l.stationKindCoach,
    DestinationKind.bus => l.stationKindBus,
    DestinationKind.address || DestinationKind.pin => null,
  };
  final d = detail?.trim();
  final hasDetail = d != null && d.isNotEmpty;
  if (kindLabel == null) {
    return hasDetail ? d : null;
  }
  return hasDetail ? l.destinationRowSubtitle(kindLabel, d) : kindLabel;
}
