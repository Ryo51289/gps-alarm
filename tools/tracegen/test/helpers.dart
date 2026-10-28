import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tracegen/tracegen.dart';

/// Latitude/longitude of the synthetic north-bound test route.
const double kSynthLat = 20;
const double kSynthLng = 105;

/// Point [northM] metres north of the synthetic route origin.
LatLng synthPoint(double northM) =>
    LatLng(kSynthLat + northM / kMetresPerDegLat, kSynthLng);

/// Route JSON: straight line along the meridian at lat 20 through
/// waypoints `(id, metres from origin)`.
Map<String, Object?> synthRouteJson([
  List<(String, double)> waypoints = const [
    ('a', 0),
    ('mid', 5000),
    ('b', 10000),
  ],
]) => {
  'id': 'synth',
  'title': 'Synthetic route',
  'attribution': 'none',
  'waypoints': [
    for (final (id, m) in waypoints)
      {
        'id': id,
        'lat': synthPoint(m).lat,
        'lng': synthPoint(m).lng,
        'source': 'approx',
      },
  ],
};

/// Profile JSON on [synthRouteJson]: 72 km/h, accel = decel = 0.5, no
/// jitter, no stops, no dwell, mild noise. [overrides] replace top-level
/// keys.
Map<String, Object?> synthProfileJson({
  String destination = 'b',
  String first = 'a',
  Map<String, Object?> overrides = const {},
}) => {
  'id': 'synth',
  'title': 'Synthetic trip',
  'vehicle': 'coach',
  'route': 'synth',
  'destination': destination,
  'seed': 1,
  'startTime': '2026-03-14T00:00:00Z',
  'sampleIntervalS': 5,
  'startDwellS': 0,
  'endDwellS': 0,
  'motion': {
    'accelMps2': 0.5,
    'decelMps2': 0.5,
    'cruiseJitter': 0,
    'jitterChunkM': 1000,
  },
  'speedLimits': [
    {'from': first, 'kmh': 72},
  ],
  'stops': <Object?>[],
  'gpsGaps': <Object?>[],
  'noise': {
    'sigmaM': 5,
    'rho': 0.9,
    'accMinM': 3,
    'speedSigmaMps': 0.3,
    'speedMissingRate': 0,
    'outlierRate': 0,
    'outlierMinM': 0,
    'outlierMaxM': 0,
  },
  'scriptedOutliers': <Object?>[],
  'cases': <Object?>[],
  ...overrides,
};

/// Parses a synthetic profile/route pair.
(Profile, Route) synth({
  Map<String, Object?>? route,
  Map<String, Object?>? profile,
}) {
  final r = parseRoute(route ?? synthRouteJson(), file: 'routes/synth.json');
  final p = parseProfile(
    profile ?? synthProfileJson(),
    file: 'profiles/synth.json',
    route: r,
  );
  return (p, r);
}

/// Deep copy of a JSON value (so tests can mutate it).
Object? deepCopy(Object? json) => jsonDecode(jsonEncode(json));

/// Package root of tracegen (tests run with it as the working directory).
Directory get packageDir => Directory.current;

/// Data directory committed with the package.
Directory get dataDir => Directory('${packageDir.path}/data');

/// Committed fixtures directory.
Directory get fixturesDir =>
    Directory('${packageDir.path}/../../fixtures/traces');

/// Collects everything written to an [IOSink].
final class CapturedSink {
  new() : this._(<int>[]);

  new _(this._bytes) : sink = IOSink(_Collector(_bytes));

  final List<int> _bytes;
  final IOSink sink;

  Future<String> text() async {
    await sink.flush();
    return utf8.decode(_bytes);
  }
}

final class _Collector implements StreamConsumer<List<int>> {
  new(this._bytes);

  final List<int> _bytes;

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_bytes.addAll);

  @override
  Future<void> close() async {}
}
