// T11 TG31 (tester): every T10 trace test TR01–TR35 maps to fixture cases
// exactly as T11 §5.4/§5.5 prescribes; T11.1 adds the seven TR37 cases
// (T11.1 §5.8) and `policyPhaseSweep` (TR30, stopgap TR27).
//
// The golden table below was written by hand from the spec tables (not
// copied from the generator output). Each case is reduced to a signature at
// the anchor level (mode, inputs, filters, window anchors, forbids), so a
// case that drifts from its §5.4 row (wrong anchor, missing filter, dropped
// forbid, wrong action) fails here even when `check`/`validate` are green.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

String _at(Map<String, Object?> p) {
  final anchor = p['anchor'] as String?;
  if (anchor == null) {
    return 't=${p['t']}';
  }
  final off = p['offsetS']! as int;
  return off == 0 ? anchor : '$anchor${off > 0 ? '+' : ''}$off';
}

String _battery(Map<String, Object?> b) =>
    '${b['t']}:${b['levelPct']}${b['charging'] == true ? 'c' : ''}';

String _action(Map<String, Object?> a) =>
    '${a['action']}@${_at(a['at']! as Map<String, Object?>)}';

String _relaunch(Map<String, Object?> r) =>
    'relaunch@${_at(r['at']! as Map<String, Object?>)}:${r['fallbackStatus']}';

String _filter(Map<String, Object?> e) => [
  e['event'],
  if (e.containsKey('reason')) e['reason'],
  if (e.containsKey('ringNow')) 'ringNow=${e['ringNow']}',
  if (e.containsKey('cause')) e['cause'],
].join('/');

/// Anchor-level signature of one fixture case.
List<String> signature(Map<String, Object?> c) {
  final cfg = c['config']! as Map<String, Object?>;
  final head = <String>[
    switch (cfg['mode']) {
      'distance' => 'D${cfg['thresholdM']}',
      'time' => 'T${cfg['thresholdMin']}',
      'smart' => 'S',
      final m => 'mode=$m',
    },
    if (cfg['preAlert'] == true) 'pa' else 'nopa',
    if (cfg.containsKey('vehicleHint')) 'hint=${cfg['vehicleHint']}',
    if (cfg['params'] case final Map<String, Object?> p)
      'params{${[for (final e in p.entries) '${e.key}=${e.value}'].join(',')}}',
    if (cfg['battery'] case final List<Object?> b)
      'battery[${b.cast<Map<String, Object?>>().map(_battery).join(',')}]',
    if (cfg['actions'] case final List<Object?> a)
      'actions[${a.cast<Map<String, Object?>>().map(_action).join(',')}]',
    if (cfg.containsKey('kill'))
      'kill@${_at(cfg['kill']! as Map<String, Object?>)}',
    if (cfg['relaunch'] case final Map<String, Object?> r) _relaunch(r),
    if (cfg.containsKey('osDismiss'))
      'osDismiss=${(cfg['osDismiss']! as Map)['offsetS']}',
    if (cfg.containsKey('osSim')) 'osSim=${cfg['osSim']}',
    if (cfg.containsKey('osRingMaxS')) 'osRingMaxS=${cfg['osRingMaxS']}',
  ];
  final out = <String>[head.join(' ')];
  if (c.containsKey('samplingModes')) {
    out.add('modes=${(c['samplingModes']! as List).join(',')}');
  }
  if (c.containsKey('policyPhaseSweep')) {
    out.add('sweep=${c['policyPhaseSweep']}');
  }
  for (final e in (c['expect']! as List).cast<Map<String, Object?>>()) {
    final w = e['window']! as Map<String, Object?>;
    out.add(
      'E ${_filter(e)} [${_at(w['notBefore']! as Map<String, Object?>)},'
      '${_at(w['notAfter']! as Map<String, Object?>)}]',
    );
  }
  for (final e
      in (c['expectAfter'] as List? ?? const []).cast<Map<String, Object?>>()) {
    final within = (e['withinS']! as List).join(',');
    out.add(
      'A ${_filter(e)} >${_at(e['after']! as Map<String, Object?>)} [$within]',
    );
  }
  final f = c['expectFallback'] as Map<String, Object?>?;
  if (f != null) {
    final w = f['window']! as Map<String, Object?>;
    out.add(
      'F ${_at(w['modeAt']! as Map<String, Object?>)} '
      'tol[${(w['toleranceS']! as List).join(',')}]',
    );
  }
  final k = c['killSweep'] as Map<String, Object?>?;
  if (k != null) {
    out.add(
      [
        'K ${_at(k['from']! as Map<String, Object?>)}',
        'every=${k['everyS']}',
        'notAfter=${_at(k['notAfter']! as Map<String, Object?>)}',
        'early=${_at(k['earlyFrom']! as Map<String, Object?>)}',
        if (k.containsKey('statsOnly')) 'statsOnly=${k['statsOnly']}',
      ].join(' '),
    );
  }
  if (c.containsKey('expectOutcome')) {
    out.add('O ${c['expectOutcome']}');
  }
  if (c.containsKey('expectSummary')) {
    out.add('Σ ${(c['expectSummary']! as Map)['vehicleGuess']}');
  }
  final forbid = (c['forbid']! as List).cast<String>();
  if (forbid.isNotEmpty) {
    out.add('! ${([...forbid]..sort()).join(',')}');
  }
  for (final e
      in (c['forbidMatch'] as List? ?? const []).cast<Map<String, Object?>>()) {
    out.add('!m ${_filter(e)}');
  }
  for (final e
      in (c['forbidAfter'] as List? ?? const []).cast<Map<String, Object?>>()) {
    out.add('!a ${_filter(e)} >${_at(e['after']! as Map<String, Object?>)}');
  }
  return out;
}

