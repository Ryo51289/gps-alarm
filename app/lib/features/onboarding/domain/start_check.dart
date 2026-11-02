/// Can a trip start with these permissions? (T19 §1.3). Shared by screen 0
/// (T21), the home "Sẵn sàng" card (T22) and screen 3 (T25).
library;

import 'package:napstop/core/bridge/core_api.g.dart';

/// Blocking requirements. Names match the `permission-missing` details of
/// TripHostApi (T14 §4).
enum StartRequirement { location, precise, locationServices, alarmChannel }

/// Non-blocking issues, most severe first (T19 §1.3 `warnings`).
enum PermissionWarning {
  /// Android: notifications not granted.
  notifications,

  /// Android: exact alarms denied or not determined.
  exactAlarm,

  /// Android: full-screen intent denied or not determined.
  fullScreenIntent,

  /// iOS 26+: AlarmKit not granted (the alarm is silent in Silent mode).
  alarmKit,

  /// iOS: notifications not granted while AlarmKit is granted.
  notificationsNoStatus,

  /// Android: battery optimization still applies ("guide" level).
  batteryOptimization,
}

/// Result of [checkStart].
final class StartCheck {
  const new({required this.missing, required this.warnings});

  /// Fixed order: location, precise, locationServices, alarmChannel.
  final List<StartRequirement> missing;
  final List<PermissionWarning> warnings;

  bool get canStart => missing.isEmpty;
}

bool _isDeniedOrUnknown(PermissionStateMsg s) =>
    s == PermissionStateMsg.denied || s == PermissionStateMsg.notDetermined;

/// Blocking requirements and warnings for [s] on [device].
StartCheck checkStart(PermissionStatusMsg s, DeviceInfoMsg device) {
  final missing = <StartRequirement>[];
  final warnings = <PermissionWarning>[];
  final hasLocation =
      s.location == LocationAccessMsg.whileInUse ||
      s.location == LocationAccessMsg.always;
  if (!hasLocation) {
    missing.add(StartRequirement.location);
  } else if (s.precise != PermissionStateMsg.granted) {
    missing.add(StartRequirement.precise);
  }
  if (!s.locationServicesEnabled) {
    missing.add(StartRequirement.locationServices);
  }
  switch (device.platform) {
    case PlatformMsg.android:
      // Android always has an alarm channel (foreground service + alarm).
      if (s.notifications != PermissionStateMsg.granted &&
          s.notifications != PermissionStateMsg.notApplicable) {
        warnings.add(PermissionWarning.notifications);
      }
      if (_isDeniedOrUnknown(s.exactAlarm)) {
        warnings.add(PermissionWarning.exactAlarm);
      }
      if (_isDeniedOrUnknown(s.fullScreenIntent)) {
        warnings.add(PermissionWarning.fullScreenIntent);
      }
      if (s.batteryOptimizationIgnored == PermissionStateMsg.denied) {
        warnings.add(PermissionWarning.batteryOptimization);
      }
    case PlatformMsg.ios:
      final alarmKitGranted =
          (device.iosMajor ?? 0) >= 26 &&
          s.alarmKit == PermissionStateMsg.granted;
      final notificationsGranted =
          s.notifications == PermissionStateMsg.granted;
      if (!alarmKitGranted && !notificationsGranted) {
        missing.add(StartRequirement.alarmChannel);
      } else {
        if ((device.iosMajor ?? 0) >= 26 &&
            s.alarmKit != PermissionStateMsg.granted &&
            s.alarmKit != PermissionStateMsg.notApplicable) {
          warnings.add(PermissionWarning.alarmKit);
        }
        if (!notificationsGranted &&
            s.notifications != PermissionStateMsg.notApplicable &&
            s.alarmKit == PermissionStateMsg.granted) {
          warnings.add(PermissionWarning.notificationsNoStatus);
        }
      }
  }
  return StartCheck(
    missing: List.unmodifiable(missing),
    warnings: List.unmodifiable(warnings),
  );
}

/// Shortcut for `checkStart(s, device).canStart`.
bool canStart(PermissionStatusMsg s, DeviceInfoMsg device) =>
    checkStart(s, device).canStart;
