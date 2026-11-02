/// Pure pipeline profile + route -> GPX and expect bytes (spec T02 §1, §6,
/// T11 §4, §5.3, T11.1 §4).
library;

import 'dart:convert';
import 'dart:math' show max, min, sqrt;
import 'dart:typed_data';

import 'package:tracegen/src/anchor.dart';
import 'package:tracegen/src/expect_writer.dart';
import 'package:tracegen/src/geo.dart';
import 'package:tracegen/src/gpx_writer.dart';
import 'package:tracegen/src/milestones.dart';
import 'package:tracegen/src/motion.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/sensor.dart';

/// The two files of one trace.
final class TraceFiles {
  const new({required this.id, required this.gpx, required this.expect});

  final String id;
  final Uint8List gpx;
  final Uint8List expect;
}

/// Every intermediate result of one generation run (for tests).
final class GeneratedTrace {
  const new({
    required this.profile,
    required this.route,
    required this.plan,
    required this.truth,
    required this.sensor,
    required this.segments,
    required this.cases,
    required this.gpxText,
    required this.expectText,
  });

  final Profile profile;
  final Route route;
  final MotionPlan plan;
  final TraceTruth truth;
  final SensorResult sensor;
  final List<List<Observation>> segments;
  final List<ResolvedCase> cases;
  final String gpxText;
  final String expectText;

  TraceFiles toFiles() => TraceFiles(
    id: profile.id,
    gpx: Uint8List.fromList(utf8.encode(gpxText)),
    expect: Uint8List.fromList(utf8.encode(expectText)),
  );
}

/// Generates the GPX and expect files of [profile]; throws
/// [ProfileException] when the scenario cannot be realised.
TraceFiles generateTrace(Profile profile, Route route) =>
    buildTrace(profile, route).toFiles();

