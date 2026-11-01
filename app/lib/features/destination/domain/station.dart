/// Offline station dataset model (spec T24 §3, §7.1).
library;

/// Station kind. Declaration order is the tie-break order of search results
/// (train before coach before bus).
enum StationKind { train, coach, bus }

/// A train station, coach station or bus terminal from the offline dataset.
final class Station {
  const new({
    required this.id,
    required this.name,
    required this.nameAscii,
    required this.kind,
    required this.province,
    required this.lat,
    required this.lng,
    this.aliases = const [],
  });

  /// `osm:n123` / `osm:w123` / `osm:r123` / `man:<slug>`. Not stable across
  /// dataset refreshes; never persist it.
  final String id;

  /// Display name (Vietnamese, NFC in practice).
  final String name;

  /// `foldVi(name)`.
  final String nameAscii;
  final StationKind kind;

  /// One of the 34 provinces (after the 2025 merger).
  final String province;
  final double lat;
  final double lng;

  /// Other display names, at most 5.
  final List<String> aliases;

  @override
  String toString() => 'Station($id, $name, ${kind.name}, $province)';
}

/// The decoded `assets/stations.json`.
final class StationDataset {
  const new({
    required this.osmBase,
    required this.attribution,
    required this.licenseUrl,
    required this.stations,
  });

  /// OSM data timestamp of the snapshot.
  final String osmBase;

  /// "© OpenStreetMap contributors".
  final String attribution;
  final String licenseUrl;
  final List<Station> stations;
}
