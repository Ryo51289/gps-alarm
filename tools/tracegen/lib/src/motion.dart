/// Ground-truth motion along the route (spec T02 §6.1–6.3).
library;

import 'dart:math' show max, min, sqrt;

import 'package:tracegen/src/geo.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/rng.dart';

/// Distance grid step, metres.
const double kGridStepM = 10;

/// True state of the vehicle at one tick.
final class TruthState {
  const new({
    required this.t,
    required this.s,
    required this.pos,
    required this.speedMps,
    required this.dwelling,
  });

  /// Seconds since start (tick).
  final int t;

  /// Metres along the route.
  final double s;
  final LatLng pos;
  final double speedMps;
  final bool dwelling;
}

/// A mid-route stop on the distance grid.
final class StopPoint {
  const new({
    required this.gridIndex,
    required this.dwellS,
    this.waypointId,
    this.name,
  });

  final int gridIndex;
  final int dwellS;

  /// Set for stops declared in `stops[]`; null for `regularStops`.
  final String? waypointId;
  final String? name;
}

/// Speed profile and timeline on a 10 m grid.
final class MotionPlan {
  new _({
    required this.polyline,
    required this.intervalS,
    required this.gridS,
    required this.speeds,
    required this.dwell,
    required this.arriveT,
    required this.departT,
    required this.jitterFactors,
    required this.stopPoints,
  });

  /// Builds the plan of [profile] on [route]; throws [ProfileException]
  /// when stops collide on the grid.
  factory build(Profile profile, Route route) {
    final polyline = route.toPolyline();
    final length = polyline.lengthM;
    final n = (length / kGridStepM).ceil();
    final gridS = [for (var k = 0; k <= n; k++) min(k * kGridStepM, length)];

    double waypointS(String id) => polyline.cumulativeM[route.indexOf(id)];
    int gridIndexOfWaypoint(String id) => _waypointGridIndex(
      polyline,
      route.indexOf(id),
      route.waypoints.length,
      n,
    );

    // Cruise jitter factors, drawn in chunk order.
    final motion = profile.motion;
    final motionRng = SplitMix64.stream(profile.seed, kMotionStream);
    final chunks = (length / motion.jitterChunkM).ceil();
    final jitter = [
      for (var c = 0; c < chunks; c++)
        1 + motion.cruiseJitter * (2 * motionRng.nextDouble() - 1),
    ];

    final limitStarts = [
      for (final l in profile.speedLimits) waypointS(l.from),
    ];
    double limitAt(double s) {
      var e = 0;
      for (var i = 0; i < limitStarts.length; i++) {
        if (limitStarts[i] <= s) {
          e = i;
        }
      }
      final limit = profile.speedLimits[e];
      var v = limit.kmh / 3.6;
      if (limit.jitter) {
        final c = (s / motion.jitterChunkM).floor().clamp(0, chunks - 1);
        v = v * jitter[c];
      }
      return v;
    }

    final cap = [for (final s in gridS) limitAt(s)];
    cap[0] = 0;
    cap[n] = 0;
    final dwell = List<int>.filled(n + 1, 0);

    // Stops: declared waypoint stops first, then regular stops.
    final stopPoints = <StopPoint>[];
    bool collides(int k) =>
        k < 2 ||
        k > n - 2 ||
        stopPoints.any((p) => (p.gridIndex - k).abs() < 2);
    for (var i = 0; i < profile.stops.length; i++) {
      final stop = profile.stops[i];
      final k = gridIndexOfWaypoint(stop.at);
      if (collides(k)) {
        throw ProfileException(
          '${profile.file}: stops[$i].at',
          'stop at grid index $k is too close to the route ends or another '
              'stop',
        );
      }
      final w = route.waypoints[route.indexOf(stop.at)];
      stopPoints.add(
        StopPoint(
          gridIndex: k,
          dwellS: stop.dwellS,
          waypointId: w.id,
          name: w.name,
        ),
      );
    }
    final regular = profile.regularStops;
    if (regular != null) {
      final avoid = [
        0.0,
        length,
        waypointS(profile.destination),
        for (final stop in profile.stops) waypointS(stop.at),
      ];
      for (var i = 1; i * regular.everyM < length; i++) {
        final s = i * regular.everyM;
        if (avoid.any((a) => (s - a).abs() < regular.marginM)) {
          continue;
        }
        final k = _gridIndexOfS(s, n);
        if (collides(k)) {
          continue;
        }
        stopPoints.add(StopPoint(gridIndex: k, dwellS: regular.dwellS));
      }
    }
    stopPoints.sort((a, b) => a.gridIndex.compareTo(b.gridIndex));
    for (final p in stopPoints) {
      cap[p.gridIndex] = 0;
      dwell[p.gridIndex] = p.dwellS;
    }
    dwell[0] = dwell[0] + profile.startDwellS;
    dwell[n] = profile.endDwellS;

    // Speed profile: backward pass (braking), then forward pass (traction).
    final v = List<double>.of(cap);
    for (var k = n - 1; k >= 0; k--) {
      final dk = gridS[k + 1] - gridS[k];
      v[k] = min(v[k], sqrt(v[k + 1] * v[k + 1] + 2 * motion.decelMps2 * dk));
    }
    for (var k = 1; k <= n; k++) {
      final dk = gridS[k] - gridS[k - 1];
      v[k] = min(v[k], sqrt(v[k - 1] * v[k - 1] + 2 * motion.accelMps2 * dk));
    }

    // Timeline.
    final arriveT = List<double>.filled(n + 1, 0);
    final departT = List<double>.filled(n + 1, 0);
    departT[0] = dwell[0].toDouble();
    for (var k = 0; k < n; k++) {
      final dk = gridS[k + 1] - gridS[k];
      final dt = 2 * dk / (v[k] + v[k + 1]);
      arriveT[k + 1] = departT[k] + dt;
      departT[k + 1] = arriveT[k + 1] + dwell[k + 1];
    }

    return MotionPlan._(
      polyline: polyline,
      intervalS: profile.sampleIntervalS,
      gridS: List.unmodifiable(gridS),
      speeds: List.unmodifiable(v),
      dwell: List.unmodifiable(dwell),
      arriveT: List.unmodifiable(arriveT),
      departT: List.unmodifiable(departT),
      jitterFactors: List.unmodifiable(jitter),
      stopPoints: List.unmodifiable(stopPoints),
    );
  }

