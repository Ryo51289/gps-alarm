import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/home/domain/greeting.dart';
import 'package:napstop/features/home/domain/readiness.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Enum to display string mappings of screen 1 (T22 §11).
extension HomeStrings on AppLocalizations {
  String greeting(Greeting g) => switch (g) {
    Greeting.morning => homeGreetingMorning,
    Greeting.noon => homeGreetingNoon,
    Greeting.afternoon => homeGreetingAfternoon,
    Greeting.evening => homeGreetingEvening,
  };

  String slotLabel(SavedPlaceSlot slot) => switch (slot) {
    SavedPlaceSlot.home => homeSlotHome,
    SavedPlaceSlot.hometown => homeSlotHometown,
    SavedPlaceSlot.work => homeSlotWork,
  };

  /// Null for [VehicleKindMsg.unknown].
  String? vehicleLabel(VehicleKindMsg vehicle) => switch (vehicle) {
    VehicleKindMsg.train => homeVehicleTrain,
    VehicleKindMsg.coach => homeVehicleCoach,
    VehicleKindMsg.bus => homeVehicleBus,
    VehicleKindMsg.unknown => null,
  };

  String readinessChip(ReadinessChip chip) {
    final pct = chip.percent ?? 0;
    return switch (chip.kind) {
      ReadinessChipKind.locationWhileInUse => homeChipLocationWhileInUse,
      ReadinessChipKind.locationAlways => homeChipLocationAlways,
      ReadinessChipKind.locationDenied => homeChipLocationDenied,
      ReadinessChipKind.locationApproximate => homeChipLocationApproximate,
      ReadinessChipKind.locationServicesOff => homeChipLocationServicesOff,
      ReadinessChipKind.noAlarmChannel => homeChipNoAlarmChannel,
      ReadinessChipKind.notificationsOff => homeChipNotificationsOff,
      ReadinessChipKind.exactAlarmOff => homeChipExactAlarmOff,
      ReadinessChipKind.fullScreenOff => homeChipFullScreenOff,
      ReadinessChipKind.alarmKitOff => homeChipAlarmKitOff,
      ReadinessChipKind.notificationsNoStatus => homeChipNotificationsNoStatus,
      ReadinessChipKind.battery => homeChipBattery(pct),
      ReadinessChipKind.batteryCharging => homeChipBatteryCharging(pct),
      ReadinessChipKind.batteryLow => homeChipBatteryLow(pct),
      ReadinessChipKind.alarmVolume => homeChipAlarmVolume(pct),
      ReadinessChipKind.alarmVolumeLow => homeChipAlarmVolumeLow(pct),
      ReadinessChipKind.alarmMuted => homeChipAlarmMuted,
      ReadinessChipKind.dndBlocksAlarms => homeChipDndBlocksAlarms,
      ReadinessChipKind.batteryOptimization => homeChipBatteryOptimization,
      ReadinessChipKind.deviceStatusUnknown => homeChipDeviceStatusUnknown,
      ReadinessChipKind.dndCheckAlarms => homeChipDndCheckAlarms,
    };
  }
}
