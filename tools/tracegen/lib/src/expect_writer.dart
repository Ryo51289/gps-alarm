/// `<id>.expect.json` writer, schema v1 with the T11 additions (spec T02
/// §7.3, T11 §2).
library;

import 'package:tracegen/src/canonical_json.dart';
import 'package:tracegen/src/milestones.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/sensor.dart';

/// Version of the `expect.json` schema written by this generator.
const int kSchemaVersion = 1;

/// Generator version; must equal `version` in `pubspec.yaml`.
const String kGeneratorVersion = '1.1.0';

/// An expectation whose window has been resolved to ticks.
final class ResolvedExpect {
  const new({
    required this.spec,
    required this.notBefore,
    required this.notAfter,
  });

  final ExpectSpec spec;
  final int notBefore;
  final int notAfter;
}

/// A time point with its tick; [t] is null for a run-time anchor.
final class ResolvedTimePoint {
  const new(this.spec, this.t);

  final TimePoint spec;
  final int? t;
}

/// `expectFallback` resolved by T11 §5.3.
final class ResolvedFallback {
  const new({
    required this.spec,
    required this.asOfT,
    required this.notBefore,
    required this.notAfter,
    required this.modeAtT,
    required this.killT,
    required this.estimateT,
  });

  final ExpectFallbackSpec spec;
  final int asOfT;
  final int notBefore;
  final int notAfter;
  final int modeAtT;
  final int killT;

  /// `E` of T11 §5.3.
  final int estimateT;
}

/// A case whose static anchors have been resolved to ticks.
final class ResolvedCase {
  const new({
    required this.spec,
    required this.expect,
    this.kill,
    this.relaunchAt,
    this.actions = const [],
    this.expectAfter = const [],
    this.forbidAfter = const [],
    this.fallback,
  });

  final CaseSpec spec;
  final List<ResolvedExpect> expect;
  final ResolvedTimePoint? kill;
  final ResolvedTimePoint? relaunchAt;

  /// One per `spec.actions`, same order.
  final List<ResolvedTimePoint> actions;

  /// `after` of each `spec.expectAfter`, same order.
  final List<ResolvedTimePoint> expectAfter;

  /// `after` of each `spec.forbidAfter`, same order.
  final List<ResolvedTimePoint> forbidAfter;
  final ResolvedFallback? fallback;
}

/// Inputs of [writeExpect].
final class ExpectContent {
  const new({
    required this.profile,
    required this.destination,
    required this.truth,
    required this.sampleCount,
    required this.outliers,
    required this.cases,
  });

  final Profile profile;

  /// Destination waypoint (its position is replaced by the effective
  /// destination `truth.destination`).
  final Waypoint destination;
  final TraceTruth truth;
  final int sampleCount;
  final List<OutlierRecord> outliers;
  final List<ResolvedCase> cases;
}

/// Ordered JSON tree of the expect file (key order as in T02 §7.3 and
/// T11 §2.1, §2.2).
Map<String, Object?> expectJsonTree(ExpectContent c) {
  final p = c.profile;
  final truth = c.truth;
  final overshoot = truth.overshoot;
  final closest = truth.closest;
  return {
    'schemaVersion': kSchemaVersion,
    'generator': {'name': 'tracegen', 'version': kGeneratorVersion},
    'trace': {
      'id': p.id,
      'title': p.title,
      'vehicle': p.vehicle.name,
      'gpx': '${p.id}.gpx',
      'seed': p.seed,
      'noiseSeed': p.noiseSeed,
      'startTime': p.startTime,
      'sampleIntervalS': p.sampleIntervalS,
      'durationS': truth.endT,
      'sampleCount': c.sampleCount,
    },
    'destination': {
      'id': c.destination.id,
      if (c.destination.name != null) 'name': c.destination.name,
      'lat': Fixed(truth.destination.lat, 7),
      'lng': Fixed(truth.destination.lng, 7),
      if (p.destinationOffsetM != 0) 'offsetM': p.destinationOffsetM,
    },
    'truth': {
      'routeLengthM': truth.routeLengthM.round(),
      'destinationRouteM': truth.destinationRouteM.round(),
      'arrivalT': truth.arrivalT,
      'stops': [
        for (final s in truth.stops)
          {
            'routeM': s.routeM,
            'arriveT': s.arriveT,
            'departT': s.departT,
            if (s.name != null) 'name': s.name,
          },
      ],
      'gpsGaps': [
        for (final g in truth.gaps) {'fromT': g.fromT, 'toT': g.toT},
      ],
      'outliers': [
        for (final o in c.outliers)
          {'t': o.t, 'kind': o.kind.name, 'errorM': o.errorM},
      ],
      if (overshoot != null)
        'overshoot': {
          'closestT': overshoot.closestT,
          'closestM': overshoot.closestM,
          't': overshoot.t,
        },
      if (closest != null)
        'closest': {
          't': closest.t,
          'straightM': closest.straightM,
          'departT': closest.departT,
        },
    },
    'milestones': {
      'distance': [
        for (final m in truth.distanceMilestones())
          {
            'thresholdM': m.thresholdM,
            'routeT': m.routeT,
            'straightT': m.straightT,
          },
      ],
      'time': [
        for (final m in truth.timeMilestones())
          {'beforeArrivalMin': m.beforeArrivalMin, 't': m.t},
      ],
    },
    'cases': [for (final rc in c.cases) _caseJson(rc)],
  };
}

