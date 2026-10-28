/// Route and profile input files: parsing and validation (spec T02 §8).
library;

import 'dart:convert';
import 'dart:io';

import 'package:tracegen/src/anchor.dart';
import 'package:tracegen/src/fmt.dart';
import 'package:tracegen/src/geo.dart';
import 'package:tracegen/src/paths.dart';

/// Trip id / waypoint id pattern (spec §7.1).
final RegExp kIdPattern = RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*$');

final RegExp _sourcePattern = RegExp(r'^(osm:(node|way|relation)/\d+|approx)$');

/// Event names of schema v1 (spec §7.3.1).
const List<String> kEventNames = [
  'preAlert',
  'alarm',
  'gpsLost',
  'gpsRecovered',
  'overshoot',
  'arrived',
];

/// Seeds must be exactly representable as a JSON number everywhere: 2^53.
const int _maxSeedExclusive = 9007199254740992;

enum Vehicle { train, coach, bus }

final class ProfileException implements Exception {
  const new(this.path, this.message);

  /// File and field, e.g. `profiles/x.json: speedLimits[2].from`.
  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

final class Waypoint {
  const new({
    required this.id,
    required this.pos,
    required this.source,
    this.name,
  });

  final String id;
  final String? name;
  final LatLng pos;
  final String source;
}

final class Route {
  const new({
    required this.id,
    required this.title,
    required this.attribution,
    required this.waypoints,
  });

  final String id;
  final String title;
  final String attribution;
  final List<Waypoint> waypoints;

  /// Index of waypoint [id], or -1.
  int indexOf(String id) => waypoints.indexWhere((w) => w.id == id);

  Polyline toPolyline() => Polyline([for (final w in waypoints) w.pos]);
}

final class MotionSpec {
  const new({
    required this.accelMps2,
    required this.decelMps2,
    required this.cruiseJitter,
    required this.jitterChunkM,
  });

  final double accelMps2;
  final double decelMps2;
  final double cruiseJitter;
  final double jitterChunkM;
}

final class SpeedLimit {
  const new({required this.from, required this.kmh, this.jitter = true});

  /// Waypoint id where the limit starts.
  final String from;
  final double kmh;

  /// Whether the per-chunk cruise jitter applies.
  final bool jitter;
}

final class StopSpec {
  const new({required this.at, required this.dwellS});

  final String at;
  final int dwellS;
}

final class RegularStopsSpec {
  const new({
    required this.everyM,
    required this.dwellS,
    required this.marginM,
  });

  final double everyM;
  final int dwellS;
  final double marginM;
}

final class GapSpec {
  const new({required this.at, required this.durationS});

  final String at;
  final int durationS;
}

final class NoiseSpec {
  const new({
    required this.sigmaM,
    required this.rho,
    required this.accMinM,
    required this.speedSigmaMps,
    required this.speedMissingRate,
    required this.outlierRate,
    required this.outlierMinM,
    required this.outlierMaxM,
  });

  final double sigmaM;
  final double rho;
  final double accMinM;
  final double speedSigmaMps;
  final double speedMissingRate;
  final double outlierRate;
  final double outlierMinM;
  final double outlierMaxM;
}

final class ScriptedOutlierSpec {
  const new({
    required this.atRemainingM,
    required this.count,
    required this.distanceToDestinationM,
    required this.accM,
  });

  final double atRemainingM;
  final int count;
  final double distanceToDestinationM;
  final double accM;
}

enum CaseMode { distance, time }

final class WindowEdge {
  const new(this.anchor, this.offsetS);

  final Anchor anchor;
  final int offsetS;
}

final class ExpectSpec {
  const new({
    required this.event,
    required this.notBefore,
    required this.notAfter,
    required this.ref,
  });

  final String event;
  final WindowEdge notBefore;
  final WindowEdge notAfter;
  final String ref;
}

final class CaseSpec {
  const new({
    required this.id,
    required this.status,
    required this.mode,
    required this.threshold,
    required this.preAlert,
    required this.expect,
    required this.forbid,
  });

  final String id;

  /// `draft` or `final`.
  final String status;
  final CaseMode mode;

