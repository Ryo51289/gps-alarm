/// The home "Sẵn sàng" card: permissions + battery + alarm volume + Do Not
/// Disturb (T22 §8.3). Pure Dart.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

enum ReadinessLevel { ready, check, blocked }

/// ok and guide are neutral; caution is orange; warning and blocking are red.
enum ReadinessSeverity { ok, guide, caution, warning, blocking }

enum ReadinessAction { none, openPermissions, openBatteryGuide }

enum ReadinessChipKind {
  locationWhileInUse,
  locationAlways,
  locationDenied,
  locationApproximate,
  locationServicesOff,
  noAlarmChannel,
  notificationsOff,
  exactAlarmOff,
  fullScreenOff,
  alarmKitOff,
  notificationsNoStatus,
  battery,
  batteryCharging,
  batteryLow,
  alarmVolume,
  alarmVolumeLow,
  alarmMuted,
  dndBlocksAlarms,
  batteryOptimization,

  /// Android: deviceStatus() failed, or volume / Do Not Disturb unreadable
  /// (T21 §12, O6): "not checked" is not "ready".
  deviceStatusUnknown,

  /// Android: Do Not Disturb "priority" whose alarm policy cannot be read
  /// (API 26-29, or a read error), T21 §12.
  dndCheckAlarms,

  /// iOS 26+, AlarmKit allowed: rings even in Silent mode (T28.3 D5).
  iosAlarmKitOn,

  /// iOS, notifications only (before 26, or AlarmKit not applicable): may
  /// not ring in Silent mode (T28.3 D5).
  iosSilentRisk,
}

/// One line of the card.
@immutable
final class ReadinessChip {
  const new(this.kind, this.severity, {this.percent});

  final ReadinessChipKind kind;
  final ReadinessSeverity severity;

  /// Battery or volume percent, for the chips that show one.
  final int? percent;

  @override
  bool operator ==(Object other) =>
      other is ReadinessChip &&
      other.kind == kind &&
      other.severity == severity &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(kind, severity, percent);

  @override
  String toString() =>
      'ReadinessChip(${kind.name}, ${severity.name}, $percent)';
}

@immutable
final class Readiness {
  const new({
    required this.level,
    required this.chips,
    required this.action,
    required this.showSleepModeHint,
  });

  final ReadinessLevel level;
  final List<ReadinessChip> chips;
  final ReadinessAction action;

  /// Android: a schedule mode may turn on at night and cannot be read without
  /// policy access (S2 V5-9), so the card always reminds the user (Q4).
  final bool showSleepModeHint;
}

/// Battery at or below this percent, not charging: caution (Q3).
const int kLowBatteryPct = 20;

/// Alarm volume below this percent: caution (Q3).
const int kLowAlarmVolumePct = 30;

