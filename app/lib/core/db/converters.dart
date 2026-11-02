/// Enum <-> TEXT converters with fixed wire names (T22 §5.2). The wire names
/// are a storage format: never change one, only add new ones. They match the
/// analytics names of T29 §2.
library;

import 'package:drift/drift.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';

/// Base of the converters below. [wireOf] is an exhaustive `switch`, so a new
/// enum value without a wire name does not compile. An unknown wire value
/// read from the database throws a [FormatException] that does not quote
/// the value.
abstract base class WireEnumConverter<T extends Enum>
    extends TypeConverter<T, String> {
  const new();

  /// Every value of the enum.
  List<T> get values;

  /// Fixed wire name of [value].
  String wireOf(T value);

  @override
  T fromSql(String fromDb) {
    for (final v in values) {
      if (wireOf(v) == fromDb) {
        return v;
      }
    }
    throw FormatException('Unknown wire value for $T');
  }

  @override
  String toSql(T value) => wireOf(value);
}

final class DestinationKindConverter
    extends WireEnumConverter<DestinationKind> {
  const new();

  @override
  List<DestinationKind> get values => DestinationKind.values;

  @override
  String wireOf(DestinationKind value) => switch (value) {
    DestinationKind.train => 'train',
    DestinationKind.coach => 'coach',
    DestinationKind.bus => 'bus',
    DestinationKind.address => 'address',
    DestinationKind.pin => 'pin',
  };
}

final class DestinationSourceConverter
    extends WireEnumConverter<DestinationSource> {
  const new();

  @override
  List<DestinationSource> get values => DestinationSource.values;

  @override
  String wireOf(DestinationSource value) => switch (value) {
    DestinationSource.station => 'station',
    DestinationSource.places => 'places',
    DestinationSource.mapPin => 'map_pin',
    DestinationSource.savedPlace => 'saved_place',
    DestinationSource.recentTrip => 'recent_trip',
  };
}

final class SavedPlaceSlotConverter extends WireEnumConverter<SavedPlaceSlot> {
  const new();

  @override
  List<SavedPlaceSlot> get values => SavedPlaceSlot.values;

  @override
  String wireOf(SavedPlaceSlot value) => switch (value) {
    SavedPlaceSlot.home => 'home',
    SavedPlaceSlot.hometown => 'hometown',
    SavedPlaceSlot.work => 'work',
  };
}

final class AlarmModeConverter extends WireEnumConverter<AlarmModeMsg> {
  const new();

  @override
  List<AlarmModeMsg> get values => AlarmModeMsg.values;

  @override
  String wireOf(AlarmModeMsg value) => switch (value) {
    AlarmModeMsg.distance => 'distance',
    AlarmModeMsg.time => 'time',
    AlarmModeMsg.smart => 'smart',
  };
}

final class VehicleKindConverter extends WireEnumConverter<VehicleKindMsg> {
  const new();

  @override
  List<VehicleKindMsg> get values => VehicleKindMsg.values;

  @override
  String wireOf(VehicleKindMsg value) => switch (value) {
    VehicleKindMsg.train => 'train',
    VehicleKindMsg.coach => 'coach',
    VehicleKindMsg.bus => 'bus',
    VehicleKindMsg.unknown => 'unknown',
  };
}

final class TripOutcomeConverter extends WireEnumConverter<TripOutcomeMsg> {
  const new();

  @override
  List<TripOutcomeMsg> get values => TripOutcomeMsg.values;

  @override
  String wireOf(TripOutcomeMsg value) => switch (value) {
    TripOutcomeMsg.onTime => 'on_time',
    TripOutcomeMsg.snoozed => 'snoozed',
    TripOutcomeMsg.missed => 'missed',
    TripOutcomeMsg.cancelled => 'cancelled',
  };
}

final class EndReasonConverter extends WireEnumConverter<EndReasonMsg> {
  const new();

  @override
  List<EndReasonMsg> get values => EndReasonMsg.values;

  @override
  String wireOf(EndReasonMsg value) => switch (value) {
    EndReasonMsg.dismissed => 'dismissed',
    EndReasonMsg.userStop => 'user_stop',
    EndReasonMsg.alarmUnanswered => 'alarm_unanswered',
  };
}

final class AlarmReasonConverter extends WireEnumConverter<AlarmReasonMsg> {
  const new();

  @override
  List<AlarmReasonMsg> get values => AlarmReasonMsg.values;

  @override
  String wireOf(AlarmReasonMsg value) => switch (value) {
    AlarmReasonMsg.distance => 'distance',
    AlarmReasonMsg.time => 'time',
    AlarmReasonMsg.smartTime => 'smart_time',
    AlarmReasonMsg.smartDistance => 'smart_distance',
    AlarmReasonMsg.smartSlowDistance => 'smart_slow_distance',
    AlarmReasonMsg.gpsLost => 'gps_lost',
    AlarmReasonMsg.lowBattery => 'low_battery',
    AlarmReasonMsg.passedClosest => 'passed_closest',
    AlarmReasonMsg.overshoot => 'overshoot',
    AlarmReasonMsg.snoozeEnd => 'snooze_end',
    AlarmReasonMsg.timeout => 'timeout',
    AlarmReasonMsg.fallback => 'fallback',
    AlarmReasonMsg.fallbackMissed => 'fallback_missed',
  };
}