/// T11 §5.5: `summary_unknown`, present in every profile; [sweep] = T11.1
/// `policyPhaseSweep: true` (stopgap only).
List<String> summary(String guess, {bool sweep = false}) => [
  'D1000 nopa hint=unknown actions[stop@end]',
  if (sweep) 'sweep=true',
  'E tripEnded [end,end]',
  'Σ $guess',
];

/// T11.1 §5.7/§5.8: a TR37 `killSweep` case.
List<String> killSweepCase({
  bool time = false,
  bool sweep = false,
  bool statsOnly = false,
}) => [
  if (time) 'T15 pa' else 'D1000 pa',
  if (sweep) 'sweep=true',
  [
    'K t=60 every=60 notAfter=arrival',
    'early=${time ? 'arrival-900' : 'straight<=1000'}',
    if (statsOnly) 'statsOnly=true',
  ].join(' '),
];

const _r1300 = '[route<=1300,route<=700]';
const _r5300 = '[route<=5300,route<=4700]';
const _battery20 = '0:25,600:22,1200:19,1800:16,2400:13,3000:10,3600:7,4200:5';
const _tr34Config =
    'D1000 pa kill@arrival-2400 relaunch@osFallbackFired+60:auto '
    'osDismiss=20';
const _tr35Config =
    'D1000 pa kill@arrival-600 relaunch@osFallbackFired+30:auto '
    'osRingMaxS=60';
const _ov = '[overshoot-15,overshoot+60]';

