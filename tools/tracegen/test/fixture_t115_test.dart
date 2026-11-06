// T11.5: TR44 case `distance_1000_overshoot_ringing` on
// `coach_gb_phuly_overshoot` (T10 "T10.8" §3). The case only makes sense when
// the first alarm still rings at the overshoot and the second ring (first
// ring + osRingMaxS) cannot reach the end of the trace's alarmMaxActiveS
// window; both are checked on the fixture numbers, not on hand values.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

typedef _J = Map<String, Object?>;

const _id = 'coach_gb_phuly_overshoot';
const _caseId = 'distance_1000_overshoot_ringing';

/// `alarmMaxActiveS` default (T10 §5, §4.13).
const _alarmMaxActiveS = 3600;

void main() {
  final j = jsonDecode(
    File('${fixturesDir.path}/$_id.expect.json').readAsStringSync(),
  ) as _J;
  final trace = j['trace']! as _J;
  final cases = (j['cases']! as List).cast<_J>();
  final c = cases.singleWhere((c) => c['id'] == _caseId);
  final cfg = c['config']! as _J;
  final ex = (c['expect']! as List).cast<_J>();
  _J expectOf(String event) => ex.singleWhere((e) => e['event'] == event);
  final after = (c['expectAfter']! as List).cast<_J>().single;
  final ringMax = cfg['osRingMaxS']! as int;

  group('T11.5 TR44 fixture', () {
    test('final, TR44, DISTANCE 1000, osRingMaxS 600, phase-swept', () {
      expect(c['status'], 'final');
      expect(c['testIds'], ['TR44']);
      expect(cfg['mode'], 'distance');
      expect(cfg['thresholdM'], 1000);
      expect(cfg.containsKey('actions'), isFalse);
      expect(cfg.containsKey('kill'), isFalse);
      expect(ringMax, 600);
      expect(c['policyPhaseSweep'], isTrue);
    });

    test('first alarm still rings at the latest overshoot tick', () {
      final ring1Earliest = expectOf('alarm')['notBefore']! as int;
      final overshootLatest = expectOf('overshoot')['notAfter']! as int;
      expect(ring1Earliest + ringMax, greaterThan(overshootLatest));
    });

    test(
      'OVERSHOOT rings in [ring1 + osRingMaxS, ring1 + osRingMaxS + 10]',
      () {
        expect(after['event'], 'alarm');
        expect(after['reason'], 'OVERSHOOT');
        expect(after['ringNow'], isTrue);
        expect(after['after'], {'anchor': 'event:alarm', 'offsetS': 0});
        expect(after['withinS'], [ringMax, ringMax + 10]);
      },
    );

    test(
      'forbid tripEnded covers "no ALARM_UNANSWERED before ring2 + 1 h"',
      () {
        final ring2Earliest =
            (expectOf('alarm')['notBefore']! as int) + ringMax;
        expect(
          trace['durationS']! as int,
          lessThan(ring2Earliest + _alarmMaxActiveS),
        );
        expect(c['forbid'], containsAll(<String>['gpsLost', 'tripEnded']));
      },
    );
  });
}
