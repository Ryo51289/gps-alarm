// Case keys of T11 §2 and the cross checks of §5.2 (TG01–TG11), plus the
// T11.1 keys `policyPhaseSweep` and `killSweep` (TG39, TG41).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const String _file = 'profiles/synth.json';

/// A minimal valid case; [config] replaces the whole config object.
Map<String, Object?> caseJson({
  Map<String, Object?>? config,
  List<Object?> expect = const [],
  List<Object?> forbid = const [],
  Map<String, Object?> extra = const {},
}) => {
  'id': 'c',
  'config':
      config ?? {'mode': 'distance', 'thresholdM': 1000, 'preAlert': true},
  'expect': expect,
  'forbid': forbid,
  ...extra,
};

Map<String, Object?> d1000([Map<String, Object?> more = const {}]) => {
  'mode': 'distance',
  'thresholdM': 1000,
  'preAlert': true,
  ...more,
};

Map<String, Object?> edge(String anchor, [int offset = 0]) => {
  'anchor': anchor,
  'offsetS': offset,
};

Map<String, Object?> expectItem(
  String event, {
  Map<String, Object?> filters = const {},
  String nb = 'route<=1300',
  String na = 'route<=700',
}) => {
  'event': event,
  ...filters,
  'notBefore': {'anchor': nb},
  'notAfter': {'anchor': na},
  'ref': 'test',
};

Map<String, Object?> afterItem(
  String event,
  Map<String, Object?> after, {
  Map<String, Object?> filters = const {},
  List<int> within = const [0, 0],
}) => {
  'event': event,
  ...filters,
  'after': after,
  'withinS': within,
  'ref': 'test',
};

/// Profile with one case on the synthetic route; [overrides] replace
/// top-level profile keys.
Map<String, Object?> profileWith(
  Map<String, Object?> c, {
  Map<String, Object?> overrides = const {},
}) => synthProfileJson(
  overrides: {
    'endDwellS': 30,
    'cases': [c],
    ...overrides,
  },
);

/// Parses (and with [build] also generates) the profile; returns the error.
ProfileException? errorOf(
  Map<String, Object?> c, {
  Map<String, Object?> overrides = const {},
  bool build = false,
}) {
  try {
    final (p, r) = synth(profile: profileWith(c, overrides: overrides));
    if (build) {
      buildTrace(p, r);
    }
    return null;
  } on ProfileException catch (e) {
    return e;
  }
}

void expectError(
  Map<String, Object?> c,
  String field, {
  Pattern? message,
  Map<String, Object?> overrides = const {},
  bool build = false,
}) {
  final e = errorOf(c, overrides: overrides, build: build);
  expect(e, isNotNull, reason: 'expected an error at $field');
  expect(e!.path, '$_file: cases[0].$field', reason: e.toString());
  if (message != null) {
    expect(e.message, contains(message));
  }
}

void expectOk(
  Map<String, Object?> c, {
  Map<String, Object?> overrides = const {},
  bool build = true,
}) {
  final e = errorOf(c, overrides: overrides, build: build);
  expect(e, isNull, reason: e.toString());
}