/// Like [generateTrace] but keeps every intermediate result.
GeneratedTrace buildTrace(Profile profile, Route route) {
  final file = profile.file;
  final plan = MotionPlan.build(profile, route);
  final states = plan.ticks();
  final interval = profile.sampleIntervalS;
  final lastTick = plan.lastTick;
  final cum = plan.polyline.cumulativeM;

  // Destination waypoint W and effective destination D (T11 §4.2).
  final destIndex = route.indexOf(profile.destination);
  final destination = route.waypoints[destIndex];
  final effective = effectiveDestination(
    destination.pos,
    route.waypoints[destIndex - 1].pos,
    profile.destinationOffsetM,
  );

  // Truth of the motion (independent of the gaps).
  final motionTruth = TraceTruth.compute(
    plan: plan,
    states: states,
    destinationGridIndex: plan.gridIndexOfWaypoint(
      destIndex,
      route.waypoints.length,
    ),
    destination: effective,
    file: file,
    withClosest: profile.destinationOffsetM != 0,
  );

  // GPS gaps (T02 §6.5, T11 §4.3).
  final gaps = <GapRecord>[];
  for (var i = 0; i < profile.gpsGaps.length; i++) {
    final spec = profile.gpsGaps[i];
    final path = '$file: gpsGaps[$i]';
    final startKey = spec.at != null ? 'at' : 'atStop';
    final (fromT, toT, endKey) = _resolveGap(
      spec,
      path: path,
      route: route,
      plan: plan,
      states: states,
      cum: cum,
      motionTruth: motionTruth,
      interval: interval,
    );
    if (fromT == 0) {
      throw ProfileException('$path.$startKey', 'gap must start after t = 0');
    }
    if (toT > lastTick - interval) {
      throw ProfileException(
        '$path.$endKey',
        'gap must end at least one sample before the last tick',
      );
    }
    if (gaps.isNotEmpty && fromT <= gaps.last.toT) {
      throw ProfileException(
        '$path.$startKey',
        'gaps must not overlap or touch',
      );
    }
    gaps.add(GapRecord(fromT: fromT, toT: toT));
  }

  final truth = motionTruth.withGaps(gaps);

  // Scripted outliers (T02 §6.5, T11 §4.4), relative to D.
  bool inGap(int t) => gaps.any((g) => g.contains(t));
  final scripted = <int, ScriptedPoint>{};
  for (var i = 0; i < profile.scriptedOutliers.length; i++) {
    final spec = profile.scriptedOutliers[i];
    final path = '$file: scriptedOutliers[$i]';
    var j0 = -1;
    for (var j = 0; j < states.length; j++) {
      if (truth.remainingAt(j) <= spec.atRemainingM && !inGap(states[j].t)) {
        j0 = j;
        break;
      }
    }
    if (j0 < 0) {
      throw ProfileException('$path.atRemainingM', 'never reached');
    }
    for (var c = 0; c < spec.count; c++) {
      final j = j0 + c;
      if (j >= states.length) {
        throw ProfileException('$path.count', 'runs past the last tick');
      }
      final t = states[j].t;
      if (inGap(t)) {
        throw ProfileException('$path.count', 'touches a GPS gap');
      }
      if (scripted.containsKey(t)) {
        throw ProfileException('$path.count', 'overlaps another group');
      }
      final (e, n) = localEnM(effective, states[j].pos);
      final r = sqrt(e * e + n * n);
      if (r == 0) {
        throw ProfileException(
          '$path.atRemainingM',
          'true position equals the destination',
        );
      }
      final d = spec.distanceToDestinationM;
      scripted[t] = ScriptedPoint(
        pos: spec.beyond
            ? offsetM(effective, -e * d / r, -n * d / r)
            : offsetM(effective, e * d / r, n * d / r),
        accM: spec.accM,
      );
    }
  }

  var sensor = simulateSensor(
    truth: states,
    noise: profile.noise,
    noiseSeed: profile.noiseSeed,
    gaps: gaps,
    scripted: scripted,
  );
  if (profile.dropSpeedAtStops) {
    sensor = dropSpeedWhileDwelling(sensor, states);
  }

  // A new trkseg after every hole in the sample sequence (= every gap).
  final segments = <List<Observation>>[];
  for (final o in sensor.observations) {
    if (segments.isEmpty || o.t - segments.last.last.t > interval) {
      segments.add([o]);
    } else {
      segments.last.add(o);
    }
  }

  final cases = <ResolvedCase>[
    for (var i = 0; i < profile.cases.length; i++)
      resolveCase(
        profile.cases[i],
        truth,
        path: '$file: cases[$i]',
        sampleIntervalS: interval,
        vehicle: profile.vehicle.name,
      ),
  ];

  final gpxText = writeGpx(
    GpxTrack(
      id: profile.id,
      title: profile.title,
      vehicle: profile.vehicle.name,
      startEpochS: profile.startEpochS,
      segments: segments,
    ),
  );
  final expectText = writeExpect(
    ExpectContent(
      profile: profile,
      destination: destination,
      truth: truth,
      sampleCount: sensor.observations.length,
      outliers: sensor.outliers,
      cases: cases,
    ),
  );
  return GeneratedTrace(
    profile: profile,
    route: route,
    plan: plan,
    truth: truth,
    sensor: sensor,
    segments: segments,
    cases: cases,
    gpxText: gpxText,
    expectText: expectText,
  );
}

/// `(fromT, toT, key of the end field)` of one gap spec.
(int, int, String) _resolveGap(
  GapSpec spec, {
  required String path,
  required Route route,
  required MotionPlan plan,
  required List<TruthState> states,
  required List<double> cum,
  required TraceTruth motionTruth,
  required int interval,
}) {
  final at = spec.at;
  if (at != null) {
    final sAt = cum[route.indexOf(at)];
    final j = states.indexWhere((st) => st.s >= sAt);
    if (j < 0) {
      throw ProfileException('$path.at', 'waypoint is never reached');
    }
    final fromT = states[j].t;
    return (fromT, fromT + spec.durationS!, 'durationS');
  }
  // Truth stops follow plan.stopPoints one to one.
  final k = plan.stopPoints.indexWhere((p) => p.waypointId == spec.atStop);
  final stop = motionTruth.stops[k];
  final fromT = stop.arriveT + spec.offsetS;
  if (fromT > stop.departT) {
    throw ProfileException(
      '$path.offsetS',
      'gap must start while dwelling at ${spec.atStop} '
          '(arriveT ${stop.arriveT}, departT ${stop.departT})',
    );
  }
  final until = spec.until;
  if (until == null) {
    return (fromT, fromT + spec.durationS!, 'durationS');
  }
  final int toT;
  try {
    toT = motionTruth.resolveAnchor(until.anchor) + until.offsetS;
  } on AnchorException catch (x) {
    throw ProfileException('$path.until.anchor', x.message);
  }
  if (toT <= fromT || (toT - fromT) % interval != 0) {
    throw ProfileException(
      '$path.until',
      'gap end $toT must follow the start $fromT by a positive multiple of '
          'sampleIntervalS ($interval)',
    );
  }
  return (fromT, toT, 'until');
}

