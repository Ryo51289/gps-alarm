/// Route and profile input files: parsing and validation (spec T02 §8,
/// T11 §2, §4, §5).
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

/// Pattern of a T10 test id in `testIds` (T11 §2.2).
final RegExp kTestIdPattern = RegExp(r'^TR\d{2}$');

/// `AlarmReason` values allowed in a `reason` filter (T10 §2.3).
const List<String> kAlarmReasons = [
  'DISTANCE',
  'TIME',
  'SMART_TIME',
  'SMART_DISTANCE',
  'SMART_SLOW_DISTANCE',
  'GPS_LOST',
  'LOW_BATTERY',
  'PASSED_CLOSEST',
  'OVERSHOOT',
  'SNOOZE_END',
  'TIMEOUT',
  'FALLBACK',
  'FALLBACK_MISSED',
];

/// `cause` values of `gpsLost`.
const List<String> kGpsLostCauses = [
  'NO_FIX_TIMEOUT',
  'NEVER_ACQUIRED',
  'PERMISSION_REVOKED',
  'SERVICES_OFF',
];

/// `cause` values of `fallbackAlarmChanged`.
const List<String> kFallbackCauses = [
  'ETA',
  'SNOOZE',
  'SUPERSEDED',
  'TRIP_ENDED',
  'RESYNC',
];

/// `config.actions[].action` values.
const List<String> kActions = [
  'dismiss',
  'snooze',
  'stop',
  'batteryMaxSaving',
  'batteryAlarmAt5',
  'batteryAlarmEarlier',
  'locationOff',
  'permissionRevoked',
  'locationOn',
];

/// `config.relaunch.fallbackStatus` values.
const List<String> kFallbackStatuses = [
  'auto',
  'PENDING',
  'RANG',
  'DISMISSED',
  'MISSING',
  'UNKNOWN',
];

/// `expectOutcome` values.
const List<String> kOutcomes = ['ON_TIME', 'SNOOZED', 'MISSED', 'CANCELLED'];

/// `expectSummary.vehicleGuess` values.
const List<String> kVehicleGuesses = ['TRAIN', 'COACH', 'BUS', 'UNKNOWN'];

/// `config.vehicleHint` values.
const List<String> kVehicleHints = ['train', 'coach', 'bus', 'unknown'];

/// `samplingModes` values (one element).
const List<String> kSamplingModes = ['all', 'policy'];

/// Integer (type I) engine parameters accepted in `config.params`
/// (T11 §5.1, T10 §5).
const Set<String> kIntParams = {
  'fixMaxAgeS',
  'outlierResetSpanS',
  'smoothWindowS',
  'stopExitMinM',
  'speedEmaTauS',
  'shortStopIncludeS',
  'speedEstablishedMovingS',
  'speedEstablishedSamples',
  'maxSpeedSampleGapS',
  'expectedSpeedKmhTrain',
  'expectedSpeedKmhCoach',
  'expectedSpeedKmhBus',
  'expectedSpeedKmhUnknown',
  'etaStopPenaltyS',
  'smartTargetS',
  'smartFloorM',
  'smartSlowSpeedKmh',
  'smartSlowHysteresisKmh',
  'shortDistanceWarnS',
  'preAlertLeadS',
  'preAlertDistanceFactor',
  'preAlertMinDistanceM',
  'preAlertMinGapS',
  'gpsLostMinS',
  'gpsLostIntervalFactor',
  'gpsLostAlarmEtaS',
  'acquireTimeoutS',
  'overshootNearMinM',
  'overshootOpenM',
  'overshootMinSpeedKmh',
  'passedClosestMinRadiusM',
  'passedClosestOpenMinM',
  'arrivedRadiusM',
  'snoozeS',
  'maxSnoozes',
  'alarmMaxActiveS',
  'maxTripMinS',
  'maxTripCapS',
  'lowBatteryAlarmPct',
  'lowBatteryEarlierPct',
  'batteryMinRateWindowS',
  'batteryReserveAfterAlarmS',
  'denseEnterS',
  'mediumEnterS',
  'samplingSparseIntervalS',
  'samplingSparseMinIntervalS',
  'samplingMediumIntervalS',
  'samplingMediumMinIntervalS',
  'samplingDenseIntervalS',
  'samplingDenseMinIntervalS',
  'maxSavingIntervalFactor',
  'fallbackLagS',
  'fallbackEarlyMaxS',
  'fallbackNearS',
  'fallbackNearSlackS',
  'fallbackMinLeadS',
  'fallbackQuietBeforeS',
  'fallbackMinShiftS',
  'fallbackMinIntervalS',
  'fallbackRetryS',
  'vehicleBusMaxAvgKmh',
};