  /// `thresholdM` (distance) or `thresholdMin` (time).
  final int threshold;
  final bool preAlert;
  final List<ExpectSpec> expect;
  final List<String> forbid;
}

/// A validated profile (spec §8.2).
final class Profile {
  const new({
    required this.file,
    required this.id,
    required this.title,
    required this.vehicle,
    required this.route,
    required this.destination,
    required this.seed,
    required this.noiseSeed,
    required this.startTime,
    required this.startEpochS,
    required this.sampleIntervalS,
    required this.startDwellS,
    required this.endDwellS,
    required this.motion,
    required this.speedLimits,
    required this.stops,
    required this.regularStops,
    required this.gpsGaps,
    required this.noise,
    required this.scriptedOutliers,
    required this.cases,
  });

  /// Label used in error paths, e.g. `profiles/x.json`.
  final String file;
  final String id;
  final String title;
  final Vehicle vehicle;

  /// Route id.
  final String route;

  /// Destination waypoint id.
  final String destination;
  final int seed;
  final int noiseSeed;
  final String startTime;
  final int startEpochS;
  final int sampleIntervalS;
  final int startDwellS;
  final int endDwellS;
  final MotionSpec motion;
  final List<SpeedLimit> speedLimits;
  final List<StopSpec> stops;
  final RegularStopsSpec? regularStops;
  final List<GapSpec> gpsGaps;
  final NoiseSpec noise;
  final List<ScriptedOutlierSpec> scriptedOutliers;
  final List<CaseSpec> cases;
}

/// Loads profiles and routes from a data directory (`profiles/`, `routes/`).
final class ProfileRepository {
  new(this.dataDir);

  final Directory dataDir;

  /// Ids of every `profiles/*.json`, sorted (ASCII).
  List<String> profileIds() {
    final dir = Directory('${dataDir.path}/profiles');
    if (!dir.existsSync()) {
      return const [];
    }
    final ids = <String>[
      for (final e in dir.listSync())
        if (e is File && e.path.endsWith('.json')) _baseName(e.path, '.json'),
    ]..sort();
    return ids;
  }

  /// Loads profile [profileId] and its route; throws [ProfileException].
  (Profile, Route) load(String profileId) {
    final file = 'profiles/$profileId.json';
    final json = _readJson(File('${dataDir.path}/$file'), file);
    final routeId = json is Map<String, Object?> ? json['route'] : null;
    if (routeId is! String || !kIdPattern.hasMatch(routeId)) {
      throw ProfileException('$file: route', 'must be a valid route id');
    }
    final routeFile = File('${dataDir.path}/routes/$routeId.json');
    if (!routeFile.existsSync()) {
      throw ProfileException('$file: route', 'unknown route "$routeId"');
    }
    final route = parseRoute(
      _readJson(routeFile, 'routes/$routeId.json'),
      file: 'routes/$routeId.json',
      expectedId: routeId,
    );
    final profile = parseProfile(
      json,
      file: file,
      route: route,
      expectedId: profileId,
    );
    return (profile, route);
  }