/// Effective destination D (T11 §4.2): [w] shifted by [offset] metres
/// perpendicular to the direction [previous] -> [w]; positive = left.
LatLng effectiveDestination(LatLng w, LatLng previous, int offset) {
  if (offset == 0) {
    return w;
  }
  final (e, n) = localEnM(w, previous);
  final r = sqrt(e * e + n * n);
  return offsetM(w, offset * n / r, -offset * e / r);
}

/// [sensor] with no speed on the samples of every dwelling tick (T11 §4.1).
SensorResult dropSpeedWhileDwelling(
  SensorResult sensor,
  List<TruthState> states,
) {
  final dwelling = {
    for (final st in states)
      if (st.dwelling) st.t,
  };
  return SensorResult(
    observations: List.unmodifiable([
      for (final o in sensor.observations)
        if (dwelling.contains(o.t))
          Observation(t: o.t, pos: o.pos, accM: o.accM)
        else
          o,
    ]),
    outliers: sensor.outliers,
  );
}

/// Resolves the static time points and windows of [spec] on [truth];
/// throws [ProfileException] labelled with [path] (T11 §2.3, §5.3,
/// T11.1 §4). [vehicle] is `trace.vehicle` (default of the vehicle hint).
ResolvedCase resolveCase(
  CaseSpec spec,
  TraceTruth truth, {
  required String path,
  required int sampleIntervalS,
  required String vehicle,
}) {
  final endT = truth.endT;

  ResolvedTimePoint point(TimePoint p, String where, int? killT) {
    final anchor = p.anchor;
    if (anchor == null) {
      final t = p.t!;
      if (t > endT) {
        throw ProfileException(
          '$path.$where.t',
          't = $t is after durationS ($endT)',
        );
      }
      return ResolvedTimePoint(p, t);
    }
    if (anchor.isRun) {
      return ResolvedTimePoint(p, null);
    }
    final int t;
    try {
      t = truth.resolveAnchor(anchor, killT: killT) + p.offsetS;
    } on AnchorException catch (x) {
      throw ProfileException('$path.$where.anchor', x.message);
    }
    if (t < 0 || t > endT) {
      throw ProfileException(
        '$path.$where',
        'resolves to t = $t outside [0, durationS ($endT)]',
      );
    }
    return ResolvedTimePoint(p, t);
  }

  final killSpec = spec.kill;
  final kill = killSpec == null ? null : point(killSpec, 'config.kill', null);
  final killT = kill?.t;
  final relaunchSpec = spec.relaunch;
  final relaunch = relaunchSpec == null
      ? null
      : point(relaunchSpec.at, 'config.relaunch.at', killT);
  final relaunchT = relaunch?.t;
  if (relaunchT != null && killT != null && relaunchT <= killT) {
    throw ProfileException(
      '$path.config.relaunch.at',
      'resolves to t = $relaunchT, not after config.kill (t = $killT)',
    );
  }
  for (var j = 0; j < spec.battery.length; j++) {
    if (spec.battery[j].t > endT) {
      throw ProfileException(
        '$path.config.battery[$j].t',
        'is after durationS ($endT)',
      );
    }
  }
  final actions = [
    for (var j = 0; j < spec.actions.length; j++)
      point(spec.actions[j].at, 'config.actions[$j].at', killT),
  ];

  final expect = <ResolvedExpect>[];
  for (var j = 0; j < spec.expect.length; j++) {
    final e = spec.expect[j];
    final where = '$path.expect[$j]';
    int resolve(WindowEdge edge, String key) {
      try {
        return truth.resolveEdge(edge.anchor, edge.offsetS, killT: killT);
      } on AnchorException catch (x) {
        throw ProfileException('$where.$key.anchor', x.message);
      }
    }

    final notBefore = resolve(e.notBefore, 'notBefore');
    final notAfter = resolve(e.notAfter, 'notAfter');
    if (notBefore > notAfter) {
      throw ProfileException(
        where,
        'window resolves to notBefore $notBefore > notAfter $notAfter',
      );
    }
    expect.add(
      ResolvedExpect(spec: e, notBefore: notBefore, notAfter: notAfter),
    );
  }
  final expectAfter = [
    for (var j = 0; j < spec.expectAfter.length; j++)
      point(spec.expectAfter[j].after, 'expectAfter[$j].after', killT),
  ];
  final forbidAfter = [
    for (var j = 0; j < spec.forbidAfter.length; j++)
      point(spec.forbidAfter[j].after, 'forbidAfter[$j].after', killT),
  ];

  ResolvedFallback? fallback;
  final f = spec.expectFallback;
  if (f != null && killT != null) {
    final int modeAtT;
    try {
      modeAtT =
          truth.resolveAnchor(f.modeAt.anchor, killT: killT) + f.modeAt.offsetS;
    } on AnchorException catch (x) {
      throw ProfileException('$path.expectFallback.modeAt.anchor', x.message);
    }
    final asOfT = killT - sampleIntervalS;
    if (asOfT < 0) {
      throw ProfileException(
        '$path.config.kill',
        'expectFallback needs kill.t >= sampleIntervalS',
      );
    }
    // truth.straightM[j] is the tick j * I (true position, effective
    // destination).
    final asOfIndex = asOfT ~/ sampleIntervalS;
    assert(truth.states[asOfIndex].t == asOfT, 'tick grid');
    fallback = fallbackWindow(
      spec: f,
      mode: spec.mode,
      threshold: spec.threshold,
      hint: spec.vehicleHint ?? vehicle,
      modeAtT: modeAtT,
      killT: killT,
      asOfStraightM: truth.straightM[asOfIndex].floor(),
      sampleIntervalS: sampleIntervalS,
      durationS: endT,
    );
  }

  ResolvedKillSweep? killSweep;
  final ks = spec.killSweep;
  if (ks != null) {
    final from = point(ks.from, 'killSweep.from', null);
    final fromT = from.t!;
    if (fromT < sampleIntervalS) {
      throw ProfileException(
        '$path.killSweep.from',
        'resolves to t = $fromT, must be >= sampleIntervalS '
            '($sampleIntervalS)',
      );
    }
    killSweep = ResolvedKillSweep(
      spec: ks,
      from: from,
      notAfter: point(ks.notAfter, 'killSweep.notAfter', null),
      earlyFrom: point(ks.earlyFrom, 'killSweep.earlyFrom', null),
    );
  }

  return ResolvedCase(
    spec: spec,
    expect: List.unmodifiable(expect),
    kill: kill,
    relaunchAt: relaunch,
    actions: List.unmodifiable(actions),
    expectAfter: List.unmodifiable(expectAfter),
    forbidAfter: List.unmodifiable(forbidAfter),
    fallback: fallback,
    killSweep: killSweep,
  );
}

