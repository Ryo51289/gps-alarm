/// Ground-truth summary, milestones and anchor resolution (spec T02 §6.6).
library;

import 'package:tracegen/src/anchor.dart';
import 'package:tracegen/src/geo.dart';
import 'package:tracegen/src/motion.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/sensor.dart';

/// Distance milestone thresholds, metres.
const List<int> kDistanceThresholdsM = [
  200,
  500,
  1000,
  2000,
  3000,
  5000,
  10000,
  25000,
  50000,
];

/// Time milestone thresholds, minutes before arrival.
const List<int> kTimeThresholdsMin = [5, 10, 15, 20, 30, 60];

/// Minimum route length after the destination for an overshoot, metres.
const double kOvershootRouteM = 1000;

/// Straight-line distance beyond the closest approach for an overshoot.
const double kOvershootMarginM = 1000;

final class StopTruth {
  const new({
    required this.routeM,
    required this.arriveT,
    required this.departT,
    this.name,
  });

  final int routeM;
  final int arriveT;
  final int departT;
  final String? name;
}

final class OvershootTruth {
  const new({required this.closestT, required this.closestM, required this.t});

  final int closestT;
  final int closestM;
  final int t;
}

final class DistanceMilestone {
  const new({
    required this.thresholdM,
    required this.routeT,
    required this.straightT,
  });

  final int thresholdM;
  final int routeT;

  /// Null when already within the threshold at `t = 0`.
  final int? straightT;
}

final class TimeMilestone {
  const new({required this.beforeArrivalMin, required this.t});

  final int beforeArrivalMin;
  final int t;
}

/// Facts measured on the true timeline.
final class TraceTruth {
  new _({
    required this.states,
    required this.destination,
    required this.routeLengthM,
    required this.destinationRouteM,
    required this.arrivalT,
    required this.destDepartT,
    required this.stops,
    required this.gaps,
    required this.overshoot,
    required this.straightM,
  });

  /// Computes the truth summary; throws [ProfileException] (labelled with
  /// [file]) when the destination is never reached or a stop is not
  /// visible on the tick grid.
  factory compute({
    required MotionPlan plan,
    required List<TruthState> states,
    required int destinationGridIndex,
    required LatLng destination,
    required String file,
    List<GapRecord> gaps = const [],
  }) {
    final sDest = plan.gridS[destinationGridIndex];
    final straight = [for (final st in states) distanceM(st.pos, destination)];

    final arrival = states.indexWhere((st) => st.s >= sDest);
    if (arrival < 0) {
      throw ProfileException(
        '$file: destination',
        'destination is never reached on the tick grid',
      );
    }
    final arrivalT = states[arrival].t;

    final stops = <StopTruth>[];
    for (final p in plan.stopPoints) {
      final sStop = plan.gridS[p.gridIndex];
      final at = [
        for (final st in states)
          if (st.dwelling && st.s == sStop) st.t,
      ];
      if (at.isEmpty) {
        throw ProfileException(
          '$file: stops',
          'stop at ${sStop.round()} m has no dwelling tick',
        );
      }
      stops.add(
        StopTruth(
          routeM: sStop.round(),
          arriveT: at.first,
          departT: at.last,
          name: p.name,
        ),
      );
    }

    var destDepartT = arrivalT;
    for (final st in states) {
      if (st.s == sDest) {
        destDepartT = st.t;
      }
    }

    OvershootTruth? overshoot;
    if (plan.polyline.lengthM - sDest >= kOvershootRouteM) {
      var closest = 0;
      for (var j = 1; j < straight.length; j++) {
        if (straight[j] < straight[closest]) {
          closest = j;
        }
      }
      final limit = straight[closest] + kOvershootMarginM;
      for (var j = 0; j < states.length; j++) {
        final st = states[j];
        if (st.t > destDepartT && st.s > sDest && straight[j] >= limit) {
          overshoot = OvershootTruth(
            closestT: states[closest].t,
            closestM: straight[closest].round(),
            t: st.t,
          );
          break;
        }
      }
    }

    return TraceTruth._(
      states: states,
      destination: destination,
      routeLengthM: plan.polyline.lengthM,
      destinationRouteM: sDest,
      arrivalT: arrivalT,
      destDepartT: destDepartT,
      stops: List.unmodifiable(stops),
      gaps: List.unmodifiable(gaps),
      overshoot: overshoot,
      straightM: List.unmodifiable(straight),
    );
  }

  /// One true state per tick.
  final List<TruthState> states;
  final LatLng destination;
  final double routeLengthM;

  /// `sDest`: position of the destination along the route.
  final double destinationRouteM;

  /// First tick with `s >= sDest`.
  final int arrivalT;

  /// Last tick standing at the destination (or [arrivalT]).
  final int destDepartT;
  final List<StopTruth> stops;
  final List<GapRecord> gaps;
  final OvershootTruth? overshoot;

  /// Straight-line distance to the destination at each tick.
  final List<double> straightM;

  /// Last tick (`durationS`).
  int get endT => states.last.t;

  /// Route distance still to go at tick index [j] (negative past it).
  double remainingAt(int j) => destinationRouteM - states[j].s;

  /// Distance milestones below the initial remaining distance.
  List<DistanceMilestone> distanceMilestones() => [
    for (final x in kDistanceThresholdsM)
      if (x < remainingAt(0))
        DistanceMilestone(
          thresholdM: x,
          routeT: _firstTick((j) => remainingAt(j) <= x)!,
          straightT: straightM[0] <= x
              ? null
              : _firstTick((j) => straightM[j] <= x),
        ),
  ];

  /// Time milestones that fall at or after the start.
  List<TimeMilestone> timeMilestones() => [
    for (final n in kTimeThresholdsMin)
      if (arrivalT - 60 * n >= 0)
        TimeMilestone(beforeArrivalMin: n, t: arrivalT - 60 * n),
  ];

  /// Tick of [anchor]; throws [AnchorException] when it does not exist.
  int resolveAnchor(Anchor anchor) {
    switch (anchor.kind) {
      case AnchorKind.start:
        return 0;
      case AnchorKind.end:
        return endT;
      case AnchorKind.arrival:
        return arrivalT;
      case AnchorKind.overshoot:
        final o = overshoot;
        if (o == null) {
          throw const AnchorException('trace has no overshoot');
        }
        return o.t;
      case AnchorKind.gpsGapStart:
      case AnchorKind.gpsGapEnd:
        if (anchor.value >= gaps.length) {
          throw AnchorException(
            'gap index ${anchor.value} out of range (${gaps.length} gap(s))',
          );
        }
        final g = gaps[anchor.value];
        return anchor.kind == AnchorKind.gpsGapStart ? g.fromT : g.toT;
      case AnchorKind.routeWithin:
        return _firstTick((j) => remainingAt(j) <= anchor.value) ??
            (throw AnchorException('"${anchor.text}" is never reached'));
      case AnchorKind.straightWithin:
        return _firstTick((j) => straightM[j] <= anchor.value) ??
            (throw AnchorException('"${anchor.text}" is never reached'));
    }
  }

  /// `clamp(anchor + offsetS, 0, durationS)`.
  int resolveEdge(Anchor anchor, int offsetS) =>
      (resolveAnchor(anchor) + offsetS).clamp(0, endT);

  int? _firstTick(bool Function(int j) test) {
    for (var j = 0; j < states.length; j++) {
      if (test(j)) {
        return states[j].t;
      }
    }
    return null;
  }
}