  static Object? _readJson(File f, String label) {
    if (!f.existsSync()) {
      throw ProfileException(label, 'file not found');
    }
    try {
      return jsonDecode(utf8.decode(f.readAsBytesSync()));
    } on FormatException catch (e) {
      throw ProfileException(label, 'invalid JSON: ${e.message}');
    }
  }
}

String _baseName(String path, String suffix) {
  final name = fileNameOf(path);
  return name.substring(0, name.length - suffix.length);
}

/// Parses and validates a route file (spec §8.1).
Route parseRoute(Object? json, {required String file, String? expectedId}) {
  final o = _Obj.root(json, file)
    ..allowOnly(const {'id', 'title', 'attribution', 'waypoints'});
  final id = o.id('id');
  if (expectedId != null && id != expectedId) {
    throw o.error('id', 'must equal the file name "$expectedId"');
  }
  final title = o.str('title');
  final attribution = o.str('attribution');
  final list = o.list('waypoints');
  if (list.length < 2) {
    throw o.error('waypoints', 'need at least 2 waypoints');
  }
  final waypoints = <Waypoint>[];
  final seen = <String>{};
  for (var i = 0; i < list.length; i++) {
    final w = o.objAt(list, 'waypoints', i)
      ..allowOnly(const {'id', 'name', 'lat', 'lng', 'source'});
    final wid = w.id('id');
    if (!seen.add(wid)) {
      throw w.error('id', 'duplicate waypoint id "$wid"');
    }
    final name = w.optStr('name');
    final lat = w.number('lat');
    if (lat < -90 || lat > 90) {
      throw w.error('lat', 'must be in [-90, 90]');
    }
    final lng = w.number('lng');
    if (lng < -180 || lng >= 180) {
      throw w.error('lng', 'must be in [-180, 180)');
    }
    final source = w.str('source');
    if (!_sourcePattern.hasMatch(source)) {
      throw w.error(
        'source',
        'must match osm:(node|way|relation)/<n> or approx',
      );
    }
    waypoints.add(
      Waypoint(id: wid, name: name, pos: LatLng(lat, lng), source: source),
    );
  }
  final route = Route(
    id: id,
    title: title,
    attribution: attribution,
    waypoints: List.unmodifiable(waypoints),
  );
  for (var i = 0; i + 1 < waypoints.length; i++) {
    if (!(distanceM(waypoints[i].pos, waypoints[i + 1].pos) >= 1)) {
      throw o.error(
        'waypoints[${i + 1}]',
        'less than 1 m from the previous waypoint',
      );
    }
  }
  return route;
}

/// Parses and validates a profile against its [route] (spec §8.2).
Profile parseProfile(
  Object? json, {
  required String file,
  required Route route,
  String? expectedId,
}) {
  final o = _Obj.root(json, file)
    ..allowOnly(const {
      'id',
      'title',
      'vehicle',
      'route',
      'destination',
      'seed',
      'noiseSeed',
      'startTime',
      'sampleIntervalS',
      'startDwellS',
      'endDwellS',
      'motion',
      'speedLimits',
      'stops',
      'regularStops',
      'gpsGaps',
      'noise',
      'scriptedOutliers',
      'cases',
    });
  final id = o.id('id');
  if (expectedId != null && id != expectedId) {
    throw o.error('id', 'must equal the file name "$expectedId"');
  }
  final title = o.str('title');
  final vehicleName = o.str('vehicle');
  final vehicle = Vehicle.values.where((v) => v.name == vehicleName);
  if (vehicle.isEmpty) {
    throw o.error('vehicle', 'must be one of train, coach, bus');
  }
  final routeId = o.str('route');
  if (routeId != route.id) {
    throw o.error('route', 'unknown route "$routeId"');
  }
  final lastIndex = route.waypoints.length - 1;

  int waypointIndex(_Obj obj, String key) {
    final wid = obj.str(key);
    final i = route.indexOf(wid);
    if (i < 0) {
      throw obj.error(key, 'unknown waypoint "$wid" in route ${route.id}');
    }
    return i;
  }

  final destination = o.str('destination');
  final destIndex = waypointIndex(o, 'destination');
  if (destIndex == 0) {
    throw o.error('destination', 'must not be the first waypoint');
  }

  int seedAt(String key) {
    final v = o.integer(key);
    if (v < 0 || v >= _maxSeedExclusive) {
      throw o.error(key, 'must be in [0, 2^53)');
    }
    return v;
  }

  final seed = seedAt('seed');
  final noiseSeed = o.has('noiseSeed') ? seedAt('noiseSeed') : seed;

  final startTime = o.str('startTime');
  final int startEpochS;
  try {
    startEpochS = parseIsoUtc(startTime);
  } on FormatException catch (e) {
    throw o.error('startTime', '${e.message} (YYYY-MM-DDTHH:MM:SSZ)');
  }

  final interval = o.integer('sampleIntervalS');
  if (interval < 1) {
    throw o.error('sampleIntervalS', 'must be >= 1');
  }
  final startDwellS = o.integer('startDwellS');
  if (startDwellS < 0) {
    throw o.error('startDwellS', 'must be >= 0');
  }
  final endDwellS = o.integer('endDwellS');
  if (endDwellS < 0) {
    throw o.error('endDwellS', 'must be >= 0');
  }

  int dwellAt(_Obj obj, String key) {
    final v = obj.integer(key);
    if (v < 2 * interval) {
      throw obj.error(key, 'must be >= 2 * sampleIntervalS');
    }
    return v;
  }

  // motion
  final m = o.obj('motion')
    ..allowOnly(const {
      'accelMps2',
      'decelMps2',
      'cruiseJitter',
      'jitterChunkM',
    });
  final motion = MotionSpec(
    accelMps2: m.positive('accelMps2'),
    decelMps2: m.positive('decelMps2'),
    cruiseJitter: m.number('cruiseJitter'),
    jitterChunkM: m.number('jitterChunkM'),
  );
  if (motion.cruiseJitter < 0 || motion.cruiseJitter >= 0.5) {
    throw m.error('cruiseJitter', 'must be in [0, 0.5)');
  }
  if (motion.jitterChunkM < 100) {
    throw m.error('jitterChunkM', 'must be >= 100');
  }

  // speedLimits
  final limitList = o.list('speedLimits');
  if (limitList.isEmpty) {
    throw o.error('speedLimits', 'must not be empty');
  }
  final speedLimits = <SpeedLimit>[];
  var previous = -1;
  for (var i = 0; i < limitList.length; i++) {
    final e = o.objAt(limitList, 'speedLimits', i)
      ..allowOnly(const {'from', 'kmh', 'jitter'});
    final index = waypointIndex(e, 'from');
    if (i == 0 && index != 0) {
      throw e.error('from', 'first entry must start at the first waypoint');
    }
    if (index <= previous) {
      throw e.error('from', 'entries must follow the route order');
    }
    previous = index;
    final kmh = e.number('kmh');
    if (kmh <= 0 || kmh > 200) {
      throw e.error('kmh', 'must be in (0, 200]');
    }
    speedLimits.add(
      SpeedLimit(
        from: e.str('from'),
        kmh: kmh,
        jitter: !e.has('jitter') || e.boolean('jitter'),
      ),
    );
  }

  // stops
  final stops = <StopSpec>[];
  final stopIds = <String>{};
  final stopList = o.has('stops') ? o.list('stops') : const <Object?>[];
  for (var i = 0; i < stopList.length; i++) {
    final e = o.objAt(stopList, 'stops', i)..allowOnly(const {'at', 'dwellS'});
    final index = waypointIndex(e, 'at');
    if (index == 0 || index == lastIndex) {
      throw e.error('at', 'must not be the first or last waypoint');
    }
    final at = e.str('at');
    if (!stopIds.add(at)) {
      throw e.error('at', 'duplicate stop "$at"');
    }
    stops.add(StopSpec(at: at, dwellS: dwellAt(e, 'dwellS')));
  }

  RegularStopsSpec? regularStops;
  if (o.has('regularStops')) {
    final r = o.obj('regularStops')
      ..allowOnly(const {'everyM', 'dwellS', 'marginM'});
    final everyM = r.number('everyM');
    if (everyM < 200) {
      throw r.error('everyM', 'must be >= 200');
    }
    final marginM = r.number('marginM');
    if (marginM < 0) {
      throw r.error('marginM', 'must be >= 0');
    }
    regularStops = RegularStopsSpec(
      everyM: everyM,
      dwellS: dwellAt(r, 'dwellS'),
      marginM: marginM,
    );
  }

  // gpsGaps
  final gaps = <GapSpec>[];
  final gapList = o.has('gpsGaps') ? o.list('gpsGaps') : const <Object?>[];
  for (var i = 0; i < gapList.length; i++) {
    final e = o.objAt(gapList, 'gpsGaps', i)
      ..allowOnly(const {'at', 'durationS'});
    waypointIndex(e, 'at');
    final duration = e.integer('durationS');
    if (duration <= 0 || duration % interval != 0) {
      throw e.error(
        'durationS',
        'must be a positive multiple of '
            'sampleIntervalS ($interval)',
      );
    }
    gaps.add(GapSpec(at: e.str('at'), durationS: duration));
  }

  // noise
  final n = o.obj('noise')
    ..allowOnly(const {
      'sigmaM',
      'rho',
      'accMinM',
      'speedSigmaMps',
      'speedMissingRate',
      'outlierRate',
      'outlierMinM',
      'outlierMaxM',
    });
  double rangeAt(_Obj obj, String key, double lo, double hi, String text) {
    final v = obj.number(key);
    if (v < lo || v > hi) {
      throw obj.error(key, 'must be in $text');
    }
    return v;
  }

  final noise = NoiseSpec(
    sigmaM: rangeAt(n, 'sigmaM', 0, double.maxFinite, '[0, inf)'),
    rho: rangeAt(n, 'rho', 0, 1, '[0, 1)'),
    accMinM: n.positive('accMinM'),
    speedSigmaMps: rangeAt(n, 'speedSigmaMps', 0, double.maxFinite, '[0, inf)'),
    speedMissingRate: rangeAt(n, 'speedMissingRate', 0, 1, '[0, 1]'),
    outlierRate: rangeAt(n, 'outlierRate', 0, 1, '[0, 1]'),
    outlierMinM: rangeAt(n, 'outlierMinM', 0, double.maxFinite, '[0, inf)'),
    outlierMaxM: rangeAt(n, 'outlierMaxM', 0, double.maxFinite, '[0, inf)'),
  );
  if (noise.rho >= 1) {
    throw n.error('rho', 'must be in [0, 1)');
  }
  if (noise.outlierMinM > noise.outlierMaxM) {
    throw n.error('outlierMinM', 'must be <= outlierMaxM');
  }

  // scriptedOutliers
  final scripted = <ScriptedOutlierSpec>[];
  final scriptedList = o.has('scriptedOutliers')
      ? o.list('scriptedOutliers')
      : const <Object?>[];
  for (var i = 0; i < scriptedList.length; i++) {
    final e = o.objAt(scriptedList, 'scriptedOutliers', i)
      ..allowOnly(const {
        'atRemainingM',
        'count',
        'distanceToDestinationM',
        'accM',
      });
    final count = e.integer('count');
    if (count < 1) {
      throw e.error('count', 'must be >= 1');
    }
    final d = e.number('distanceToDestinationM');
    if (d < 0) {
      throw e.error('distanceToDestinationM', 'must be >= 0');
    }
    scripted.add(
      ScriptedOutlierSpec(
        atRemainingM: e.number('atRemainingM'),
        count: count,
        distanceToDestinationM: d,
        accM: e.positive('accM'),
      ),
    );
  }

  // cases
  final cases = <CaseSpec>[];
  final caseIds = <String>{};
  final caseList = o.list('cases');
  for (var i = 0; i < caseList.length; i++) {
    cases.add(_parseCase(o.objAt(caseList, 'cases', i), caseIds, gaps.length));
  }

  return Profile(
    file: file,
    id: id,
    title: title,
    vehicle: vehicle.single,
    route: routeId,
    destination: destination,
    seed: seed,
    noiseSeed: noiseSeed,
    startTime: startTime,
    startEpochS: startEpochS,
    sampleIntervalS: interval,
    startDwellS: startDwellS,
    endDwellS: endDwellS,
    motion: motion,
    speedLimits: List.unmodifiable(speedLimits),
    stops: List.unmodifiable(stops),
    regularStops: regularStops,
    gpsGaps: List.unmodifiable(gaps),
    noise: noise,
    scriptedOutliers: List.unmodifiable(scripted),
    cases: List.unmodifiable(cases),
  );
}

CaseSpec _parseCase(_Obj c, Set<String> caseIds, int gapCount) {
  c.allowOnly(const {'id', 'status', 'config', 'expect', 'forbid'});
  final id = c.id('id');
  if (!caseIds.add(id)) {
    throw c.error('id', 'duplicate case id "$id"');
  }
  final status = c.has('status') ? c.str('status') : 'draft';
  if (status != 'draft' && status != 'final') {
    throw c.error('status', 'must be draft or final');
  }
  final config = c.obj('config')
    ..allowOnly(const {'mode', 'thresholdM', 'thresholdMin', 'preAlert'});
  final modeName = config.str('mode');
  final CaseMode mode;
  final int threshold;
  switch (modeName) {
    case 'distance':
      mode = CaseMode.distance;
      if (config.has('thresholdMin')) {
        throw config.error('thresholdMin', 'not allowed in distance mode');
      }
      threshold = config.integer('thresholdM');
    case 'time':
      mode = CaseMode.time;
      if (config.has('thresholdM')) {
        throw config.error('thresholdM', 'not allowed in time mode');
      }
      threshold = config.integer('thresholdMin');
    default:
      throw config.error('mode', 'must be distance or time');
  }
  if (threshold <= 0) {
    throw config.error(
      mode == CaseMode.distance ? 'thresholdM' : 'thresholdMin',
      'must be > 0',
    );
  }
  final preAlert = !config.has('preAlert') || config.boolean('preAlert');

  String eventAt(_Obj obj, String key, Object? value) {
    if (value is! String || !kEventNames.contains(value)) {
      throw obj.error(key, 'unknown event "$value"');
    }
    return value;
  }

  final expect = <ExpectSpec>[];
  final expectList = c.list('expect');
  final expectEvents = <String>{};
  for (var j = 0; j < expectList.length; j++) {
    final e = c.objAt(expectList, 'expect', j)
      ..allowOnly(const {'event', 'notBefore', 'notAfter', 'ref'});
    final event = eventAt(e, 'event', e.raw('event'));
    if (!expectEvents.add(event)) {
      throw e.error('event', 'duplicate expected event "$event"');
    }
    expect.add(
      ExpectSpec(
        event: event,
        notBefore: _parseEdge(e.obj('notBefore'), gapCount),
        notAfter: _parseEdge(e.obj('notAfter'), gapCount),
        ref: e.str('ref'),
      ),
    );
  }
  final forbidList = c.list('forbid');
  final forbid = <String>[];
  for (var j = 0; j < forbidList.length; j++) {
    final event = eventAt(c, 'forbid[$j]', forbidList[j]);
    if (expectEvents.contains(event)) {
      throw c.error('forbid[$j]', 'event "$event" is also expected');
    }
    if (forbid.contains(event)) {
      throw c.error('forbid[$j]', 'duplicate event "$event"');
    }
    forbid.add(event);
  }
  return CaseSpec(
    id: id,
    status: status,
    mode: mode,
    threshold: threshold,
    preAlert: preAlert,
    expect: List.unmodifiable(expect),
    forbid: List.unmodifiable(forbid),
  );
}

WindowEdge _parseEdge(_Obj e, int gapCount) {
  e.allowOnly(const {'anchor', 'offsetS'});
  final Anchor anchor;
  try {
    anchor = Anchor.parse(e.str('anchor'));
  } on AnchorException catch (x) {
    throw e.error('anchor', x.message);
  }
  if ((anchor.kind == AnchorKind.gpsGapStart ||
          anchor.kind == AnchorKind.gpsGapEnd) &&
      anchor.value >= gapCount) {
    throw e.error(
      'anchor',
      'gap index ${anchor.value} out of range '
          '($gapCount gap(s))',
    );
  }
  final offset = e.has('offsetS') ? e.integer('offsetS') : 0;
  return WindowEdge(anchor, offset);
}

/// JSON object accessor that reports errors with a field path.
final class _Obj {
  new(this.map, this.file, this.path);

