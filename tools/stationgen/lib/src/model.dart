/// Data types shared by the build steps.
library;

import 'package:stationgen/src/prefixes.dart';

/// Input data error (exit 65). [code] is one of the `E_*` constants.
final class StationgenException implements Exception {
  const new(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Exit code: success.
const int kExitOk = 0;

/// Exit code: acceptance failed, outputs differ, or fetch failed.
const int kExitFailed = 1;

/// Exit code: command line usage error (sysexits `EX_USAGE`).
const int kExitUsage = 64;

/// Exit code: invalid input data (sysexits `EX_DATAERR`).
const int kExitData = 65;

const String kErrQueryChanged = 'E_QUERY_CHANGED';
const String kErrRawInvalid = 'E_RAW_INVALID';
const String kErrStaleOverride = 'E_STALE_OVERRIDE';
const String kErrProvinceUnresolved = 'E_PROVINCE_UNRESOLVED';
const String kErrOverrideInvalid = 'E_OVERRIDE_INVALID';
const String kErrProvincesInvalid = 'E_PROVINCES_INVALID';
const String kErrMustHaveInvalid = 'E_MUST_HAVE_INVALID';
const String kErrInputMissing = 'E_INPUT_MISSING';

/// OSM element type letter used in ids (`n`, `w`, `r`).
enum OsmType {
  node('n', 'node'),
  way('w', 'way'),
  relation('r', 'relation');

  new(this.letter, this.jsonName);

  final String letter;
  final String jsonName;

  static OsmType? fromJson(String? s) {
    for (final t in values) {
      if (t.jsonName == s) {
        return t;
      }
    }
    return null;
  }
}

/// An element of part A of the Overpass response.
final class OsmElement {
  const new({
    required this.type,
    required this.id,
    required this.tags,
    this.lat,
    this.lon,
  });

  final OsmType type;
  final int id;
  final Map<String, String> tags;

  /// Node position or way/relation bbox centre; null when missing.
  final double? lat;
  final double? lon;

  /// `n123`, `w123`, `r123` (the form used by overrides).
  String get ref => '${type.letter}$id';

  /// Station id in `stations.json`.
  String get stationId => 'osm:$ref';
}

/// Why an element did not become a station.
enum DropReason {
  overrideDrop('OVERRIDE_DROP'),
  notStation('NOT_STATION'),
  lifecycle('LIFECYCLE'),
  private('PRIVATE'),
  noName('NO_NAME'),
  metro('METRO'),
  noGeometry('NO_GEOMETRY'),
  outsideBbox('OUTSIDE_BBOX');

  new(this.label);

  final String label;
}

/// Bounding box of Viet Nam used for validation (spec §3).
const double kMinLat = 8;
const double kMaxLat = 23.5;
const double kMinLng = 102;
const double kMaxLng = 110;

bool insideVnBbox(double lat, double lng) =>
    lat >= kMinLat && lat <= kMaxLat && lng >= kMinLng && lng <= kMaxLng;

/// A station candidate before de-duplication.
final class Candidate {
  new({
    required this.id,
    required this.name,
    required this.kind,
    required this.province,
    required this.lat,
    required this.lng,
    required this.aliases,
    required this.primary,
    required this.typeRank,
    required this.osmId,
  });

  final String id;
  String name;
  StationKind kind;
  String province;
  double lat;
  double lng;
  List<String> aliases;

  /// Carries the main tag of its kind (spec §4.5 `primary`).
  final bool primary;

  /// node 0 < way 1 < relation 2 < manual 3.
  final int typeRank;

  /// OSM numeric id (0 for manual entries).
  final int osmId;

  /// Ids merged into this one by de-duplication.
  final List<String> mergedIds = [];

  List<String> get core => coreTokens(name);

  String get coreKey => core.join(' ');
}

/// A dropped element, for the build report.
final class Dropped {
  const new(this.id, this.name, this.reason);

  final String id;

  /// Raw name or null.
  final String? name;
  final DropReason reason;
}
