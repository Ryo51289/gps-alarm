/// Pure pipeline profile + route -> GPX and expect bytes (spec T02 §1, §6).
library;

import 'dart:convert';
import 'dart:math' show sqrt;
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

  // GPS gaps (§6.5).
  final gaps = <GapRecord>[];
  for (var i = 0; i < profile.gpsGaps.length; i++) {
    final spec = profile.gpsGaps[i];
    final path = '$file: gpsGaps[$i]';
    final sAt = cum[route.indexOf(spec.at)];
    final j = states.indexWhere((st) => st.s >= sAt);
    if (j < 0) {
      throw ProfileException('$path.at', 'waypoint is never reached');
    }
    final fromT = states[j].t;
    if (fromT == 0) {
      throw ProfileException('$path.at', 'gap must start after t = 0');
    }
    final toT = fromT + spec.durationS;
    if (toT > lastTick - interval) {
      throw ProfileException(
        '$path.durationS',
        'gap must end at least one sample before the last tick',
      );
    }
    if (gaps.isNotEmpty && fromT <= gaps.last.toT) {
      throw ProfileException('$path.at', 'gaps must not overlap or touch');
    }
    gaps.add(GapRecord(fromT: fromT, toT: toT));
  }

  // Truth summary.
  final destIndex = route.indexOf(profile.destination);
  final destination = route.waypoints[destIndex];
  final truth = TraceTruth.compute(
    plan: plan,
    states: states,
    destinationGridIndex: plan.gridIndexOfWaypoint(
      destIndex,
      route.waypoints.length,
    ),
    destination: destination.pos,
    file: file,
    gaps: gaps,
  );

  // Scripted outliers (§6.5).
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
      final (e, n) = localEnM(destination.pos, states[j].pos);
      final r = sqrt(e * e + n * n);
      if (r == 0) {
        throw ProfileException(
          '$path.atRemainingM',
          'true position equals the destination',
        );
      }
      final d = spec.distanceToDestinationM;
      scripted[t] = ScriptedPoint(
        pos: offsetM(destination.pos, e * d / r, n * d / r),
        accM: spec.accM,
      );
    }
  }

  final sensor = simulateSensor(
    truth: states,
    noise: profile.noise,
    noiseSeed: profile.noiseSeed,
    gaps: gaps,
    scripted: scripted,
  );

  // A new trkseg after every hole in the sample sequence (= every gap).
  final segments = <List<Observation>>[];
  for (final o in sensor.observations) {
    if (segments.isEmpty || o.t - segments.last.last.t > interval) {
      segments.add([o]);
    } else {
      segments.last.add(o);
    }
  }

  // Cases.
  final cases = <ResolvedCase>[];
  for (var i = 0; i < profile.cases.length; i++) {
    final spec = profile.cases[i];
    final expect = <ResolvedExpect>[];
    for (var j = 0; j < spec.expect.length; j++) {
      final e = spec.expect[j];
      final path = '$file: cases[$i].expect[$j]';
      int resolve(WindowEdge edge, String key) {
        try {
          return truth.resolveEdge(edge.anchor, edge.offsetS);
        } on AnchorException catch (x) {
          throw ProfileException('$path.$key.anchor', x.message);
        }
      }

      final notBefore = resolve(e.notBefore, 'notBefore');
      final notAfter = resolve(e.notAfter, 'notAfter');
      if (notBefore > notAfter) {
        throw ProfileException(
          path,
          'window resolves to notBefore $notBefore > notAfter $notAfter',
        );
      }
      expect.add(
        ResolvedExpect(spec: e, notBefore: notBefore, notAfter: notAfter),
      );
    }
    cases.add(ResolvedCase(spec: spec, expect: List.unmodifiable(expect)));
  }

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
