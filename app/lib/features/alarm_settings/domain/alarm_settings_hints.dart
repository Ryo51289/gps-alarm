/// Pure decisions behind the hints and warnings of screen 3 (T25 §3.2,
/// §3.3), kept out of the widgets.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';

/// Hint under the alarm style cards.
enum AlarmStyleHint { ring, ringNoRamp, ringNoSilent, vibrate, headphones }

/// Whether the alarm rings in Silent mode: Android always (alarm stream);
/// iOS only with AlarmKit (iOS 26+, granted). Unknown yet → true (T25: the
/// Android hint). iOS before 26 is never, whatever the permissions
/// (T28.3 test report #1). Screens that must not claim it while unknown use
/// [ringsInSilentIfKnown].
bool ringsInSilent(PermissionStatusMsg? permissions, DeviceInfoMsg? device) =>
    ringsInSilentIfKnown(permissions, device) ?? true;

/// Like [ringsInSilent], but null while it cannot be told: device unknown,
/// or iOS 26+ with permissions unknown (not read yet, or the read failed).
bool? ringsInSilentIfKnown(
  PermissionStatusMsg? permissions,
  DeviceInfoMsg? device,
) {
  if (device == null) {
    return null;
  }
  switch (device.platform) {
    case PlatformMsg.android:
      return true;
    case PlatformMsg.ios:
      if ((device.iosMajor ?? 0) < 26) {
        return false;
      }
      if (permissions == null) {
        return null;
      }
      return permissions.alarmKit == PermissionStateMsg.granted;
  }
}

AlarmStyleHint alarmStyleHint(
  AlarmStyle style, {
  required bool ringsInSilent,
  required bool rampUp,
}) => switch (style) {
  AlarmStyle.ringAndVibrate when !ringsInSilent => AlarmStyleHint.ringNoSilent,
  AlarmStyle.ringAndVibrate =>
    rampUp ? AlarmStyleHint.ring : AlarmStyleHint.ringNoRamp,
  AlarmStyle.vibrateOnly => AlarmStyleHint.vibrate,
  AlarmStyle.headphonesOnly => AlarmStyleHint.headphones,
};

/// The "khoảng cách quá ngắn" banner (T10 §4.7): distance mode only.
@immutable
final class ShortDistanceInfo {
  const new({
    required this.vehicle,
    required this.speedKmh,
    required this.thresholdM,
    required this.leadS,
  });

  final VehicleKindMsg vehicle;
  final int speedKmh;
  final int thresholdM;

  /// Rounded down, so it never reads "4 phút".
  final int leadS;

  @override
  bool operator ==(Object other) =>
      other is ShortDistanceInfo &&
      other.vehicle == vehicle &&
      other.speedKmh == speedKmh &&
      other.thresholdM == thresholdM &&
      other.leadS == leadS;

  @override
  int get hashCode => Object.hash(vehicle, speedKmh, thresholdM, leadS);
}

/// Null when no warning applies.
ShortDistanceInfo? shortDistanceInfo(
  TripSettings s,
  VehicleKindMsg vehicle,
  AlarmSettingsParams p,
) {
  if (s.mode != AlarmModeMsg.distance ||
      !shortDistanceWarning(s.distanceThresholdM, vehicle, p)) {
    return null;
  }
  final speed = p.expectedSpeedKmh(vehicle);
  return ShortDistanceInfo(
    vehicle: vehicle,
    speedKmh: speed,
    thresholdM: s.distanceThresholdM,
    leadS: shortDistanceLeadS(s.distanceThresholdM, speed),
  );
}

/// T10 §4.9 / §9: battery at or below `lowBatteryAlarmPct` and not charging
/// → the percent to show; otherwise null. Unknown charging counts as not
/// charging.
int? lowBatteryWarningPct(DeviceStatusMsg? status, AlarmSettingsParams p) {
  final pct = status?.batteryPct;
  if (pct == null || status?.charging == true) {
    return null;
  }
  return pct <= p.lowBatteryAlarmPct ? pct : null;
}

/// The alarm would not be heard: alarm stream muted or at 0 (Do Not Disturb
/// "Tắt hoàn toàn" mutes it, T14.1 test report O1), or Do Not Disturb
/// blocks alarms (total silence, or priority without alarms). Same rules
/// as the red chips of the home card (T22 §8.3 steps 5-6).
bool alarmMayBeSilenced(DeviceStatusMsg? status) {
  if (status == null) {
    return false;
  }
  final filter = status.interruptionFilter;
  return status.alarmMuted == true ||
      status.alarmVolumePct == 0 ||
      filter == InterruptionFilterMsg.none ||
      (filter == InterruptionFilterMsg.priority &&
          status.priorityAllowsAlarms == false);
}

/// Initial settings of screen 3: [preset] (full settings) wins, else the
/// choice of the draft on top of the stored [defaults], else [defaults].
TripSettings initialTripSettings({
  required TripSettings defaults,
  TripSettings? preset,
  TripAlarmChoice? choice,
}) {
  if (preset != null) {
    return preset.normalized();
  }
  if (choice != null) {
    return defaults.withChoice(choice);
  }
  return defaults.normalized();
}
