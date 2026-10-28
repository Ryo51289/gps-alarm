import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const LatLng origin = LatLng(20, 105);

List<TruthState> standing(int count, {double speed = 0}) => [
  for (var j = 0; j < count; j++)
    TruthState(t: j * 5, s: 0, pos: origin, speedMps: speed, dwelling: false),
];

NoiseSpec noiseSpec({
  double sigma = 10,
  double rho = 0.9,
  double speedSigma = 0,
  double missing = 0,
  double outlierRate = 0,
  double outlierMin = 0,
  double outlierMax = 0,
}) => NoiseSpec(
  sigmaM: sigma,
  rho: rho,
  accMinM: 3,
  speedSigmaMps: speedSigma,
  speedMissingRate: missing,
  outlierRate: outlierRate,
  outlierMinM: outlierMin,
  outlierMaxM: outlierMax,
);

void main() {
  test('correlated noise statistics (TC10)', () {
    final result = simulateSensor(
      truth: standing(20000),
      noise: noiseSpec(),
      noiseSeed: 11,
    );
    final obs = result.observations;
    expect(obs, hasLength(20000));
    final east = <double>[];
    final north = <double>[];
    for (final o in obs) {
      final (e, n) = localEnM(origin, o.pos);
      east.add(e);
      north.add(n);
      expect(o.accM, inInclusiveRange(12.0, 18.0));
    }
    for (final axis in [east, north]) {
      final rms = math.sqrt(
        axis.fold<double>(0, (s, x) => s + x * x) / axis.length,
      );
      expect(rms, inInclusiveRange(8.5, 11.5));
      var num = 0.0;
      var den = 0.0;
      for (var j = 0; j < axis.length; j++) {
        den += axis[j] * axis[j];
        if (j > 0) {
          num += axis[j] * axis[j - 1];
        }
      }
      expect(num / den, inInclusiveRange(0.85, 0.95));
    }
  });

  test('missing speed rate (TC11)', () {
    final missing = simulateSensor(
      truth: standing(10000, speed: 10),
      noise: noiseSpec(speedSigma: 0.5, missing: 0.3),
      noiseSeed: 12,
    ).observations;
    final ratio = missing.where((o) => o.speedMps == null).length / 10000;
    expect(ratio, inInclusiveRange(0.27, 0.33));

    final complete = simulateSensor(
      truth: standing(10000, speed: 10),
      noise: noiseSpec(speedSigma: 0.5),
      noiseSeed: 12,
    ).observations;
    expect(complete.where((o) => o.speedMps == null), isEmpty);
    for (final o in [...missing, ...complete]) {
      expect(o.speedMps ?? 0, greaterThanOrEqualTo(0));
    }
  });

  test('random outliers (TC14)', () {
    final result = simulateSensor(
      truth: standing(20000),
      noise: noiseSpec(outlierRate: 0.01, outlierMin: 300, outlierMax: 1500),
      noiseSeed: 13,
    );
    expect(result.outliers.length, inInclusiveRange(150, 250));
    for (final o in result.outliers) {
      expect(o.kind, OutlierKind.random);
      expect(o.errorM, inInclusiveRange(299, 1501));
    }
  });

  group('trace with a GPS gap (TC12)', () {
    Map<String, Object?> profile({required bool gap}) => synthProfileJson(
      overrides: {
        'endDwellS': 10,
        // 10 m/s, so the 360 s gap at 5 km ends before the destination.
        'speedLimits': [
          {'from': 'a', 'kmh': 36},
        ],
        'gpsGaps': [
          if (gap) {'at': 'mid', 'durationS': 360},
        ],
      },
    );

    final withGap = buildTrace(
      synth(profile: profile(gap: true)).$1,
      synth().$2,
    );
    final without = buildTrace(
      synth(profile: profile(gap: false)).$1,
      synth().$2,
    );

    test('drops exactly the samples inside the gap', () {
      final gap = withGap.truth.gaps.single;
      expect(gap.toT - gap.fromT, 360);
      expect(
        withGap.sensor.observations.where((o) => gap.contains(o.t)),
        isEmpty,
      );
      expect(withGap.segments, hasLength(2));
      expect('<trkseg>'.allMatches(withGap.gpxText), hasLength(2));
      expect(
        withGap.sensor.observations.length,
        without.sensor.observations.length - 72,
      );
    });

    test('keeps the noise of every other sample', () {
      final byT = {for (final o in without.sensor.observations) o.t: o};
      for (final o in withGap.sensor.observations) {
        final ref = byT[o.t]!;
        expect(o.pos.lat, ref.pos.lat);
        expect(o.pos.lng, ref.pos.lng);
        expect(o.accM, ref.accM);
        expect(o.speedMps, ref.speedMps);
      }
    });
  });

  group('scripted outliers (TC13)', () {
    Map<String, Object?> profile({required bool scripted}) => synthProfileJson(
      overrides: {
        'endDwellS': 10,
        'scriptedOutliers': [
          if (scripted) ...[
            {
              'atRemainingM': 4000,
              'count': 3,
              'distanceToDestinationM': 600,
              'accM': 25,
            },
            {
              'atRemainingM': 400,
              'count': 2,
              'distanceToDestinationM': 1800,
              'accM': 30,
            },
          ],
        ],
      },
    );

    final route = synth().$2;
    final trace = buildTrace(synth(profile: profile(scripted: true)).$1, route);
    final plain = buildTrace(
      synth(profile: profile(scripted: false)).$1,
      route,
    );
    final dest = synthPoint(10000);

    test('replaces 3 then 2 consecutive samples', () {
      final records = trace.sensor.outliers;
      expect(records, hasLength(5));
      expect(records.every((r) => r.kind == OutlierKind.scripted), isTrue);
      final ts = [for (final r in records) r.t];
      expect(ts[1] - ts[0], 5);
      expect(ts[2] - ts[1], 5);
      expect(ts[4] - ts[3], 5);

      final truth = trace.truth;
      final first = truth.states.indexWhere(
        (s) => truth.destinationRouteM - s.s <= 4000,
      );
      expect(ts[0], truth.states[first].t);

      final byT = {for (final o in trace.sensor.observations) o.t: o};
      for (var i = 0; i < 5; i++) {
        final o = byT[ts[i]]!;
        expect(distanceM(o.pos, dest), closeTo(i < 3 ? 600 : 1800, 1));
        expect(o.accM, i < 3 ? 25.0 : 30.0);
      }
    });

    test('leaves the other samples unchanged', () {
      final scriptedTs = {for (final r in trace.sensor.outliers) r.t};
      final byT = {for (final o in plain.sensor.observations) o.t: o};
      for (final o in trace.sensor.observations) {
        if (scriptedTs.contains(o.t)) {
          continue;
        }
        expect(o.pos.lat, byT[o.t]!.pos.lat);
        expect(o.pos.lng, byT[o.t]!.pos.lng);
      }
    });
  });
}
