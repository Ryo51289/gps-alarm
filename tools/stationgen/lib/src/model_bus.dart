/// Data types of the bus stop dataset (spec T24.3 §3, §4).
library;

/// Why an element did not become a bus stop (spec T24.3 §4).
enum BusDropReason {
  overrideDrop('OVERRIDE_DROP'),
  notStop('NOT_STOP'),
  lifecycle('LIFECYCLE'),
  private('PRIVATE'),
  noName('NO_NAME'),
  noGeometry('NO_GEOMETRY'),
  outsideBbox('OUTSIDE_BBOX'),
  dupOfStation('DUP_OF_STATION');

  new(this.label);

  final String label;
}

/// A bus stop candidate before merging the two sides of a road.
final class BusCandidate {
  new({
    required this.id,
    required this.name,
    required this.province,
    required this.lat,
    required this.lng,
    required this.routes,
    required this.typeRank,
    required this.osmId,
  });

  /// `n123` / `w123` (or `man:<slug>` for a manual entry).
  final String id;
  String name;
  String province;
  double lat;
  double lng;

  /// Normalised `route_ref` values (spec D7).
  List<String> routes;

  /// node 0 < way 1 < manual 3.
  final int typeRank;

  /// OSM numeric id (0 for manual entries).
  final int osmId;
}

/// A bus stop of the output: one merged cluster (spec T24.3 D5).
final class BusStop {
  const new({
    required this.id,
    required this.name,
    required this.province,
    required this.lat,
    required this.lng,
    required this.routes,
    this.members = const [],
  });

  /// Id of the seed candidate.
  final String id;
  final String name;
  final String province;

  /// Mean of the member coordinates.
  final double lat;
  final double lng;
  final List<String> routes;

  /// Every merged candidate, seed first.
  final List<BusCandidate> members;
}

/// A dropped element, for the bus build report.
final class BusDropped {
  const new(this.id, this.name, this.reason);

  final String id;

  /// Raw name or null.
  final String? name;
  final BusDropReason reason;
}