void main() {
  test('TG01 smart mode takes no threshold', () {
    expectOk(caseJson(config: {'mode': 'smart'}));
    expectError(
      caseJson(config: {'mode': 'smart', 'thresholdM': 1000}),
      'config.thresholdM',
      message: 'not allowed in smart mode',
    );
  });

  test('TG02 threshold ranges', () {
    for (final (value, ok) in [
      (199, false),
      (200, true),
      (10000, true),
      (10001, false),
    ]) {
      final c = caseJson(config: {'mode': 'distance', 'thresholdM': value});
      ok ? expectOk(c, build: false) : expectError(c, 'config.thresholdM');
    }
    for (final (value, ok) in [
      (4, false),
      (5, true),
      (60, true),
      (61, false),
    ]) {
      final c = caseJson(config: {'mode': 'time', 'thresholdMin': value});
      ok ? expectOk(c, build: false) : expectError(c, 'config.thresholdMin');
    }
  });

  test('TG03 vehicleHint', () {
    expectOk(caseJson(config: d1000({'vehicleHint': 'unknown'})));
    expectError(
      caseJson(config: d1000({'vehicleHint': 'plane'})),
      'config.vehicleHint',
    );
  });

  test('TG04 params: names, types, decimals, ASCII order', () {
    expectError(
      caseJson(
        config: d1000({
          'params': {'foo': 1},
        }),
      ),
      'config.params.foo',
      message: 'unknown engine parameter',
    );
    expectError(
      caseJson(
        config: d1000({
          'params': {'smartTargetS': 300.5},
        }),
      ),
      'config.params.smartTargetS',
      message: 'JSON integer',
    );
    expectError(
      caseJson(
        config: d1000({
          'params': {'routeFactorPrior': 1.23456},
        }),
      ),
      'config.params.routeFactorPrior',
      message: '4 decimals',
    );
    final (p, r) = synth(
      profile: profileWith(
        caseJson(
          config: d1000({
            'params': {'smartTargetS': 300, 'routeFactorPrior': 1.25},
          }),
        ),
      ),
    );
    final text = buildTrace(p, r).expectText;
    expect(text, contains('"routeFactorPrior": 1.2500'));
    expect(text, contains('"smartTargetS": 300'));
    final params =
        (((jsonDecode(text) as Map)['cases'] as List).single as Map)['config']
            as Map;
    expect((params['params'] as Map).keys, [
      'routeFactorPrior',
      'smartTargetS',
    ]);
  });

  test('TG05 battery track', () {
    Map<String, Object?> b(int t, int level, {bool? charging = false}) => {
      't': t,
      'levelPct': level,
      'charging': ?charging,
    };
    expectError(
      caseJson(
        config: d1000({
          'battery': [b(7, 50)],
        }),
      ),
      'config.battery[0].t',
    );
    expectError(
      caseJson(
        config: d1000({
          'battery': [b(0, 50), b(0, 49)],
        }),
      ),
      'config.battery[1].t',
    );
    expectError(
      caseJson(
        config: d1000({
          'battery': [b(0, 101)],
        }),
      ),
      'config.battery[0].levelPct',
    );
    expectError(
      caseJson(
        config: d1000({
          'battery': [b(0, 50, charging: null)],
        }),
      ),
      'config.battery[0].charging',
    );
    expectOk(
      caseJson(
        config: d1000({
          'battery': [b(0, 50), b(60, 49)],
        }),
      ),
    );
  });

  test('TG06 actions', () {
    Map<String, Object?> action(Map<String, Object?> at, [String a = 'stop']) =>
        d1000({
          'kill': {'t': 300},
          'actions': [
            {'at': at, 'action': a},
          ],
        });
    expectError(
      caseJson(config: action({'t': 0}, 'jump')),
      'config.actions[0].action',
    );
    expectError(
      caseJson(config: action(edge('event:foo'))),
      'config.actions[0].at.anchor',
      message: 'unknown event',
    );
    expectError(
      caseJson(config: action(edge('osFallbackFired'))),
      'config.actions[0].at.anchor',
      message: 'not allowed in config.actions',
    );
    expectError(
      caseJson(config: action(edge('end', 5))),
      'config.actions[0].at',
      message: 'outside [0, durationS',
      build: true,
    );
    expectOk(caseJson(config: action(edge('event:alarm', 20), 'snooze')));
  });

  test('TG07 kill, relaunch, osDismiss', () {
    expectError(
      caseJson(
        config: d1000({
          'relaunch': {
            'at': {'t': 100},
            'fallbackStatus': 'PENDING',
          },
        }),
      ),
      'config.relaunch',
      message: 'needs config.kill',
    );
    expectError(
      caseJson(
        config: d1000({
          'kill': {'t': 100},
          'relaunch': {
            'at': {'t': 100},
            'fallbackStatus': 'PENDING',
          },
        }),
      ),
      'config.relaunch.at',
    );
    expectError(
      caseJson(
        config: d1000({
          'kill': edge('arrival', -100),
          'relaunch': {'at': edge('arrival', -200), 'fallbackStatus': 'RANG'},
        }),
      ),
      'config.relaunch.at',
      message: 'not after config.kill',
      build: true,
    );
    expectError(
      caseJson(
        config: d1000({
          'kill': {'t': 100},
          'relaunch': {
            'at': edge('osFallbackFired', 30),
            'fallbackStatus': 'RANG',
          },
          'osDismiss': {'offsetS': 20},
        }),
      ),
      'config.osDismiss',
    );
    expectError(
      caseJson(config: d1000({'kill': edge('event:alarm')})),
      'config.kill.anchor',
    );
    expectOk(
      caseJson(
        config: d1000({
          'kill': edge('arrival', -200),
          'relaunch': {
            'at': edge('osFallbackFired', 30),
            'fallbackStatus': 'auto',
          },
          'osDismiss': {'offsetS': 20},
          'osRingMaxS': 60,
        }),
      ),
    );
  });

  test('TG08 event filters', () {
    expectError(
      caseJson(
        expect: [
          expectItem('gpsLost', filters: {'reason': 'DISTANCE'}),
        ],
      ),
      'expect[0].reason',
    );
    expectError(
      caseJson(
        expect: [
          expectItem('alarm', filters: {'reason': 'NEAR'}),
        ],
      ),
      'expect[0].reason',
    );
    expectOk(
      caseJson(
        expect: [
          expectItem('fallbackAlarmChanged', filters: {'cause': 'SUPERSEDED'}),
        ],
      ),
    );
    expectError(
      caseJson(
        expect: [
          expectItem('preAlert', filters: {'ringNow': true}),
        ],
      ),
      'expect[0].ringNow',
    );
  });

  test('TG09 consistency of expect / forbid', () {
    final alarm = expectItem('alarm');
    final distance = expectItem('alarm', filters: {'reason': 'DISTANCE'});
    // (a) unfiltered + filtered entries of the same event.
    expectOk(caseJson(expect: [alarm, distance]));
    // (b) the same filters twice.
    expectError(caseJson(expect: [distance, distance]), 'expect[1]');
    // (c) forbid an expected event.
    expectError(
      caseJson(
        expect: [
          expectItem('alarm', filters: {'reason': 'TIME'}),
        ],
        forbid: ['alarm'],
      ),
      'forbid[0]',
    );
    // (d) forbidMatch with another reason.
    expectOk(
      caseJson(
        expect: [distance],
        extra: {
          'forbidMatch': [
            {'event': 'alarm', 'reason': 'OVERSHOOT'},
          ],
        },
      ),
    );
    // (e) unfiltered forbidMatch.
    expectError(
      caseJson(
        expect: [distance],
        extra: {
          'forbidMatch': [
            {'event': 'alarm'},
          ],
        },
      ),
      'forbidMatch[0]',
    );
    // (f) forbidAfter overlapping an expectAfter (0 + 0 > -5).
    final killed = d1000({
      'kill': {'t': 100},
      'relaunch': {'at': edge('osFallbackFired', 30), 'fallbackStatus': 'auto'},
    });
    expectError(
      caseJson(
        config: killed,
        extra: {
          'expectAfter': [
            afterItem('alarm', edge('relaunch'), filters: {'ringNow': true}),
          ],
          'forbidAfter': [
            {'event': 'alarm', 'ringNow': true, 'after': edge('relaunch', -5)},
          ],
        },
      ),
      'forbidAfter[0]',
    );
    // TR23 shape: different ringNow, no conflict.
    expectOk(
      caseJson(
        config: killed,
        extra: {
          'expectAfter': [
            afterItem(
              'alarm',
              edge('relaunch'),
              filters: {'reason': 'FALLBACK', 'ringNow': false},
            ),
          ],
          'forbidAfter': [
            {'event': 'alarm', 'ringNow': true, 'after': edge('relaunch', -5)},
          ],
        },
      ),
    );
  });

  test('final cases need testIds', () {
    expectError(caseJson(extra: {'status': 'final'}), 'testIds');
    expectError(
      caseJson(
        extra: {
          'status': 'final',
          'testIds': ['T22'],
        },
      ),
      'testIds[0]',
    );
    expectOk(
      caseJson(
        extra: {
          'status': 'final',
          'testIds': ['TR22'],
        },
      ),
    );
  });

  test('TG10(e) expectFallback rejects formula params', () {
    expectError(
      caseJson(
        config: d1000({
          'kill': {'t': 100},
          'params': {'fallbackLagS': 40},
        }),
        extra: {
          'expectFallback': {
            'modeAt': edge('straight<=1000'),
            'toleranceS': [-300, 120],
            'ref': 'test',
          },
        },
      ),
      'expectFallback',
      message: 'fallbackLagS',
    );
    // T11.1 V11: the 12 parameters of the formula.
    expect(kFallbackFormulaParams, hasLength(12));
    for (final name in kFallbackFormulaParams) {
      final value = kDoubleParams.contains(name) ? 1.5 : 40;
      expectError(
        caseJson(
          config: d1000({
            'kill': {'t': 100},
            'params': {name: value},
          }),
          extra: {
            'expectFallback': {
              'modeAt': edge('straight<=1000'),
              'toleranceS': [-300, 120],
              'ref': 'test',
            },
          },
        ),
        'expectFallback',
        message: 'cannot be computed when params override $name',
      );
    }
  });

  test('TG11 anchors: new kinds and where they may be used', () {
    final offroute = {'destinationOffsetM': 300};
    final killed = d1000({
      'kill': {'t': 100},
      'relaunch': {'at': edge('osFallbackFired', 30), 'fallbackStatus': 'auto'},
    });
    for (final anchor in [
      'closest',
      'closest.departT',
      'kill',
      'event:alarm',
      'relaunch',
      'osFallbackFired',
    ]) {
      expectOk(
        caseJson(
          config: killed,
          extra: {
            'expectAfter': [afterItem('tripEnded', edge(anchor))],
          },
        ),
        overrides: offroute,
        build: false,
      );
    }
    expect(
      () => Anchor.parse('event:alarmX'),
      throwsA(
        isA<AnchorException>().having(
          (e) => e.message,
          'message',
          contains('unknown event'),
        ),
      ),
    );
    expectError(
      caseJson(expect: [expectItem('alarm', nb: 'event:preAlert')]),
      'expect[0].notBefore.anchor',
      message: 'run-time anchor',
    );
    expectError(
      caseJson(
        extra: {
          'expectAfter': [afterItem('tripEnded', edge('kill'))],
        },
      ),
      'expectAfter[0].after.anchor',
      message: 'needs config.kill',
    );
    expectError(
      caseJson(expect: [expectItem('alarm', nb: 'closest')]),
      'expect[0].notBefore.anchor',
      message: 'destinationOffsetM',
    );
    expectError(
      caseJson(
        config: d1000({
          'params': {'passedClosestOpenMinM': 800},
        }),
        expect: [expectItem('alarm', nb: 'closest.departT')],
      ),
      'expect[0].notBefore.anchor',
      overrides: offroute,
    );
  });

  test('TG37 run anchors in inputs need offsetS >= sampleIntervalS', () {
    const message =
        'run anchor in an input requires offsetS >= '
        'sampleIntervalS (5)';
    Map<String, Object?> withAction(Map<String, Object?> at) => d1000({
      'kill': {'t': 100},
      'relaunch': {'at': edge('osFallbackFired', 30), 'fallbackStatus': 'auto'},
      'actions': [
        {'at': at, 'action': 'dismiss'},
      ],
    });
    Map<String, Object?> withRelaunch(Map<String, Object?> at) => d1000({
      'kill': {'t': 100},
      'relaunch': {'at': at, 'fallbackStatus': 'auto'},
    });

    // config.actions[].at: event:* and relaunch.
    for (final offset in [0, -5]) {
      expectError(
        caseJson(config: withAction(edge('event:alarm', offset))),
        'config.actions[0].at.offsetS',
        message: message,
      );
    }
    expectOk(
      caseJson(config: withAction(edge('event:alarm', 5))),
      build: false,
    );
    expectError(
      caseJson(config: withAction(edge('relaunch'))),
      'config.actions[0].at.offsetS',
      message: message,
    );
    // A run anchor without offsetS means offsetS 0.
    expectError(
      caseJson(config: withAction({'anchor': 'event:alarm'})),
      'config.actions[0].at.offsetS',
      message: message,
    );

    // config.relaunch.at: osFallbackFired and event:*.
    expectError(
      caseJson(config: withRelaunch(edge('osFallbackFired'))),
      'config.relaunch.at.offsetS',
      message: message,
    );
    expectOk(
      caseJson(config: withRelaunch(edge('osFallbackFired', 5))),
      build: false,
    );
    expectError(
      caseJson(config: withRelaunch(edge('event:preAlert'))),
      'config.relaunch.at.offsetS',
      message: message,
    );

    // Static anchors in inputs keep any offset.
    expectOk(
      caseJson(
        config: d1000({
          'actions': [
            {'at': edge('arrival', -5), 'action': 'stop'},
          ],
        }),
      ),
    );

    // Checks (expectAfter / forbidAfter) are not inputs.
    expectOk(
      caseJson(
        config: withRelaunch(edge('osFallbackFired', 30)),
        extra: {
          'expectAfter': [afterItem('tripEnded', edge('event:alarm'))],
          'forbidAfter': [
            {'event': 'preAlert', 'after': edge('relaunch', -5)},
          ],
        },
      ),
      build: false,
    );
  });

  test('TG39 policyPhaseSweep (T11.1 §3 V1-V4)', () {
    Map<String, Object?> sweep(
      Object? value, {
      Map<String, Object?>? config,
      Map<String, Object?> more = const {},
    }) => caseJson(config: config, extra: {'policyPhaseSweep': value, ...more});

    expectOk(sweep(true));
    expectOk(sweep(false));
    for (final bad in ['yes', 1]) {
      expectError(
        sweep(bad),
        'policyPhaseSweep',
        message: 'must be true or false',
      );
    }
    expectError(
      sweep(
        true,
        more: {
          'samplingModes': ['all'],
        },
      ),
      'policyPhaseSweep',
      message: 'policyPhaseSweep cannot be used with samplingModes ["all"]',
    );
    expectOk(
      sweep(
        true,
        more: {
          'samplingModes': ['policy'],
        },
      ),
    );
    expectError(
      sweep(
        true,
        config: d1000({
          'actions': [
            {'at': edge('start', 60), 'action': 'batteryMaxSaving'},
          ],
        }),
      ),
      'policyPhaseSweep',
      message: 'policyPhaseSweep cannot be used with action batteryMaxSaving',
    );
    expectError(
      sweep(
        true,
        config: d1000({
          'params': {'samplingSparseIntervalS': 182},
        }),
      ),
      'policyPhaseSweep',
      message:
          'policyPhaseSweep needs samplingSparseIntervalS (182) to be a '
          'multiple of sampleIntervalS (5)',
    );
    expectOk(
      sweep(
        true,
        config: d1000({
          'params': {'samplingSparseIntervalS': 180},
        }),
      ),
    );

    final (p, _) = synth(profile: profileWith(sweep(true)));
    expect(p.cases.single.policyPhaseSweep, isTrue);
    final (q, _) = synth(profile: profileWith(caseJson()));
    expect(q.cases.single.policyPhaseSweep, isFalse);
  });

  test('TG41 killSweep (T11.1 §3 V5-V10)', () {
    Map<String, Object?> ks([Map<String, Object?> more = const {}]) => {
      'from': {'t': 60},
      'everyS': 60,
      'notAfter': {'anchor': 'arrival'},
      'earlyFrom': {'anchor': 'straight<=1000'},
      ...more,
    };
    Map<String, Object?> withSweep(
      Map<String, Object?> sweep, {
      Map<String, Object?>? config,
    }) => caseJson(config: config, extra: {'killSweep': sweep});

    expectOk(withSweep(ks()));
    expectOk(withSweep(ks({'statsOnly': true})));
    expectOk(withSweep(ks({'statsOnly': false})));

    // V5: required keys.
    for (final key in ['from', 'everyS', 'notAfter', 'earlyFrom']) {
      expectError(
        withSweep(ks()..remove(key)),
        'killSweep.$key',
        message: 'missing required key',
      );
    }
    // V7: everyS.
    expectError(
      withSweep(ks({'everyS': 0})),
      'killSweep.everyS',
      message: 'must be > 0',
    );
    expectError(
      withSweep(ks({'everyS': -60})),
      'killSweep.everyS',
      message: 'must be > 0',
    );
    expectError(
      withSweep(ks({'everyS': 62})),
      'killSweep.everyS',
      message: 'must be a multiple of sampleIntervalS (5)',
    );
    expectError(
      withSweep(ks({'everyS': '60'})),
      'killSweep.everyS',
      message: 'must be an integer',
    );
    // V6: from.t >= I; the multiple check comes first.
    expectError(
      withSweep(
        ks({
          'from': {'t': 0},
        }),
      ),
      'killSweep.from.t',
      message: 'must be >= sampleIntervalS (5)',
    );
    expectError(
      withSweep(
        ks({
          'from': {'t': 3},
        }),
      ),
      'killSweep.from.t',
      message: 'must be a multiple of sampleIntervalS (5)',
    );
    expectOk(
      withSweep(
        ks({
          'from': {'t': 5},
        }),
      ),
    );
    // V6 for an anchored from: checked after resolving.
    expectOk(withSweep(ks({'from': edge('start')})), build: false);
    expectError(
      withSweep(ks({'from': edge('start')})),
      'killSweep.from',
      message: 'must be >= sampleIntervalS (5)',
      build: true,
    );
    // V9: run anchors and kill.
    expectError(
      withSweep(
        ks({
          'notAfter': {'anchor': 'event:alarm'},
        }),
      ),
      'killSweep.notAfter.anchor',
      message: 'anchor "event:alarm" is not allowed in killSweep',
    );
    expectError(
      withSweep(
        ks({
          'earlyFrom': {'anchor': 'kill'},
        }),
      ),
      'killSweep.earlyFrom.anchor',
      message: 'anchor "kill" is not allowed in killSweep',
    );
    // V8: statsOnly.
    expectError(
      withSweep(ks({'statsOnly': 'true'})),
      'killSweep.statsOnly',
      message: 'must be true or false',
    );
    // Must-understand inside killSweep and its At objects.
    expectError(
      withSweep(ks({'foo': 1})),
      'killSweep.foo',
      message: 'unknown key',
    );
    expectError(
      withSweep(
        ks({
          'from': {'t': 60, 'foo': 1},
        }),
      ),
      'killSweep.from.foo',
      message: 'unknown key',
    );
    // V10: not with kill, relaunch, osDismiss, osSim false.
    expectError(
      withSweep(
        ks(),
        config: d1000({
          'kill': {'t': 100},
        }),
      ),
      'killSweep',
      message: 'killSweep cannot be used with config.kill',
    );
    expectError(
      withSweep(
        ks(),
        config: d1000({
          'kill': {'t': 100},
          'relaunch': {
            'at': edge('osFallbackFired', 30),
            'fallbackStatus': 'auto',
          },
        }),
      ),
      'killSweep',
      message: 'killSweep cannot be used with config.',
    );
    expectError(
      withSweep(ks(), config: d1000({'osSim': false})),
      'killSweep',
      message: 'killSweep cannot be used with config.osSim false',
    );
    expectOk(withSweep(ks(), config: d1000({'osSim': true})));
    // A reference error shows up when generating.
    expectError(
      withSweep(
        ks({
          'notAfter': {'anchor': 'overshoot'},
        }),
      ),
      'killSweep.notAfter.anchor',
      message: 'trace has no overshoot',
      build: true,
    );

    final (p, _) = synth(profile: profileWith(withSweep(ks())));
    final sweep = p.cases.single.killSweep!;
    expect(sweep.from.t, 60);
    expect(sweep.everyS, 60);
    expect(sweep.notAfter.anchor?.text, 'arrival');
    expect(sweep.earlyFrom.anchor?.text, 'straight<=1000');
    expect(sweep.statsOnly, isFalse);
  });

  test('V13 overshoot anchors are checked when the truth is known', () {
    final anchor = Anchor.parse('overshoot');
    String? check({bool? hasOvershoot}) => anchorReferenceError(
      anchor,
      hasKill: false,
      hasRelaunch: false,
      hasClosest: false,
      paramNames: const [],
      hasOvershoot: hasOvershoot,
    );
    expect(check(), isNull);
    expect(check(hasOvershoot: true), isNull);
    expect(
      check(hasOvershoot: false),
      'anchor "overshoot" needs truth.overshoot',
    );
  });
}