/// Decimal (type D) engine parameters accepted in `config.params`.
const Set<String> kDoubleParams = {
  'accAbsMaxM',
  'accRelMax',
  'accHardMaxM',
  'maxPlausibleSpeedMps',
  'stationarySpeedMps',
  'motionAccFactor',
  'speedSampleMaxAccM',
  'routeFactorPrior',
  'routeFactorMin',
  'routeFactorMax',
  'minSpeedForEtaMps',
  'etaUncertaintyFrac',
  'distanceModeFactor',
  'lostErrFrac',
  'passedClosestReachFactor',
  'passedClosestOpenFrac',
  'batteryPriorDrainPctPerH',
  'batteryMinRatePctPerH',
  'tierHysteresisFactor',
  'fallbackEarlyFrac',
};

/// Fraction digits of a type D parameter in the fixture.
const int kParamDecimals = 4;

/// Parameters whose override invalidates the `expectFallback` formula.
const Set<String> kFallbackFormulaParams = {
  'fallbackLagS',
  'fallbackEarlyFrac',
  'fallbackEarlyMaxS',
  'fallbackNearS',
};

/// Parameters whose override invalidates the `closest.departT` anchor.
const Set<String> kClosestParams = {
  'passedClosestOpenMinM',
  'passedClosestOpenFrac',
};

/// Whether [x] has at most [kParamDecimals] fraction digits.
bool hasAtMostParamDecimals(num x) =>
    x is int || double.parse(x.toStringAsFixed(kParamDecimals)) == x;

/// Largest `|destinationOffsetM|`, metres.
const int kMaxDestinationOffsetM = 5000;

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

/// A GPS gap: `{at, durationS}` (T02) or `{atStop, offsetS, durationS |
/// until}` (T11 §4.3). Exactly one of [at] / [atStop] is set; with
/// [atStop], exactly one of [durationS] / [until].
final class GapSpec {
  const new({
    this.at,
    this.atStop,
    this.offsetS = 0,
    this.durationS,
    this.until,
  });

  /// Waypoint: the gap starts at the first tick reaching it.
  final String? at;

  /// Declared stop: the gap starts [offsetS] after arriving there.
  final String? atStop;
  final int offsetS;
  final int? durationS;

  /// Static end of the gap (not clamped).
  final WindowEdge? until;
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
    this.beyond = false,
  });

  final double atRemainingM;
  final int count;
  final double distanceToDestinationM;
  final double accM;

  /// `side: beyond`: the fake point lies on the far side of the destination
  /// (T11 §4.4); `false` = `behind` (T02 §6.5).
  final bool beyond;
}

enum CaseMode { distance, time, smart }

/// Static anchor plus offset (v1 window edge, `modeAt`, `until`).
final class WindowEdge {
  const new(this.anchor, this.offsetS);

  final Anchor anchor;
  final int offsetS;
}

/// A time point `At` (T11 §2.3): `{t}` or `{anchor, offsetS}`.
final class TimePoint {
  const new literal(int this.t) : anchor = null, offsetS = 0;

  const new anchored(Anchor this.anchor, this.offsetS) : t = null;

  /// Literal tick given in the profile.
  final int? t;
  final Anchor? anchor;
  final int offsetS;

  bool get isRun => anchor?.isRun ?? false;
}

/// Event name plus optional filters (T11 §2.4).
final class EventFilter {
  const new({required this.event, this.reason, this.ringNow, this.cause});

  final String event;
  final String? reason;
  final bool? ringNow;
  final String? cause;

  /// Same event and same filter keys and values.
  bool sameAs(EventFilter o) =>
      event == o.event &&
      reason == o.reason &&
      ringNow == o.ringNow &&
      cause == o.cause;

  /// Same event and every filter key of this also in [o] with the same
  /// value (T11 §5.2).
  bool coveredBy(EventFilter o) =>
      event == o.event &&
      (reason == null || reason == o.reason) &&
      (ringNow == null || ringNow == o.ringNow) &&
      (cause == null || cause == o.cause);
}

final class ExpectSpec {
  const new({
    required this.filter,
    required this.notBefore,
    required this.notAfter,
    required this.ref,
  });

  final EventFilter filter;
  final WindowEdge notBefore;
  final WindowEdge notAfter;
  final String ref;

  String get event => filter.event;
}

final class ExpectAfterSpec {
  const new({
    required this.filter,
    required this.after,
    required this.withinLo,
    required this.withinHi,
    required this.ref,
  });

  final EventFilter filter;
  final TimePoint after;
  final int withinLo;
  final int withinHi;
  final String ref;
}