/// `profile/case` → (testIds, signature), from T11 §5.4 and §5.5.
final Map<String, (List<String>, List<String>)> golden = {
  // ---- train_hn_dh
  'train_hn_dh/distance_1000': (
    ['TR01'],
    [
      'D1000 pa',
      'E preAlert $_r5300',
      'E alarm/DISTANCE $_r1300',
      '! gpsLost,overshoot',
    ],
  ),
  'train_hn_dh/time_15': (
    ['TR02'],
    [
      'T15 pa',
      'E preAlert [arrival-1860,arrival-1740]',
      'E alarm/TIME [arrival-960,arrival-840]',
      '! gpsLost,overshoot',
    ],
  ),
  'train_hn_dh/smart': (
    ['TR08'],
    [
      'S pa',
      'E alarm/SMART_TIME [arrival-660,arrival-540]',
      '! gpsLost,overshoot',
    ],
  ),
  'train_hn_dh/distance_1000_snooze': (
    ['TR18'],
    [
      'D1000 pa actions[snooze@event:alarm+20,dismiss@event:snoozed+80]',
      'E alarm/DISTANCE $_r1300',
      'A snoozed >event:alarm [20,20]',
      'A alarm/SNOOZE_END/ringNow=true >event:alarm [80,85]',
      'A tripEnded >event:snoozed [80,80]',
      'O SNOOZED',
      '! gpsLost,overshoot',
    ],
  ),
  'train_hn_dh/distance_1000_kill': (
    ['TR22'],
    ['D1000 pa kill@arrival-2400', 'F straight<=1000 tol[-300,120]'],
  ),
  'train_hn_dh/distance_1000_kill_rang': (
    ['TR23'],
    [
      'D1000 pa kill@arrival-2400 relaunch@osFallbackFired+40:auto',
      'A alarm/FALLBACK/ringNow=false >relaunch [0,0]',
      '!a alarm/ringNow=true >relaunch-5',
    ],
  ),
  'train_hn_dh/distance_1000_kill_missing': (
    ['TR24'],
    [
      'D1000 pa kill@arrival-2400 relaunch@osFallbackFired+40:MISSING',
      'A alarm/FALLBACK_MISSED/ringNow=true >relaunch [0,0]',
      '!m alarm/FALLBACK',
    ],
  ),
  'train_hn_dh/distance_1000_kill_pending': (
    ['TR25'],
    [
      'D1000 pa kill@arrival-2400 relaunch@arrival-1800:PENDING',
      'E alarm/DISTANCE $_r1300',
      'A gpsLost/NO_FIX_TIMEOUT >relaunch [0,0]',
      'A gpsRecovered >relaunch [0,30]',
    ],
  ),
  'train_hn_dh/time_15_kill': (
    ['TR28'],
    ['T15 pa kill@arrival-2400', 'F arrival-900 tol[-300,120]'],
  ),
  'train_hn_dh/distance_1000_kill_osdismiss': (
    ['TR34'],
    [
      _tr34Config,
      'A alarm/FALLBACK/ringNow=false >relaunch [0,0]',
      'A tripEnded >relaunch [0,0]',
      'O ON_TIME',
      '!a alarm/ringNow=true >relaunch-5',
    ],
  ),
  'train_hn_dh/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'train_hn_dh/distance_1000_killsweep': (['TR37'], killSweepCase()),
  'train_hn_dh/time_15_killsweep': (['TR37'], killSweepCase(time: true)),
  // ---- coach_md_tb
  'coach_md_tb/distance_1000': (
    ['TR03'],
    [
      'D1000 pa',
      'E preAlert $_r5300',
      'E alarm/DISTANCE $_r1300',
      '! gpsLost,overshoot',
    ],
  ),
  'coach_md_tb/time_15': (
    ['TR03'],
    [
      'T15 pa',
      'E preAlert [arrival-1860,arrival-1740]',
      'E alarm/TIME [arrival-960,arrival-840]',
      '! gpsLost,overshoot',
    ],
  ),
  'coach_md_tb/smart': (
    ['TR09'],
    [
      'S pa',
      'E alarm/SMART_TIME [arrival-660,arrival-540]',
      '! gpsLost,overshoot',
    ],
  ),
  'coach_md_tb/distance_1000_battery': (
    ['TR20'],
    [
      'D1000 pa battery[$_battery20]',
      'E lowBatteryRisk [start+1200,start+1205]',
      'E alarm/LOW_BATTERY [start+4200,start+4205]',
      '! gpsLost,overshoot',
    ],
  ),
  'coach_md_tb/time_15_charging': (
    ['TR21'],
    [
      'T15 pa battery[0:6c]',
      'E alarm/TIME [arrival-960,arrival-840]',
      '! gpsLost,lowBatteryRisk,overshoot',
    ],
  ),
  'coach_md_tb/distance_1000_permission': (
    ['TR26'],
    [
      'D1000 pa actions[permissionRevoked@arrival-900]',
      'E gpsLost/PERMISSION_REVOKED [arrival-900,arrival-900]',
      'E alarm/GPS_LOST [arrival-900,arrival-900]',
      '! overshoot',
    ],
  ),
  'coach_md_tb/smart_kill': (
    ['TR29'],
    ['S pa kill@arrival-1800', 'F arrival-600 tol[-300,120]'],
  ),
  'coach_md_tb/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'coach_md_tb/distance_1000_killsweep': (['TR37'], killSweepCase()),
  // ---- bus_hn_brt01
  'bus_hn_brt01/distance_500': (
    ['TR04'],
    [
      'D500 pa',
      'E preAlert [route<=3300,route<=2700]',
      'E alarm/DISTANCE [route<=800,route<=200]',
      '! gpsLost,overshoot',
    ],
  ),
  'bus_hn_brt01/distance_1000': (
    ['TR04'],
    [
      'D1000 pa',
      'E preAlert $_r5300',
      'E alarm/DISTANCE $_r1300',
      '! gpsLost,overshoot',
    ],
  ),
  'bus_hn_brt01/summary_unknown': (['TR27'], summary('BUS')),
  // ---- bus_hn_brt01_noisy
  'bus_hn_brt01_noisy/distance_1000_noisy': (
    ['TR07'],
    [
      'D1000 pa',
      'E preAlert $_r5300',
      'E alarm/DISTANCE $_r1300',
      '! gpsLost,overshoot',
    ],
  ),
  'bus_hn_brt01_noisy/summary_unknown': (['TR27'], summary('BUS')),
  // ---- coach_dn_langco_tunnel
  'coach_dn_langco_tunnel/distance_1000_gps_lost': (
    ['TR05'],
    [
      'D1000 nopa',
      'E gpsLost/NO_FIX_TIMEOUT [gpsGap[0].start,gpsGap[0].start+90]',
      'E alarm/GPS_LOST [gpsGap[0].start,gpsGap[0].start+90]',
      'E gpsRecovered [gpsGap[0].end,gpsGap[0].end+60]',
      '! overshoot',
    ],
  ),
  'coach_dn_langco_tunnel/summary_unknown': (['TR27'], summary('UNKNOWN')),
  // ---- coach_gb_phuly_overshoot
  'coach_gb_phuly_overshoot/distance_1000_overshoot': (
    ['TR06'],
    [
      'D1000 pa',
      'E preAlert $_r5300',
      'E alarm/DISTANCE $_r1300',
      'E overshoot $_ov',
      '! gpsLost',
      '!m alarm/OVERSHOOT',
    ],
  ),
  'coach_gb_phuly_overshoot/distance_1000_dismiss': (
    ['TR19'],
    [
      'D1000 pa actions[dismiss@event:alarm+30]',
      'E alarm/DISTANCE $_r1300',
      'A tripEnded >event:alarm [30,30]',
      'O ON_TIME',
      '! gpsLost,overshoot',
    ],
  ),
  'coach_gb_phuly_overshoot/distance_1000_overshoot_silenced': (
    ['TR33'],
    [
      'D1000 pa osRingMaxS=60',
      'E alarm/DISTANCE/ringNow=true $_r1300',
      'E alarm/OVERSHOOT/ringNow=true $_ov',
      'E overshoot $_ov',
      '! gpsLost',
    ],
  ),
  'coach_gb_phuly_overshoot/distance_1000_fallback_silenced': (
    ['TR35'],
    [
      _tr35Config,
      'E alarm/OVERSHOOT/ringNow=true $_ov',
      'E overshoot $_ov',
      'A alarm/FALLBACK/ringNow=false >relaunch [0,0]',
      'F straight<=1000 tol[-300,120]',
    ],
  ),
  'coach_gb_phuly_overshoot/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'coach_gb_phuly_overshoot/distance_1000_killsweep': (
    ['TR37'],
    killSweepCase(sweep: true, statsOnly: true),
  ),
  // ---- new profiles (T11 §6.2)
  'bus_hn_slow/smart': (
    ['TR10'],
    [
      'S pa',
      'E alarm/SMART_SLOW_DISTANCE [route<=2800,route<=2200]',
      '! gpsLost,overshoot',
    ],
  ),
  'bus_hn_slow/smart_floor': (
    ['TR11'],
    [
      'S pa params{smartSlowSpeedKmh=5,smartTargetS=300}',
      'E alarm/SMART_DISTANCE $_r1300',
      '! gpsLost,overshoot',
    ],
  ),
  'bus_hn_slow/summary_unknown': (['TR27'], summary('BUS')),
  'bus_hn_slow/distance_1000_killsweep': (['TR37'], killSweepCase()),
  'coach_dn_langco_shortgap/distance_1000_shortgap': (
    ['TR13'],
    [
      'D1000 nopa',
      'E gpsLost/NO_FIX_TIMEOUT [gpsGap[0].start,gpsGap[0].end-5]',
      'E gpsRecovered [gpsGap[0].end,gpsGap[0].end+30]',
      'E alarm $_r1300',
      'E alarm/DISTANCE $_r1300',
      '! overshoot',
    ],
  ),
  'coach_dn_langco_shortgap/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'coach_dn_langco_neardest/distance_1000_neardest': (
    ['TR14'],
    [
      'D1000 nopa',
      'E gpsLost/NO_FIX_TIMEOUT [gpsGap[0].start,gpsGap[0].start+90]',
      'E alarm/GPS_LOST [gpsGap[0].start,gpsGap[0].start+90]',
      'E gpsRecovered [gpsGap[0].end,gpsGap[0].end+60]',
      '! overshoot',
    ],
  ),
  'coach_dn_langco_neardest/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'train_hn_dh_midgap/distance_1000_midgap': (
    ['TR15'],
    [
      'D1000 pa',
      'E gpsLost/NO_FIX_TIMEOUT [gpsGap[0].start+360,gpsGap[0].start+720]',
      'E gpsRecovered [gpsGap[0].end,gpsGap[0].end+30]',
      'E alarm $_r1300',
      'E alarm/DISTANCE $_r1300',
      '! overshoot',
    ],
  ),
  'train_hn_dh_midgap/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'bus_hn_brt01_noisy_traps/distance_1000': (
    ['TR16', 'TR17'],
    [
      'D1000 pa',
      'E preAlert $_r5300',
      'E alarm/DISTANCE $_r1300',
      '! gpsLost,overshoot',
    ],
  ),
  'bus_hn_brt01_noisy_traps/summary_unknown': (['TR27'], summary('BUS')),
  'train_hn_dh_stopgap/distance_1000': (
    ['TR30'],
    [
      'D1000 pa',
      'sweep=true',
      'E alarm/GPS_LOST/ringNow=true [gpsGap[0].start,arrival-300]',
      '! overshoot',
    ],
  ),
  'train_hn_dh_stopgap/summary_unknown': (
    ['TR27'],
    summary('UNKNOWN', sweep: true),
  ),
  'train_hn_dh_stopgap/distance_1000_killsweep': (
    ['TR37'],
    killSweepCase(sweep: true),
  ),
  'train_longstop/time_15': (
    ['TR12'],
    ['T15 pa', 'E alarm/TIME [arrival-960,arrival-840]', '! gpsLost,overshoot'],
  ),
  'train_longstop/time_10': (
    ['TR12'],
    ['T10 pa', 'E alarm/TIME [arrival-660,arrival-540]', '! gpsLost,overshoot'],
  ),
  'train_longstop/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'train_longstop/distance_1000_killsweep': (
    ['TR37'],
    killSweepCase(sweep: true, statsOnly: true),
  ),
  'train_longstop_nospd/time_15': (
    ['TR31'],
    ['T15 pa', 'E alarm/TIME [arrival-960,arrival-840]', '! gpsLost,overshoot'],
  ),
  'train_longstop_nospd/summary_unknown': (['TR27'], summary('UNKNOWN')),
  'coach_gb_phuly_offroute/distance_1000': (
    ['TR32'],
    [
      'D1000 pa',
      'E alarm/PASSED_CLOSEST [closest.departT,closest.departT+30]',
      '! gpsLost,overshoot',
      '!m alarm/DISTANCE',
    ],
  ),
  'coach_gb_phuly_offroute/summary_unknown': (['TR27'], summary('UNKNOWN')),
};

