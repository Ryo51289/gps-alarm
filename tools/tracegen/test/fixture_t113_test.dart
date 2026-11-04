// T11.3 (tester): TR40 fixture `coach_gb_caugie_gappass` (T10.5 round 3 §8,
// round 3b window): long GPS gap (>= 15 min), slow EMA before it and a fast
// vehicle inside it (>= 1.8x), destination passed inside the gap, GPS back
// >= 3.5 km after the destination with regular fixes; expectations resolved
// from the fixture truth. Preconditions are checked on the generator truth and
// on the GPX samples (the chord the engine sees), not on hand numbers.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

typedef _J = Map<String, Object?>;

const _id = 'coach_gb_caugie_gappass';

/// Engine defaults the preconditions guard against (T10 §5, T10.6 §5).
const _gpsLostAlarmEtaS = 1200;
const _etaStopPenaltyS = 20;
const _gpsLostLongS = 1800;
const _overshootOpenM = 1000;
const _nearRadiusM = 1000;

GeneratedTrace _build() {
  final (profile, route) = ProfileRepository(dataDir).load(_id);
  return buildTrace(profile, route);
}

_J _fixture() =>
    jsonDecode(File('${fixturesDir.path}/$_id.expect.json').readAsStringSync())
        as _J;

void main() {
  final t = _build();
  final truth = t.truth;
  final gap = truth.gaps.single;
  final interval = t.profile.sampleIntervalS;
  int idx(int time) => truth.states.indexWhere((s) => s.t == time);
  double straightAt(int time) => truth.straightM[idx(time)];

  group('T11.3 TR40 preconditions (truth)', () {
    test('one gap of 15 to 30 min (>= 900 s, < gpsLostLongS: W off)', () {
      final len = gap.toT - gap.fromT;
      expect(len, greaterThanOrEqualTo(900));
      expect(len, lessThan(_gpsLostLongS));
      expect(t.segments, hasLength(2));
      expect(t.sensor.outliers, isEmpty);
    });

    test('the destination is passed inside the gap', () {
      expect(truth.arrivalT, greaterThan(gap.fromT));
      expect(truth.arrivalT, lessThan(gap.toT));
      // Passed, not just reached: closest point (overshoot truth) is in the
      // gap too, and the route goes on >= 3.5 km after the destination.
      final ov = truth.overshoot!;
      expect(ov.closestT, inExclusiveRange(gap.fromT, gap.toT));
      expect(truth.routeLengthM - truth.destinationRouteM, greaterThan(3500));
    });

    test('GPS returns >= 3.5 km past the destination, then regular fixes', () {
      final s0 = truth.states[idx(gap.toT)];
      expect(s0.s - truth.destinationRouteM, greaterThanOrEqualTo(3500));
      expect(straightAt(gap.toT), greaterThanOrEqualTo(3500));
      // Regular 5 s fixes for at least 2 min after the gap.
      final after = t.segments.last;
      expect(after.first.t, gap.toT);
      for (var j = 1; j < after.length; j++) {
        expect(after[j].t - after[j - 1].t, interval);
      }
      expect(after.last.t - gap.toT, greaterThanOrEqualTo(120));
    });

    test('vehicle inside the gap >= 1.8x the speed before it', () {
      // EMA proxy: mean ground speed over the 300 s (speedEmaTauS) before.
      final from = gap.fromT - 300;
      final before =
          (truth.states[idx(gap.fromT - interval)].s -
              truth.states[idx(from)].s) /
          (gap.fromT - interval - from);
      final inside =
          (truth.states[idx(gap.toT)].s - truth.states[idx(gap.fromT)].s) /
          (gap.toT - gap.fromT);
      printOnFailure(
        'before ${before.toStringAsFixed(2)} m/s, '
        'inside ${inside.toStringAsFixed(2)} m/s',
      );
      expect(inside, greaterThanOrEqualTo(1.8 * before));
    });

    test(
      'dead reckoning at the slow speed is still >= 20 min out at g.end',
      () {
        // Closing speed before the gap (straight-line distance rate over the
        // last 300 s), then DR from the last fix to g.end (T10 §4.4/§4.5
        // simplified: k = 1, constant cvDr). The engine must not ring
        // GPS_LOST before the GPS returns, or TR40 tests nothing.
        final last = gap.fromT - interval;
        final cv = (straightAt(last - 300) - straightAt(last)) / 300;
        final etaAtEnd =
            straightAt(last) / cv - (gap.toT - last) + _etaStopPenaltyS;
        printOnFailure(
          'cvDr ${cv.toStringAsFixed(2)} m/s, '
          'DR ETA at g.end ${etaAtEnd.toStringAsFixed(0)} s',
        );
        expect(etaAtEnd, greaterThan(_gpsLostAlarmEtaS + 120));
      },
    );
  });

  group('T11.3 TR40 chord on the GPX samples (T10.5 round 3 §4.11)', () {
    final obs = t.sensor.observations;
    final l = obs.lastWhere((o) => o.t < gap.fromT);
    final f = obs.firstWhere((o) => o.t >= gap.toT);
    final dest = truth.destination;
    final (ax, ay) = localEnM(dest, l.pos);
    final (fx, fy) = localEnM(dest, f.pos);
    final ex = fx - ax;
    final ey = fy - ay;
    final u = -(ax * ex + ay * ey) / (ex * ex + ey * ey);
    final px = ax + u * ex;
    final py = ay + u * ey;
    final dChord = sqrt(px * px + py * py);
    final dF = sqrt(fx * fx + fy * fy);

    test('0 < u < 1 and dChord < nearRadius (1 km)', () {
      printOnFailure('u $u dChord $dChord dF $dF');
      expect(u, inExclusiveRange(0, 1));
      expect(dChord, lessThan(_nearRadiusM));
    });

    test('first fix after the gap is >= overshootOpenM past the chord', () {
      expect(dF - dChord, greaterThanOrEqualTo(_overshootOpenM));
      // Beyond the PASSED_CLOSEST radius too (3 km), i.e. the T12.1 engine
      // had nothing but TIMEOUT left (test report T12.2 #1).
      expect(dF, greaterThan(3000));
    });
  });

  group('T11.3 TR40 fixture expectations', () {
    final j = _fixture();
    final cases = (j['cases']! as List).cast<_J>();
    final g =
        (((j['truth']! as _J)['gpsGaps']! as List).single as _J)['toT']! as int;

    test('trace truth matches the generator', () {
      expect(g, gap.toT);
      expect((j['truth']! as _J)['arrivalT'], truth.arrivalT);
    });

    for (final (caseId, mode, reason) in [
      ('distance_1000', 'distance', 'OVERSHOOT'),
      ('time_15', 'time', 'TIME'),
      ('smart', 'smart', 'OVERSHOOT'),
    ]) {
      test('$caseId: [g.end, g.end + 25] for alarm, $reason, overshoot', () {
        final c = cases.singleWhere((c) => c['id'] == caseId);
        expect(c['status'], 'final');
        expect(c['testIds'], ['TR40']);
        final cfg = c['config']! as _J;
        expect(cfg['mode'], mode);
        expect(cfg['preAlert'], isFalse);
        expect(cfg.containsKey('kill'), isFalse);
        final ex = (c['expect']! as List).cast<_J>();
        List<Object?> w(String event, [String? r]) {
          final e = ex.singleWhere(
            (e) => e['event'] == event && e['reason'] == r,
          );
          return [e['notBefore'], e['notAfter']];
        }

        expect(w('gpsRecovered'), [g, g]);
        expect(w('alarm'), [g, g + 25]);
        expect(w('alarm', reason), [g, g + 25]);
        expect(ex.singleWhere((e) => e['reason'] == reason)['ringNow'], isTrue);
        expect(w('overshoot'), [g, g + 25]);
        expect(c['forbidMatch'], [
          {'event': 'alarm', 'reason': 'TIMEOUT'},
        ]);
      });
    }

    test('summary_unknown (TR27) as in every profile', () {
      final c = cases.singleWhere((c) => c['id'] == 'summary_unknown');
      expect(c['testIds'], ['TR27']);
      expect((c['expectSummary']! as _J)['vehicleGuess'], 'UNKNOWN');
    });
  });
}
