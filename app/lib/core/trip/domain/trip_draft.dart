/// Trip draft passed from screen 1/2 to screen 3 (T22 §6.2). Contract with
/// T23, T25 and T28: add optional fields only, never rename or remove.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

/// Distance threshold range (T14 V7).
const int kMinDistanceThresholdM = 200;
const int kMaxDistanceThresholdM = 10000;

/// Time threshold range (T14 V8).
const int kMinTimeThresholdMin = 5;
const int kMaxTimeThresholdMin = 60;

/// Alarm mode and thresholds chosen for one trip.
@immutable
final class TripAlarmChoice {
  const new({
    required this.mode,
    required this.preAlertEnabled,
    this.distanceThresholdM,
    this.timeThresholdMin,
  });

  final AlarmModeMsg mode;

  /// Required for distance: 200..10000 (T14 V5, V7).
  final int? distanceThresholdM;

  /// Required for time: 5..60 (T14 V6, V8).
  final int? timeThresholdMin;
  final bool preAlertEnabled;

  /// T14 V5-V8.
  bool get isValid {
    final distance = distanceThresholdM;
    final time = timeThresholdMin;
    if (mode == AlarmModeMsg.distance && distance == null) {
      return false;
    }
    if (mode == AlarmModeMsg.time && time == null) {
      return false;
    }
    if (distance != null &&
        (distance < kMinDistanceThresholdM ||
            distance > kMaxDistanceThresholdM)) {
      return false;
    }
    if (time != null &&
        (time < kMinTimeThresholdMin || time > kMaxTimeThresholdMin)) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is TripAlarmChoice &&
      other.mode == mode &&
      other.distanceThresholdM == distanceThresholdM &&
      other.timeThresholdMin == timeThresholdMin &&
      other.preAlertEnabled == preAlertEnabled;

  @override
  int get hashCode =>
      Object.hash(mode, distanceThresholdM, timeThresholdMin, preAlertEnabled);

  @override
  String toString() =>
      'TripAlarmChoice(${mode.name}, $distanceThresholdM, $timeThresholdMin, '
      '$preAlertEnabled)';
}

/// Everything screen 3 needs to start a trip, except the global alarm
/// settings (sound, vibration, dismiss method: T28 defaults, per-trip edits
/// on screen 3).
///
/// PRIVACY: [toString] never prints the name or the coordinates.
@immutable
final class TripDraft {
  /// A null `vehicleHint` means `vehicleHintFor(destination.kind)`.
  const new({
    required this.destination,
    required this.source,
    this.alarm,
    this._vehicleHint,
  });

  /// Restart a recent trip (T22, T28 "Đặt lại"): same destination and alarm
  /// choice. An alarm choice that is no longer valid is dropped, so screen 3
  /// falls back to its defaults.
  factory fromRecord(TripRecord record) => TripDraft(
    destination: record.destination,
    source: DestinationSource.recentTrip,
    alarm: record.alarm.isValid ? record.alarm : null,
    vehicleHint: record.vehicleHint,
  );

  /// A saved place (T22): no alarm choice, screen 3 uses its defaults.
  factory fromSavedPlace(SavedPlace place) => TripDraft(
    destination: place.destination,
    source: DestinationSource.savedPlace,
  );

  final TripDestination destination;
  final DestinationSource source;

  /// null: screen 3 fills the defaults (PRD §4: smart, 1 km, 15 min,
  /// pre-alert on; later the T28 settings).
  final TripAlarmChoice? alarm;
  final VehicleKindMsg? _vehicleHint;

  /// Sent as `TripConfigMsg.vehicleHint`.
  VehicleKindMsg get vehicleHint =>
      _vehicleHint ?? vehicleHintFor(destination.kind);

  /// A copy with the given fields replaced. A new [destination] without a
  /// [vehicleHint] drops the explicit hint, so the hint follows the new
  /// destination kind. [alarm] cannot be reset to null here: build a new
  /// [TripDraft] for that.
  TripDraft copyWith({
    TripDestination? destination,
    DestinationSource? source,
    TripAlarmChoice? alarm,
    VehicleKindMsg? vehicleHint,
  }) => TripDraft(
    destination: destination ?? this.destination,
    source: source ?? this.source,
    alarm: alarm ?? this.alarm,
    vehicleHint: vehicleHint ?? (destination == null ? _vehicleHint : null),
  );

  @override
  bool operator ==(Object other) =>
      other is TripDraft &&
      other.destination == destination &&
      other.source == source &&
      other.alarm == alarm &&
      other.vehicleHint == vehicleHint;

  @override
  int get hashCode => Object.hash(destination, source, alarm, vehicleHint);

  @override
  String toString() =>
      'TripDraft($destination, ${source.name}, $alarm, ${vehicleHint.name})';
}