  factory root(Object? json, String file) {
    if (json is! Map<String, Object?>) {
      throw ProfileException(file, 'top level must be a JSON object');
    }
    return _Obj(json, file, '');
  }

  final Map<String, Object?> map;
  final String file;
  final String path;

  String at(String key) => path.isEmpty ? key : '$path.$key';

  ProfileException error(String key, String message) =>
      ProfileException('$file: ${at(key)}', message);

  bool has(String key) => map.containsKey(key);

  Object? raw(String key) => map[key];

  void allowOnly(Set<String> keys) {
    for (final k in map.keys) {
      if (!keys.contains(k)) {
        throw error(k, 'unknown key');
      }
    }
  }

  Object? _required(String key) {
    if (!map.containsKey(key)) {
      throw error(key, 'missing required key');
    }
    return map[key];
  }

  String str(String key) {
    final v = _required(key);
    if (v is! String || v.isEmpty) {
      throw error(key, 'must be a non-empty string');
    }
    return v;
  }

  String? optStr(String key) => has(key) ? str(key) : null;

  String id(String key) {
    final v = str(key);
    if (!kIdPattern.hasMatch(v)) {
      throw error(key, 'must match ${kIdPattern.pattern}');
    }
    return v;
  }

  int integer(String key) {
    final v = _required(key);
    if (v is! int) {
      throw error(key, 'must be an integer');
    }
    return v;
  }

  double number(String key) {
    final v = _required(key);
    if (v is! num || !v.isFinite) {
      throw error(key, 'must be a number');
    }
    return v.toDouble();
  }

  double positive(String key) {
    final v = number(key);
    if (v <= 0) {
      throw error(key, 'must be > 0');
    }
    return v;
  }

  bool boolean(String key) {
    final v = _required(key);
    if (v is! bool) {
      throw error(key, 'must be true or false');
    }
    return v;
  }

  List<Object?> list(String key) {
    final v = _required(key);
    if (v is! List<Object?>) {
      throw error(key, 'must be an array');
    }
    return v;
  }

  _Obj obj(String key) {
    final v = _required(key);
    if (v is! Map<String, Object?>) {
      throw error(key, 'must be an object');
    }
    return _Obj(v, file, at(key));
  }

  _Obj objAt(List<Object?> list, String key, int index) {
    final v = list[index];
    if (v is! Map<String, Object?>) {
      throw error('$key[$index]', 'must be an object');
    }
    return _Obj(v, file, at('$key[$index]'));
  }
}