final class ExpectFallbackSpec {
  const new({
    required this.modeAt,
    required this.toleranceLo,
    required this.toleranceHi,
    required this.ref,
  });

  final WindowEdge modeAt;
  final int toleranceLo;
  final int toleranceHi;
  final String ref;
}

final class ForbidAfterSpec {
  const new({required this.filter, required this.after});

  final EventFilter filter;
  final TimePoint after;
}

final class BatteryPoint {
  const new({required this.t, required this.levelPct, required this.charging});

  final int t;
  final int levelPct;
  final bool charging;
}

final class ActionSpec {
  const new({required this.at, required this.action});

  final TimePoint at;
  final String action;
}

final class RelaunchSpec {
  const new({required this.at, required this.fallbackStatus});

  final TimePoint at;
  final String fallbackStatus;
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
    this.testIds = const [],
    this.vehicleHint,
    this.params = const {},
    this.battery = const [],
    this.actions = const [],
    this.kill,
    this.relaunch,
    this.osDismissS,
    this.osSim,
    this.osRingMaxS,
    this.samplingModes,
    this.expectAfter = const [],
    this.expectFallback,
    this.expectOutcome,
    this.expectSummaryVehicle,
    this.forbidMatch = const [],
    this.forbidAfter = const [],
  });

  final String id;

  /// `draft` or `final`.
  final String status;
  final List<String> testIds;
  final CaseMode mode;

  /// `thresholdM` (distance), `thresholdMin` (time), null (smart).
  final int? threshold;
  final bool preAlert;
  final String? vehicleHint;

  /// Engine parameter overrides in ASCII order of the name; type I values
  /// are `int`, type D values `double`.
  final Map<String, num> params;
  final List<BatteryPoint> battery;
  final List<ActionSpec> actions;
  final TimePoint? kill;
  final RelaunchSpec? relaunch;

  /// `config.osDismiss.offsetS`.
  final int? osDismissS;
  final bool? osSim;
  final int? osRingMaxS;
  final List<String>? samplingModes;
  final List<ExpectSpec> expect;
  final List<ExpectAfterSpec> expectAfter;
  final ExpectFallbackSpec? expectFallback;
  final String? expectOutcome;

  /// `expectSummary.vehicleGuess`.
  final String? expectSummaryVehicle;
  final List<String> forbid;
  final List<EventFilter> forbidMatch;
  final List<ForbidAfterSpec> forbidAfter;
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
    this.dropSpeedAtStops = false,
    this.destinationOffsetM = 0,
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

  /// Perpendicular shift of the effective destination, metres; positive =
  /// left of the direction of travel (T11 §4.2).
  final int destinationOffsetM;
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

  /// Drop the reported speed of every sample taken while dwelling
  /// (T11 §4.1).
  final bool dropSpeedAtStops;
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
      'destinationOffsetM',
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
      'dropSpeedAtStops',
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
  final destinationOffsetM = o.has('destinationOffsetM')
      ? o.integer('destinationOffsetM')
      : 0;
  if (destinationOffsetM.abs() > kMaxDestinationOffsetM) {
    throw o.error(
      'destinationOffsetM',
      'must be in [-$kMaxDestinationOffsetM, $kMaxDestinationOffsetM]',
    );
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
  int gapDuration(_Obj e) {
    final duration = e.integer('durationS');
    if (duration <= 0 || duration % interval != 0) {
      throw e.error(
        'durationS',
        'must be a positive multiple of '
            'sampleIntervalS ($interval)',
      );
    }
    return duration;
  }

  for (var i = 0; i < gapList.length; i++) {
    final e = o.objAt(gapList, 'gpsGaps', i)
      ..allowOnly(const {'at', 'atStop', 'offsetS', 'durationS', 'until'});
    if (e.has('at')) {
      for (final k in const ['atStop', 'offsetS', 'until']) {
        if (e.has(k)) {
          throw e.error(k, 'not allowed together with "at"');
        }
      }
      waypointIndex(e, 'at');
      gaps.add(GapSpec(at: e.str('at'), durationS: gapDuration(e)));
      continue;
    }
    if (!e.has('atStop')) {
      throw e.error('at', 'missing required key (at or atStop)');
    }
    final atStop = e.str('atStop');
    if (!stopIds.contains(atStop)) {
      throw e.error('atStop', 'must be a stop declared in stops[]');
    }
    final offset = e.integer('offsetS');
    if (offset < 0 || offset % interval != 0) {
      throw e.error(
        'offsetS',
        'must be a non-negative multiple of sampleIntervalS ($interval)',
      );
    }
    if (e.has('durationS') == e.has('until')) {
      throw e.error('durationS', 'give exactly one of durationS and until');
    }
    gaps.add(
      GapSpec(
        atStop: atStop,
        offsetS: offset,
        durationS: e.has('durationS') ? gapDuration(e) : null,
        until: e.has('until')
            ? _parseEdge(e.obj('until'), AnchorUse.gapUntil, 0)
            : null,
      ),
    );
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
        'side',
      });
    final count = e.integer('count');
    if (count < 1) {
      throw e.error('count', 'must be >= 1');
    }
    final d = e.number('distanceToDestinationM');
    if (d < 0) {
      throw e.error('distanceToDestinationM', 'must be >= 0');
    }
    final side = e.has('side') ? e.str('side') : 'behind';
    if (side != 'behind' && side != 'beyond') {
      throw e.error('side', 'must be behind or beyond');
    }
    scripted.add(
      ScriptedOutlierSpec(
        atRemainingM: e.number('atRemainingM'),
        count: count,
        distanceToDestinationM: d,
        accM: e.positive('accM'),
        beyond: side == 'beyond',
      ),
    );
  }

  final dropSpeedAtStops =
      o.has('dropSpeedAtStops') && o.boolean('dropSpeedAtStops');

  // cases
  final cases = <CaseSpec>[];
  final caseIds = <String>{};
  final caseList = o.list('cases');
  final context = _CaseContext(
    interval: interval,
    gapCount: gaps.length,
    hasClosest: destinationOffsetM != 0,
  );
  for (var i = 0; i < caseList.length; i++) {
    cases.add(_parseCase(o.objAt(caseList, 'cases', i), caseIds, context));
  }

  return Profile(
    file: file,
    id: id,
    title: title,
    vehicle: vehicle.single,
    route: routeId,
    destination: destination,
    destinationOffsetM: destinationOffsetM,
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
    dropSpeedAtStops: dropSpeedAtStops,
    cases: List.unmodifiable(cases),
  );
}

