/// `<id>.expect.json` writer, schema v1 (spec T02 §7.3).
library;

import 'package:tracegen/src/canonical_json.dart';
import 'package:tracegen/src/milestones.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/sensor.dart';

/// Version of the `expect.json` schema written by this generator.
const int kSchemaVersion = 1;

/// Generator version; must equal `version` in `pubspec.yaml`.
const String kGeneratorVersion = '1.0.0';

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

/// A case whose expectations have been resolved to ticks.
final class ResolvedCase {
  const new({required this.spec, required this.expect});

  final CaseSpec spec;
  final List<ResolvedExpect> expect;
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
  final Waypoint destination;
  final TraceTruth truth;
  final int sampleCount;
  final List<OutlierRecord> outliers;
  final List<ResolvedCase> cases;
}

/// Ordered JSON tree of the expect file (key order as in spec §7.3).
Map<String, Object?> expectJsonTree(ExpectContent c) {
  final p = c.profile;
  final truth = c.truth;
  final overshoot = truth.overshoot;
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
      'lat': Fixed(c.destination.pos.lat, 7),
      'lng': Fixed(c.destination.pos.lng, 7),
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

Map<String, Object?> _caseJson(ResolvedCase rc) {
  final spec = rc.spec;
  return {
    'id': spec.id,
    'status': spec.status,
    'config': {
      'mode': spec.mode.name,
      if (spec.mode == CaseMode.distance) 'thresholdM': spec.threshold,
      if (spec.mode == CaseMode.time) 'thresholdMin': spec.threshold,
      'preAlert': spec.preAlert,
    },
    'expect': [
      for (final e in rc.expect)
        {
          'event': e.spec.event,
          'notBefore': e.notBefore,
          'notAfter': e.notAfter,
          'window': {
            'notBefore': {
              'anchor': e.spec.notBefore.anchor.text,
              'offsetS': e.spec.notBefore.offsetS,
            },
            'notAfter': {
              'anchor': e.spec.notAfter.anchor.text,
              'offsetS': e.spec.notAfter.offsetS,
            },
          },
          'ref': e.spec.ref,
        },
    ],
    'forbid': [...spec.forbid],
  };
}

/// Canonical JSON text of the expect file.
String writeExpect(ExpectContent c) => canonicalJson(expectJsonTree(c));