/// Builds the card from the permission status, the device and the live
/// device status (null when unreadable). On Android an unreadable status,
/// volume or Do Not Disturb is a caution chip, never "ready" (T21 §12).
Readiness evaluateReadiness({
  required PermissionStatusMsg permissions,
  required DeviceInfoMsg device,
  DeviceStatusMsg? status,
}) {
  final android = device.platform == PlatformMsg.android;
  final check = checkStart(permissions, device);
  final missing = check.missing;
  final chips = <ReadinessChip>[];
  var permissionWarning = false;

  // 1. Location.
  if (missing.contains(StartRequirement.location)) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.locationDenied,
        ReadinessSeverity.blocking,
      ),
    );
  }
  if (missing.contains(StartRequirement.precise)) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.locationApproximate,
        ReadinessSeverity.blocking,
      ),
    );
  }
  if (missing.contains(StartRequirement.locationServices)) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.locationServicesOff,
        ReadinessSeverity.blocking,
      ),
    );
  }
  if (!missing.contains(StartRequirement.location) &&
      !missing.contains(StartRequirement.precise) &&
      !missing.contains(StartRequirement.locationServices)) {
    chips.add(
      ReadinessChip(
        permissions.location == LocationAccessMsg.always
            ? ReadinessChipKind.locationAlways
            : ReadinessChipKind.locationWhileInUse,
        ReadinessSeverity.ok,
      ),
    );
  }

  // 2. Alarm channel (iOS).
  if (missing.contains(StartRequirement.alarmChannel)) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.noAlarmChannel,
        ReadinessSeverity.blocking,
      ),
    );
  }
  // T28.3 D5: iOS cannot read volume or Silent mode, so say whether the
  // alarm rings in Silent mode, by the same rule as screens 3 and 4
  // (`ringsInSilent`, test report O1). iOS 26+ with AlarmKit not allowed
  // already has the alarmKitOff warning (step 3): no second line.
  if (device.platform == PlatformMsg.ios &&
      !missing.contains(StartRequirement.alarmChannel)) {
    if (ringsInSilent(permissions, device)) {
      chips.add(
        const ReadinessChip(
          ReadinessChipKind.iosAlarmKitOn,
          ReadinessSeverity.ok,
        ),
      );
    } else if (!check.warnings.contains(PermissionWarning.alarmKit)) {
      chips.add(
        const ReadinessChip(
          ReadinessChipKind.iosSilentRisk,
          ReadinessSeverity.caution,
        ),
      );
    }
  }

  // 3. Permission warnings, in the order of checkStart.
  for (final w in check.warnings) {
    final chip = switch (w) {
      PermissionWarning.notifications => const ReadinessChip(
        ReadinessChipKind.notificationsOff,
        ReadinessSeverity.warning,
      ),
      PermissionWarning.exactAlarm => const ReadinessChip(
        ReadinessChipKind.exactAlarmOff,
        ReadinessSeverity.warning,
      ),
      PermissionWarning.fullScreenIntent => const ReadinessChip(
        ReadinessChipKind.fullScreenOff,
        ReadinessSeverity.warning,
      ),
      PermissionWarning.alarmKit => const ReadinessChip(
        ReadinessChipKind.alarmKitOff,
        ReadinessSeverity.warning,
      ),
      PermissionWarning.notificationsNoStatus => const ReadinessChip(
        ReadinessChipKind.notificationsNoStatus,
        ReadinessSeverity.caution,
      ),
      // Step 7.
      PermissionWarning.batteryOptimization => null,
    };
    if (chip != null) {
      chips.add(chip);
      permissionWarning = true;
    }
  }

  // 4. Battery.
  final battery = status?.batteryPct;
  if (battery != null) {
    final charging = status?.charging == true;
    if (battery <= kLowBatteryPct && !charging) {
      chips.add(
        ReadinessChip(
          ReadinessChipKind.batteryLow,
          ReadinessSeverity.caution,
          percent: battery,
        ),
      );
    } else {
      chips.add(
        ReadinessChip(
          charging
              ? ReadinessChipKind.batteryCharging
              : ReadinessChipKind.battery,
          ReadinessSeverity.ok,
          percent: battery,
        ),
      );
    }
  }

  // 5. Alarm volume (Android only). A muted alarm stream (e.g. Do Not
  // Disturb "total silence", T14.1 O1) warns even if the percent is unknown.
  final volume = status?.alarmVolumePct;
  final muted = status?.alarmMuted == true;
  var statusUnknown = false;
  if (android && (status == null || (volume == null && !muted))) {
    statusUnknown = true;
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.deviceStatusUnknown,
        ReadinessSeverity.caution,
      ),
    );
  } else if (volume != null || muted) {
    if (muted || volume == 0) {
      chips.add(
        const ReadinessChip(
          ReadinessChipKind.alarmMuted,
          ReadinessSeverity.warning,
        ),
      );
    } else if (volume! < kLowAlarmVolumePct) {
      chips.add(
        ReadinessChip(
          ReadinessChipKind.alarmVolumeLow,
          ReadinessSeverity.caution,
          percent: volume,
        ),
      );
    } else {
      chips.add(
        ReadinessChip(
          ReadinessChipKind.alarmVolume,
          ReadinessSeverity.ok,
          percent: volume,
        ),
      );
    }
  }

  // 6. Do Not Disturb.
  final filter = status?.interruptionFilter;
  if (filter == InterruptionFilterMsg.none ||
      (filter == InterruptionFilterMsg.priority &&
          status?.priorityAllowsAlarms == false)) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.dndBlocksAlarms,
        ReadinessSeverity.warning,
      ),
    );
  } else if (filter == InterruptionFilterMsg.priority &&
      status?.priorityAllowsAlarms == null &&
      !muted) {
    // API 26-29 cannot read the applied policy (T21 D9).
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.dndCheckAlarms,
        ReadinessSeverity.caution,
      ),
    );
  } else if (android &&
      filter == InterruptionFilterMsg.unknown &&
      !statusUnknown) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.deviceStatusUnknown,
        ReadinessSeverity.caution,
      ),
    );
  }

  // 7. Battery optimization (guide).
  final batteryOptimization = check.warnings.contains(
    PermissionWarning.batteryOptimization,
  );
  if (batteryOptimization) {
    chips.add(
      const ReadinessChip(
        ReadinessChipKind.batteryOptimization,
        ReadinessSeverity.guide,
      ),
    );
  }

  final blocking = chips.any((c) => c.severity == ReadinessSeverity.blocking);
  final attention = chips.any(
    (c) =>
        c.severity == ReadinessSeverity.warning ||
        c.severity == ReadinessSeverity.caution,
  );
  final level = blocking
      ? ReadinessLevel.blocked
      : attention
      ? ReadinessLevel.check
      : ReadinessLevel.ready;
  final action = blocking || permissionWarning
      ? ReadinessAction.openPermissions
      : batteryOptimization
      ? ReadinessAction.openBatteryGuide
      : ReadinessAction.none;
  return Readiness(
    level: level,
    chips: List.unmodifiable(chips),
    action: action,
    showSleepModeHint: device.platform == PlatformMsg.android,
  );
}