final class _CaseContext {
  const new({
    required this.interval,
    required this.gapCount,
    required this.hasClosest,
  });

  final int interval;
  final int gapCount;
  final bool hasClosest;
}

/// Problem found by [checkCaseConsistency]: field path inside the case and
/// message.
typedef CaseIssue = ({String path, String message});

/// Reference of an `after` time point for the consistency checks: the
/// anchor text (null for a literal `t`) and the offset (or the literal `t`).
typedef AfterRef = ({String? anchor, int offset});

/// Cross checks of T11 §5.2 shared by the profile parser and `validate`.
List<CaseIssue> checkCaseConsistency({
  required List<EventFilter> expect,
  required List<(EventFilter, AfterRef, int)> expectAfter,
  required List<String> forbid,
  required List<EventFilter> forbidMatch,
  required List<(EventFilter, AfterRef)> forbidAfter,
}) {
  final issues = <CaseIssue>[];
  for (var j = 0; j < expect.length; j++) {
    for (var k = 0; k < j; k++) {
      if (expect[j].sameAs(expect[k])) {
        issues.add((
          path: 'expect[$j]',
          message:
              'duplicate expectation of "${expect[j].event}" with the same '
              'filters as expect[$k]',
        ));
      }
    }
  }
  final expectedFilters = [...expect, for (final (f, _, _) in expectAfter) f];
  for (var k = 0; k < forbid.length; k++) {
    if (forbid.indexOf(forbid[k]) < k) {
      issues.add((path: 'forbid[$k]', message: 'duplicate event'));
    } else if (expectedFilters.any((f) => f.event == forbid[k])) {
      issues.add((
        path: 'forbid[$k]',
        message: 'event "${forbid[k]}" is also expected',
      ));
    }
  }
  for (var k = 0; k < forbidMatch.length; k++) {
    if (expectedFilters.any(forbidMatch[k].coveredBy)) {
      issues.add((
        path: 'forbidMatch[$k]',
        message:
            'forbids an event matched by an expect/expectAfter entry '
            '("${forbidMatch[k].event}")',
      ));
    }
  }
  for (var k = 0; k < forbidAfter.length; k++) {
    final (ff, fa) = forbidAfter[k];
    for (final (ef, ea, lo) in expectAfter) {
      if (ea.anchor == fa.anchor &&
          ff.coveredBy(ef) &&
          ea.offset + lo > fa.offset) {
        issues.add((
          path: 'forbidAfter[$k]',
          message:
              'forbids an event that expectAfter requires after the same '
              'anchor ("${ff.event}")',
        ));
        break;
      }
    }
  }
  return issues;
}

