/// Destination of a trip, shared by screens 1, 2, 3 and the history (T22 §6.1).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/destination/domain/station.dart';

/// What kind of place the destination is. Stored in the database with fixed
/// wire names (see `DestinationKindConverter`).
enum DestinationKind {
  train,
  coach,
  bus,
  address,
  pin;

  static DestinationKind fromStation(StationKind kind) => switch (kind) {
    StationKind.train => train,
    StationKind.coach => coach,
    StationKind.bus => bus,
  };
}

/// How the destination was chosen (T29 `dest_source`).
/// `places` = online address search (Google Places before ADR-002, Apple
/// MapKit since T23.5).
enum DestinationSource { station, places, mapPin, savedPlace, recentTrip }

/// Longest destination name accepted by the native side (T14 V2).
const int kMaxDestinationNameLength = 200;

/// A destination: display name, WGS84 coordinates, kind.
///
/// PRIVACY: [toString] never prints the name or the coordinates.
@immutable
final class TripDestination {
  const new({
    required this.name,
    required this.lat,
    required this.lng,
    required this.kind,
    this.detail,
  });

  /// From the offline dataset (T24). Station.id is deliberately not kept: it
  /// is not stable across dataset refreshes.
  factory fromStation(Station station) => TripDestination(
    name: station.name,
    lat: station.lat,
    lng: station.lng,
    kind: DestinationKind.fromStation(station.kind),
    detail: station.province,
  );

  /// Display name; 1..200 characters, not blank (T14 V2).
  final String name;

  /// WGS84, finite, in [-90, 90].
  final double lat;

  /// WGS84, finite, in [-180, 180).
  final double lng;
  final DestinationKind kind;

  /// Province or address line, display only.
  final String? detail;

  /// T14 V2-V4 checked on the Dart side; screens validate before building a
  /// draft.
  bool get isValid =>
      name.trim().isNotEmpty &&
      name.length <= kMaxDestinationNameLength &&
      lat.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng.isFinite &&
      lng >= -180 &&
      lng < 180;

  @override
  bool operator ==(Object other) =>
      other is TripDestination &&
      other.name == name &&
      other.lat == lat &&
      other.lng == lng &&
      other.kind == kind &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(name, lat, lng, kind, detail);

  @override
  String toString() => 'TripDestination(${kind.name})';
}

/// Vehicle hint sent to the engine: train/coach/bus from the kind, else
/// unknown.
VehicleKindMsg vehicleHintFor(DestinationKind kind) => switch (kind) {
  DestinationKind.train => VehicleKindMsg.train,
  DestinationKind.coach => VehicleKindMsg.coach,
  DestinationKind.bus => VehicleKindMsg.bus,
  DestinationKind.address || DestinationKind.pin => VehicleKindMsg.unknown,
};