  final Polyline polyline;
  final int intervalS;

  /// `gridS[k] = min(k * 10, L)`, `k = 0..N`.
  final List<double> gridS;

  /// Planned speed at each grid point, m/s.
  final List<double> speeds;

  /// Dwell time at each grid point, seconds.
  final List<int> dwell;
  final List<double> arriveT;
  final List<double> departT;

  /// Cruise jitter factor of each `jitterChunkM` chunk.
  final List<double> jitterFactors;

  /// Mid-route stops, sorted by grid index.
  final List<StopPoint> stopPoints;

  /// Last grid index (`N`).
  int get lastIndex => gridS.length - 1;

  /// End of the trip (departure from the last grid point), seconds.
  double get endT => departT.last;

  /// Last tick `t <= endT`.
  int get lastTick => (endT / intervalS).floor() * intervalS;

  /// Grid index of the waypoint at [waypointIndex] of a route with
  /// [waypointCount] waypoints (spec §6.1 `idx`).
  int gridIndexOfWaypoint(int waypointIndex, int waypointCount) =>
      _waypointGridIndex(polyline, waypointIndex, waypointCount, lastIndex);

  /// True state at time [t] (seconds).
  TruthState at(int t) {
    final n = lastIndex;
    // Largest k with arriveT[k] <= t.
    var lo = 0;
    var hi = n;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (arriveT[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final k = lo;
    final double s;
    final double speed;
    final bool dwelling;
    if (k == n || t <= departT[k]) {
      s = gridS[k];
      speed = dwell[k] > 0 ? 0 : speeds[k];
      dwelling = dwell[k] > 0 && t >= arriveT[k];
    } else {
      final f = (t - departT[k]) / (arriveT[k + 1] - departT[k]);
      s = gridS[k] + f * (gridS[k + 1] - gridS[k]);
      speed = speeds[k] + f * (speeds[k + 1] - speeds[k]);
      dwelling = false;
    }
    return TruthState(
      t: t,
      s: s,
      pos: polyline.pointAt(max(0, min(s, polyline.lengthM))),
      speedMps: speed,
      dwelling: dwelling,
    );
  }

  /// True state at every tick `0, I, 2I, ..., lastTick`.
  List<TruthState> ticks() => [
    for (var t = 0; t <= lastTick; t += intervalS) at(t),
  ];
}

/// Nearest grid index of route position [s], clamped to `[0, lastIndex]`.
int _gridIndexOfS(double s, int lastIndex) =>
    (s / kGridStepM).round().clamp(0, lastIndex);

/// Grid index of waypoint [waypointIndex] (spec §6.1 `idx`): the last
/// waypoint maps to [lastIndex], any other to the nearest grid point.
int _waypointGridIndex(
  Polyline polyline,
  int waypointIndex,
  int waypointCount,
  int lastIndex,
) => waypointIndex == waypointCount - 1
    ? lastIndex
    : _gridIndexOfS(polyline.cumulativeM[waypointIndex], lastIndex);