/// Error of filter key [key] = [value] on [event], or null (T11 §2.4).
String? filterError(String event, String key, Object? value) {
  switch (key) {
    case 'reason':
      if (event != 'alarm') {
        return 'reason is only allowed on alarm';
      }
      return value is String && kAlarmReasons.contains(value)
          ? null
          : 'unknown alarm reason "$value"';
    case 'ringNow':
      if (event != 'alarm') {
        return 'ringNow is only allowed on alarm';
      }
      return value is bool ? null : 'must be true or false';
    case 'cause':
      final allowed = switch (event) {
        'gpsLost' => kGpsLostCauses,
        'fallbackAlarmChanged' => kFallbackCauses,
        _ => null,
      };
      if (allowed == null) {
        return 'cause is only allowed on gpsLost and fallbackAlarmChanged';
      }
      return value is String && allowed.contains(value)
          ? null
          : 'unknown $event cause "$value"';
  }
  return 'unknown filter key';
}

/// Reference conditions of T11 §2.3 for [anchor] in a case.
String? anchorReferenceError(
  Anchor anchor, {
  required bool hasKill,
  required bool hasRelaunch,
  required bool hasClosest,
  required Iterable<String> paramNames,
}) {
  final kind = anchor.kind;
  if (kind == AnchorKind.kill || kind == AnchorKind.osFallbackFired) {
    return hasKill ? null : 'anchor "${anchor.text}" needs config.kill';
  }
  if (kind == AnchorKind.relaunch) {
    return hasRelaunch ? null : 'anchor "relaunch" needs config.relaunch';
  }
  if (kind == AnchorKind.closest || kind == AnchorKind.closestDepart) {
    if (!hasClosest) {
      return 'anchor "${anchor.text}" needs destinationOffsetM != 0';
    }
    if (kind == AnchorKind.closestDepart &&
        paramNames.any(kClosestParams.contains)) {
      return 'anchor "closest.departT" cannot be used when params override '
          '${kClosestParams.join(' or ')}';
    }
  }
  return null;
}