/// `fallbackLagS` default (T10 §5).
const int kFallbackLagS = 30;

/// `fallbackNearS` default (T10 §5).
const int kFallbackNearS = 600;

/// `fallbackEarlyMaxS` default (T10 §5, T10.2).
const int kFallbackEarlyMaxS = 3600;

/// `1 / fallbackEarlyFrac` for the default `fallbackEarlyFrac` 0.25
/// (T10.2).
const int kFallbackEarlyDivisor = 4;

/// `100 · 3.6 · routeFactorPrior (1.2) / fallbackHintSpeedFactor (1.0)`:
/// seconds per 100 m at 1 km/h along the route (T10 §8.3).
const int kFallbackHintNumerator = 432;

/// `etaStopPenaltyS` default (T10 §5).
const int kEtaStopPenaltyS = 20;

/// `smartTargetS` default (T10 §5).
const int kSmartTargetS = 600;

/// `expectedSpeedKmh*` defaults by vehicle hint (T10 §5).
const Map<String, int> kExpectedSpeedKmh = {
  'train': 55,
  'coach': 60,
  'bus': 20,
  'unknown': 60,
};

/// Fallback alarm estimates of T11.1 §4 (T10 §8.3, D4), integers only.
///
/// [threshold] is `thresholdM` (distance), `thresholdMin` (time) or null
/// (smart); [hint] is the effective vehicle hint (a key of
/// [kExpectedSpeedKmh]); [asOfStraightM] is the straight-line distance from
/// the true position at `killT − sampleIntervalS` to the destination.
({int estimateT, int hintEstimateT, int notBefore, int notAfter})
fallbackEstimates({
  required CaseMode mode,
  required int? threshold,
  required String hint,
  required int modeAtT,
  required int killT,
  required int asOfStraightM,
  required int sampleIntervalS,
  required int durationS,
  required int toleranceLo,
  required int toleranceHi,
}) {
  final asOfT = killT - sampleIntervalS;
  final lead = max(0, modeAtT - killT - kFallbackNearS);
  final early = min(kFallbackEarlyMaxS, lead ~/ kFallbackEarlyDivisor);
  final estimateT = modeAtT + kFallbackLagS - early;

  final kmh = kExpectedSpeedKmh[hint];
  if (kmh == null) {
    throw ArgumentError.value(hint, 'hint', 'unknown vehicle hint');
  }
  final divisor = 100 * kmh;
  final travelS = (asOfStraightM * kFallbackHintNumerator) ~/ divisor;
  final int hintS;
  switch (mode) {
    case CaseMode.distance:
      hintS =
          (max(0, asOfStraightM - threshold!) * kFallbackHintNumerator) ~/
          divisor;
    case CaseMode.time:
      hintS = max(0, travelS + kEtaStopPenaltyS - 60 * threshold!);
    case CaseMode.smart:
      hintS = max(0, travelS + kEtaStopPenaltyS - kSmartTargetS);
  }
  final hintEarly = min(
    kFallbackEarlyMaxS,
    max(0, hintS - kFallbackNearS) ~/ kFallbackEarlyDivisor,
  );
  final hintEstimateT =
      asOfT + max<int>(kFallbackNearS, hintS + kFallbackLagS - hintEarly);
  return (
    estimateT: estimateT,
    hintEstimateT: hintEstimateT,
    notBefore: (min(estimateT, hintEstimateT) + toleranceLo).clamp(
      0,
      durationS,
    ),
    notAfter: (estimateT + toleranceHi).clamp(0, durationS),
  );
}

/// `expectFallback` window (T11.1 §4), integers only.
ResolvedFallback fallbackWindow({
  required ExpectFallbackSpec spec,
  required CaseMode mode,
  required int? threshold,
  required String hint,
  required int modeAtT,
  required int killT,
  required int asOfStraightM,
  required int sampleIntervalS,
  required int durationS,
}) {
  final e = fallbackEstimates(
    mode: mode,
    threshold: threshold,
    hint: hint,
    modeAtT: modeAtT,
    killT: killT,
    asOfStraightM: asOfStraightM,
    sampleIntervalS: sampleIntervalS,
    durationS: durationS,
    toleranceLo: spec.toleranceLo,
    toleranceHi: spec.toleranceHi,
  );
  return ResolvedFallback(
    spec: spec,
    asOfT: killT - sampleIntervalS,
    notBefore: e.notBefore,
    notAfter: e.notAfter,
    modeAtT: modeAtT,
    killT: killT,
    estimateT: e.estimateT,
    asOfStraightM: asOfStraightM,
    hintEstimateT: e.hintEstimateT,
  );
}