void main() {
  final ids = ProfileRepository(dataDir).profileIds();
  final fixtures = {
    for (final id in ids)
      id: jsonDecode(
        File('${fixturesDir.path}/$id.expect.json').readAsStringSync(),
      ) as Map<String, Object?>,
  };
  final cases = <String, Map<String, Object?>>{
    for (final MapEntry(key: id, value: j) in fixtures.entries)
      for (final c in (j['cases']! as List).cast<Map<String, Object?>>())
        '$id/${c['id']}': c,
  };

  group('TG31 trace coverage (T10 TR ↔ T11 cases)', () {
    test('15 profiles, 58 cases, exactly the §5.4/§5.5 case list', () {
      expect(ids, hasLength(15));
      expect(golden, hasLength(58));
      expect(cases.keys.toSet(), golden.keys.toSet());
    });

    test('every case is final with non-empty testIds', () {
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(value['status'], 'final', reason: key);
        expect(value['testIds'], isA<List<Object?>>(), reason: key);
        expect(value['testIds']! as List, isNotEmpty, reason: key);
      }
    });

    test('testIds of each case match the golden table', () {
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(value['testIds'], golden[key]?.$1, reason: key);
      }
    });

    test('every TR01–TR35 and TR37 is covered, TR36 has no case', () {
      final covered = <String, List<String>>{};
      for (final MapEntry(:key, :value) in cases.entries) {
        for (final tr in (value['testIds']! as List).cast<String>()) {
          (covered[tr] ??= []).add(key);
        }
      }
      final all = [
        for (var i = 1; i <= 35; i++) 'TR${i.toString().padLeft(2, '0')}',
        'TR37',
      ];
      expect(covered.keys.toSet(), all.toSet());
      expect(covered.containsKey('TR36'), isFalse);
      // Multiplicities fixed by §5.4: TR03, TR04, TR12 have two cases;
      // TR27 one per profile; TR37 seven (T11.1 §5.8); every other TR
      // exactly one.
      for (final tr in all) {
        final n = switch (tr) {
          'TR03' || 'TR04' || 'TR12' => 2,
          'TR27' => 15,
          'TR37' => 7,
          _ => 1,
        };
        expect(covered[tr], hasLength(n), reason: '$tr: ${covered[tr]}');
      }
    });

    test('TR27 summary_unknown exists in all 15 profiles', () {
      for (final id in ids) {
        final c = cases['$id/summary_unknown'];
        expect(c, isNotNull, reason: id);
        final vehicle = (fixtures[id]!['trace']! as Map)['vehicle'];
        expect(
          (c!['expectSummary']! as Map)['vehicleGuess'],
          vehicle == 'bus' ? 'BUS' : 'UNKNOWN',
          reason: id,
        );
      }
    });

    test('no case restricts samplingModes (T11.1)', () {
      final restricted = [
        for (final MapEntry(:key, :value) in cases.entries)
          if (value.containsKey('samplingModes')) key,
      ];
      expect(restricted, isEmpty);
    });

    test('policyPhaseSweep is true in exactly the five §5.8 cases', () {
      final swept = [
        for (final MapEntry(:key, :value) in cases.entries)
          if (value['policyPhaseSweep'] == true) key,
      ];
      expect(swept.toSet(), {
        'train_hn_dh_stopgap/distance_1000',
        'train_hn_dh_stopgap/summary_unknown',
        'train_hn_dh_stopgap/distance_1000_killsweep',
        'coach_gb_phuly_overshoot/distance_1000_killsweep',
        'train_longstop/distance_1000_killsweep',
      });
    });

    for (final key in golden.keys) {
      test('$key matches its §5.4/§5.5 row', () {
        final c = cases[key];
        expect(c, isNotNull, reason: 'missing case $key');
        expect(signature(c!), golden[key]!.$2);
      });
    }

    test('self-check: the signature sees a dropped filter or mode limit', () {
      const tr01 = 'train_hn_dh/distance_1000';
      const tr30 = 'train_hn_dh_stopgap/distance_1000';
      final c = deepCopy(cases[tr01])! as Map<String, Object?>;
      ((c['expect']! as List)[1]! as Map<String, Object?>).remove('reason');
      expect(signature(c), isNot(golden[tr01]!.$2));
      final d = deepCopy(cases[tr30])! as Map<String, Object?>
        ..remove('policyPhaseSweep');
      expect(signature(d), isNot(golden[tr30]!.$2));
      const tr37f = 'coach_gb_phuly_overshoot/distance_1000_killsweep';
      final f = deepCopy(cases[tr37f])! as Map<String, Object?>;
      (f['killSweep']! as Map<String, Object?>).remove('statsOnly');
      expect(signature(f), isNot(golden[tr37f]!.$2));
    });

    test('profile JSON and fixture list the same cases in the same order', () {
      for (final id in ids) {
        final profile = jsonDecode(
          File('${dataDir.path}/profiles/$id.json').readAsStringSync(),
        ) as Map<String, Object?>;
        expect(
          [for (final c in profile['cases']! as List) (c as Map)['id']],
          [for (final c in fixtures[id]!['cases']! as List) (c as Map)['id']],
          reason: id,
        );
      }
    });
  });
}