CaseSpec _parseCase(_Obj c, Set<String> caseIds, _CaseContext ctx) {
  c.allowOnly(const {
    'id',
    'status',
    'testIds',
    'config',
    'samplingModes',
    'expect',
    'expectAfter',
    'expectFallback',
    'expectOutcome',
    'expectSummary',
    'forbid',
    'forbidMatch',
    'forbidAfter',
  });
  final id = c.id('id');
  if (!caseIds.add(id)) {
    throw c.error('id', 'duplicate case id "$id"');
  }
  final status = c.has('status') ? c.str('status') : 'draft';
  if (status != 'draft' && status != 'final') {
    throw c.error('status', 'must be draft or final');
  }
  final testIds = <String>[];
  if (c.has('testIds')) {
    final list = c.list('testIds');
    for (var j = 0; j < list.length; j++) {
      final v = list[j];
      if (v is! String || !kTestIdPattern.hasMatch(v)) {
        throw c.error('testIds[$j]', 'must match ${kTestIdPattern.pattern}');
      }
      if (testIds.contains(v)) {
        throw c.error('testIds[$j]', 'duplicate test id "$v"');
      }
      testIds.add(v);
    }
  }
  if (status == 'final' && testIds.isEmpty) {
    throw c.error('testIds', 'a final case needs a non-empty testIds');
  }

  final interval = ctx.interval;
  void multiple(_Obj obj, String key, int v) {
    if (v % interval != 0) {
      throw obj.error(key, 'must be a multiple of sampleIntervalS ($interval)');
    }
  }

  // Every anchor used by the case, for the reference checks at the end.
  final anchors = <(Anchor, _Obj)>[];

  TimePoint timePoint(_Obj p, AnchorUse use) {
    if (p.has('t')) {
      p.allowOnly(const {'t'});
      final t = p.integer('t');
      if (t < 0) {
        throw p.error('t', 'must be >= 0');
      }
      multiple(p, 't', t);
      return TimePoint.literal(t);
    }
    p.allowOnly(const {'anchor', 'offsetS'});
    final edge = _parseEdge(p, use, ctx.gapCount);
    multiple(p, 'offsetS', edge.offsetS);
    final offsetError = inputRunOffsetError(
      edge.anchor,
      use,
      edge.offsetS,
      interval,
    );
    if (offsetError != null) {
      throw p.error('offsetS', offsetError);
    }
    anchors.add((edge.anchor, p));
    return TimePoint.anchored(edge.anchor, edge.offsetS);
  }

  final config = c.obj('config')
    ..allowOnly(const {
      'mode',
      'thresholdM',
      'thresholdMin',
      'preAlert',
      'vehicleHint',
      'params',
      'battery',
      'actions',
      'kill',
      'relaunch',
      'osDismiss',
      'osSim',
      'osRingMaxS',
    });
  final modeName = config.str('mode');
  final CaseMode mode;
  int? threshold;
  switch (modeName) {
    case 'distance':
      mode = CaseMode.distance;
      if (config.has('thresholdMin')) {
        throw config.error('thresholdMin', 'not allowed in distance mode');
      }
      threshold = config.integer('thresholdM');
      if (threshold < 200 || threshold > 10000) {
        throw config.error('thresholdM', 'must be in [200, 10000]');
      }
    case 'time':
      mode = CaseMode.time;
      if (config.has('thresholdM')) {
        throw config.error('thresholdM', 'not allowed in time mode');
      }
      threshold = config.integer('thresholdMin');
      if (threshold < 5 || threshold > 60) {
        throw config.error('thresholdMin', 'must be in [5, 60]');
      }
    case 'smart':
      mode = CaseMode.smart;
      for (final k in const ['thresholdM', 'thresholdMin']) {
        if (config.has(k)) {
          throw config.error(k, 'not allowed in smart mode');
        }
      }
    default:
      throw config.error('mode', 'must be distance, time or smart');
  }
  final preAlert = !config.has('preAlert') || config.boolean('preAlert');
  String? vehicleHint;
  if (config.has('vehicleHint')) {
    vehicleHint = config.str('vehicleHint');
    if (!kVehicleHints.contains(vehicleHint)) {
      throw config.error(
        'vehicleHint',
        'must be one of ${kVehicleHints.join(', ')}',
      );
    }
  }

  final params = <String, num>{};
  if (config.has('params')) {
    final p = config.obj('params');
    final names = p.map.keys.toList()..sort();
    for (final name in names) {
      final v = p.raw(name);
      if (kIntParams.contains(name)) {
        if (v is! int) {
          throw p.error(name, 'type I parameter must be a JSON integer');
        }
        params[name] = v;
      } else if (kDoubleParams.contains(name)) {
        if (v is! num || !v.isFinite) {
          throw p.error(name, 'must be a number');
        }
        if (!hasAtMostParamDecimals(v)) {
          throw p.error(
            name,
            'type D parameter must have at most $kParamDecimals decimals',
          );
        }
        params[name] = v.toDouble();
      } else {
        throw p.error(name, 'unknown engine parameter');
      }
    }
  }

  final battery = <BatteryPoint>[];
  if (config.has('battery')) {
    final list = config.list('battery');
    for (var j = 0; j < list.length; j++) {
      final b = config.objAt(list, 'battery', j)
        ..allowOnly(const {'t', 'levelPct', 'charging'});
      final t = b.integer('t');
      if (t < 0) {
        throw b.error('t', 'must be >= 0');
      }
      multiple(b, 't', t);
      if (battery.isNotEmpty && t <= battery.last.t) {
        throw b.error('t', 'must increase strictly');
      }
      final level = b.integer('levelPct');
      if (level < 0 || level > 100) {
        throw b.error('levelPct', 'must be in [0, 100]');
      }
      battery.add(
        BatteryPoint(t: t, levelPct: level, charging: b.boolean('charging')),
      );
    }
  }

  final actions = <ActionSpec>[];
  if (config.has('actions')) {
    final list = config.list('actions');
    for (var j = 0; j < list.length; j++) {
      final a = config.objAt(list, 'actions', j)
        ..allowOnly(const {'at', 'action'});
      final action = a.str('action');
      if (!kActions.contains(action)) {
        throw a.error('action', 'unknown action "$action"');
      }
      actions.add(
        ActionSpec(
          at: timePoint(a.obj('at'), AnchorUse.action),
          action: action,
        ),
      );
    }
  }

  final kill = config.has('kill')
      ? timePoint(config.obj('kill'), AnchorUse.kill)
      : null;

  RelaunchSpec? relaunch;
  if (config.has('relaunch')) {
    final r = config.obj('relaunch')..allowOnly(const {'at', 'fallbackStatus'});
    if (kill == null) {
      throw config.error('relaunch', 'needs config.kill');
    }
    final at = timePoint(r.obj('at'), AnchorUse.relaunch);
    final status = r.str('fallbackStatus');
    if (!kFallbackStatuses.contains(status)) {
      throw r.error(
        'fallbackStatus',
        'must be one of ${kFallbackStatuses.join(', ')}',
      );
    }
    final killT = kill.t;
    final atT = at.t;
    if (killT != null && atT != null && atT <= killT) {
      throw r.error('at', 'must be after config.kill');
    }
    relaunch = RelaunchSpec(at: at, fallbackStatus: status);
  }

  int? osDismissS;
  if (config.has('osDismiss')) {
    final d = config.obj('osDismiss')..allowOnly(const {'offsetS'});
    if (relaunch == null || relaunch.fallbackStatus != 'auto') {
      throw config.error(
        'osDismiss',
        'needs config.relaunch with fallbackStatus auto',
      );
    }
    final offset = d.integer('offsetS');
    if (offset <= 0) {
      throw d.error('offsetS', 'must be > 0');
    }
    multiple(d, 'offsetS', offset);
    osDismissS = offset;
  }
  final osSim = config.has('osSim') ? config.boolean('osSim') : null;
  if (osSim == false && relaunch?.fallbackStatus == 'auto') {
    throw config.error(
      'osSim',
      'relaunch with fallbackStatus auto needs osSim',
    );
  }
  int? osRingMaxS;
  if (config.has('osRingMaxS')) {
    osRingMaxS = config.integer('osRingMaxS');
    if (osRingMaxS <= 0) {
      throw config.error('osRingMaxS', 'must be > 0');
    }
  }

  List<String>? samplingModes;
  if (c.has('samplingModes')) {
    final list = c.list('samplingModes');
    if (list.length != 1 ||
        list.single is! String ||
        !kSamplingModes.contains(list.single)) {
      throw c.error('samplingModes', 'must be ["all"] or ["policy"]');
    }
    samplingModes = [list.single! as String];
  }

  EventFilter filterOf(_Obj e) {
    final event = e.str('event');
    if (!kEventNames.contains(event)) {
      throw e.error('event', 'unknown event "$event"');
    }
    for (final key in const ['reason', 'ringNow', 'cause']) {
      if (e.has(key)) {
        final message = filterError(event, key, e.raw(key));
        if (message != null) {
          throw e.error(key, message);
        }
      }
    }
    return EventFilter(
      event: event,
      reason: e.raw('reason') as String?,
      ringNow: e.raw('ringNow') as bool?,
      cause: e.raw('cause') as String?,
    );
  }

  const filterKeys = {'event', 'reason', 'ringNow', 'cause'};

  final expect = <ExpectSpec>[];
  final expectList = c.list('expect');
  for (var j = 0; j < expectList.length; j++) {
    final e = c.objAt(expectList, 'expect', j)
      ..allowOnly(const {...filterKeys, 'notBefore', 'notAfter', 'ref'});
    final filter = filterOf(e);
    final nb = e.obj('notBefore');
    final na = e.obj('notAfter');
    final notBefore = _parseEdge(nb, AnchorUse.window, ctx.gapCount);
    final notAfter = _parseEdge(na, AnchorUse.window, ctx.gapCount);
    anchors
      ..add((notBefore.anchor, nb))
      ..add((notAfter.anchor, na));
    expect.add(
      ExpectSpec(
        filter: filter,
        notBefore: notBefore,
        notAfter: notAfter,
        ref: e.str('ref'),
      ),
    );
  }

  (int, int) pair(_Obj obj, String key) {
    final list = obj.list(key);
    if (list.length != 2 || list[0] is! int || list[1] is! int) {
      throw obj.error(key, 'must be an array of 2 integers');
    }
    return (list[0]! as int, list[1]! as int);
  }

  final expectAfter = <ExpectAfterSpec>[];
  if (c.has('expectAfter')) {
    final list = c.list('expectAfter');
    for (var j = 0; j < list.length; j++) {
      final e = c.objAt(list, 'expectAfter', j)
        ..allowOnly(const {...filterKeys, 'after', 'withinS', 'ref'});
      final filter = filterOf(e);
      final after = timePoint(e.obj('after'), AnchorUse.after);
      final (lo, hi) = pair(e, 'withinS');
      if (lo < 0 || lo > hi) {
        throw e.error('withinS', 'need 0 <= lo <= hi');
      }
      expectAfter.add(
        ExpectAfterSpec(
          filter: filter,
          after: after,
          withinLo: lo,
          withinHi: hi,
          ref: e.str('ref'),
        ),
      );
    }
  }

  ExpectFallbackSpec? expectFallback;
  if (c.has('expectFallback')) {
    final f = c.obj('expectFallback')
      ..allowOnly(const {'modeAt', 'toleranceS', 'ref'});
    if (kill == null) {
      throw c.error('expectFallback', 'needs config.kill');
    }
    final lagParams = params.keys.where(kFallbackFormulaParams.contains);
    if (lagParams.isNotEmpty) {
      throw c.error(
        'expectFallback',
        'cannot be computed when params override ${lagParams.join(', ')}',
      );
    }
    final mo = f.obj('modeAt');
    final modeAt = _parseEdge(mo, AnchorUse.modeAt, ctx.gapCount);
    multiple(mo, 'offsetS', modeAt.offsetS);
    anchors.add((modeAt.anchor, mo));
    final (lo, hi) = pair(f, 'toleranceS');
    if (lo > hi) {
      throw f.error('toleranceS', 'need lo <= hi');
    }
    expectFallback = ExpectFallbackSpec(
      modeAt: modeAt,
      toleranceLo: lo,
      toleranceHi: hi,
      ref: f.str('ref'),
    );
  }

  String? expectOutcome;
  if (c.has('expectOutcome')) {
    expectOutcome = c.str('expectOutcome');
    if (!kOutcomes.contains(expectOutcome)) {
      throw c.error('expectOutcome', 'must be one of ${kOutcomes.join(', ')}');
    }
  }
  String? summaryVehicle;
  if (c.has('expectSummary')) {
    final s = c.obj('expectSummary')..allowOnly(const {'vehicleGuess'});
    summaryVehicle = s.str('vehicleGuess');
    if (!kVehicleGuesses.contains(summaryVehicle)) {
      throw s.error(
        'vehicleGuess',
        'must be one of ${kVehicleGuesses.join(', ')}',
      );
    }
  }

  final forbidList = c.list('forbid');
  final forbid = <String>[];
  for (var j = 0; j < forbidList.length; j++) {
    final event = forbidList[j];
    if (event is! String || !kEventNames.contains(event)) {
      throw c.error('forbid[$j]', 'unknown event "$event"');
    }
    forbid.add(event);
  }
  final forbidMatch = <EventFilter>[];
  if (c.has('forbidMatch')) {
    final list = c.list('forbidMatch');
    for (var j = 0; j < list.length; j++) {
      final e = c.objAt(list, 'forbidMatch', j)..allowOnly(filterKeys);
      forbidMatch.add(filterOf(e));
    }
  }
  final forbidAfter = <ForbidAfterSpec>[];
  if (c.has('forbidAfter')) {
    final list = c.list('forbidAfter');
    for (var j = 0; j < list.length; j++) {
      final e = c.objAt(list, 'forbidAfter', j)
        ..allowOnly(const {...filterKeys, 'after'});
      forbidAfter.add(
        ForbidAfterSpec(
          filter: filterOf(e),
          after: timePoint(e.obj('after'), AnchorUse.after),
        ),
      );
    }
  }

  for (final (anchor, obj) in anchors) {
    final message = anchorReferenceError(
      anchor,
      hasKill: kill != null,
      hasRelaunch: relaunch != null,
      hasClosest: ctx.hasClosest,
      paramNames: params.keys,
    );
    if (message != null) {
      throw obj.error('anchor', message);
    }
  }

  AfterRef ref(TimePoint p) =>
      (anchor: p.anchor?.text, offset: p.anchor == null ? p.t! : p.offsetS);
  final issues = checkCaseConsistency(
    expect: [for (final e in expect) e.filter],
    expectAfter: [
      for (final e in expectAfter) (e.filter, ref(e.after), e.withinLo),
    ],
    forbid: forbid,
    forbidMatch: forbidMatch,
    forbidAfter: [for (final e in forbidAfter) (e.filter, ref(e.after))],
  );
  if (issues.isNotEmpty) {
    throw c.error(issues.first.path, issues.first.message);
  }

  return CaseSpec(
    id: id,
    status: status,
    testIds: List.unmodifiable(testIds),
    mode: mode,
    threshold: threshold,
    preAlert: preAlert,
    vehicleHint: vehicleHint,
    params: Map.unmodifiable(params),
    battery: List.unmodifiable(battery),
    actions: List.unmodifiable(actions),
    kill: kill,
    relaunch: relaunch,
    osDismissS: osDismissS,
    osSim: osSim,
    osRingMaxS: osRingMaxS,
    samplingModes: samplingModes,
    expect: List.unmodifiable(expect),
    expectAfter: List.unmodifiable(expectAfter),
    expectFallback: expectFallback,
    expectOutcome: expectOutcome,
    expectSummaryVehicle: summaryVehicle,
    forbid: List.unmodifiable(forbid),
    forbidMatch: List.unmodifiable(forbidMatch),
    forbidAfter: List.unmodifiable(forbidAfter),
  );
}

WindowEdge _parseEdge(_Obj e, AnchorUse use, int gapCount) {
  e.allowOnly(const {'anchor', 'offsetS'});
  final Anchor anchor;
  try {
    anchor = Anchor.parse(e.str('anchor'));
  } on AnchorException catch (x) {
    throw e.error('anchor', x.message);
  }
  final useError = anchorUseError(anchor, use);
  if (useError != null) {
    throw e.error('anchor', useError);
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