Map<String, Object?> _filterJson(EventFilter f) => {
  'event': f.event,
  if (f.reason != null) 'reason': f.reason,
  if (f.ringNow != null) 'ringNow': f.ringNow,
  if (f.cause != null) 'cause': f.cause,
};

/// `At` as written to the fixture (T11 §2.3).
Map<String, Object?> _timePointJson(ResolvedTimePoint p) {
  final anchor = p.spec.anchor;
  return {
    if (p.t != null) 't': p.t,
    if (anchor != null) ...{'anchor': anchor.text, 'offsetS': p.spec.offsetS},
  };
}

Map<String, Object?> _edgeJson(WindowEdge e) => {
  'anchor': e.anchor.text,
  'offsetS': e.offsetS,
};

Map<String, Object?> _caseJson(ResolvedCase rc) {
  final spec = rc.spec;
  final relaunch = spec.relaunch;
  final kill = rc.kill;
  final relaunchAt = rc.relaunchAt;
  final fallback = rc.fallback;
  return {
    'id': spec.id,
    'status': spec.status,
    if (spec.testIds.isNotEmpty) 'testIds': [...spec.testIds],
    'config': {
      'mode': spec.mode.name,
      if (spec.mode == CaseMode.distance) 'thresholdM': spec.threshold,
      if (spec.mode == CaseMode.time) 'thresholdMin': spec.threshold,
      'preAlert': spec.preAlert,
      if (spec.vehicleHint != null) 'vehicleHint': spec.vehicleHint,
      if (spec.params.isNotEmpty)
        'params': {
          for (final MapEntry(:key, :value) in spec.params.entries)
            key: value is int ? value : Fixed(value.toDouble(), kParamDecimals),
        },
      if (spec.battery.isNotEmpty)
        'battery': [
          for (final b in spec.battery)
            {'t': b.t, 'levelPct': b.levelPct, 'charging': b.charging},
        ],
      if (spec.actions.isNotEmpty)
        'actions': [
          for (var j = 0; j < spec.actions.length; j++)
            {
              'at': _timePointJson(rc.actions[j]),
              'action': spec.actions[j].action,
            },
        ],
      if (kill != null) 'kill': _timePointJson(kill),
      if (relaunch != null && relaunchAt != null)
        'relaunch': {
          'at': _timePointJson(relaunchAt),
          'fallbackStatus': relaunch.fallbackStatus,
        },
      if (spec.osDismissS != null) 'osDismiss': {'offsetS': spec.osDismissS},
      if (spec.osSim != null) 'osSim': spec.osSim,
      if (spec.osRingMaxS != null) 'osRingMaxS': spec.osRingMaxS,
    },
    if (spec.samplingModes != null) 'samplingModes': [...?spec.samplingModes],
    'expect': [
      for (final e in rc.expect)
        {
          ..._filterJson(e.spec.filter),
          'notBefore': e.notBefore,
          'notAfter': e.notAfter,
          'window': {
            'notBefore': _edgeJson(e.spec.notBefore),
            'notAfter': _edgeJson(e.spec.notAfter),
          },
          'ref': e.spec.ref,
        },
    ],
    if (spec.expectAfter.isNotEmpty)
      'expectAfter': [
        for (var j = 0; j < spec.expectAfter.length; j++)
          {
            ..._filterJson(spec.expectAfter[j].filter),
            'after': _timePointJson(rc.expectAfter[j]),
            'withinS': [
              spec.expectAfter[j].withinLo,
              spec.expectAfter[j].withinHi,
            ],
            'ref': spec.expectAfter[j].ref,
          },
      ],
    if (fallback != null)
      'expectFallback': {
        'asOfT': fallback.asOfT,
        'notBefore': fallback.notBefore,
        'notAfter': fallback.notAfter,
        'window': {
          'modeAt': _edgeJson(fallback.spec.modeAt),
          'modeAtT': fallback.modeAtT,
          'killT': fallback.killT,
          'estimateT': fallback.estimateT,
          'toleranceS': [fallback.spec.toleranceLo, fallback.spec.toleranceHi],
        },
        'ref': fallback.spec.ref,
      },
    if (spec.expectOutcome != null) 'expectOutcome': spec.expectOutcome,
    if (spec.expectSummaryVehicle != null)
      'expectSummary': {'vehicleGuess': spec.expectSummaryVehicle},
    'forbid': [...spec.forbid],
    if (spec.forbidMatch.isNotEmpty)
      'forbidMatch': [for (final f in spec.forbidMatch) _filterJson(f)],
    if (spec.forbidAfter.isNotEmpty)
      'forbidAfter': [
        for (var j = 0; j < spec.forbidAfter.length; j++)
          {
            ..._filterJson(spec.forbidAfter[j].filter),
            'after': _timePointJson(rc.forbidAfter[j]),
          },
      ],
  };
}

/// Canonical JSON text of the expect file.
String writeExpect(ExpectContent c) => canonicalJson(expectJsonTree(c));
