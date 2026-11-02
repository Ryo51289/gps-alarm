// T11 TG33 (tester): hand-broken fixtures that `tracegen validate` must
// reject, each with `<file>:<path>: <message>` and exit 1, plus TG35 (`check`
// catches a profile edited without `generate`) and the limits of `validate`
// that only `check` covers.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

typedef _J = Map<String, Object?>;

String _read(String name) =>
    File('${fixturesDir.path}/$name').readAsStringSync();

String _mutate(String text, void Function(_J j) f) {
  final json = jsonDecode(text) as _J;
  f(json);
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

Object? _dig(Object? o, List<Object> path) {
  var cur = o;
  for (final k in path) {
    cur = k is int ? (cur! as List<Object?>)[k] : (cur! as Map)[k];
  }
  return cur;
}

_J _obj(Object? o, List<Object> path) => _dig(o, path)! as _J;

Future<(int, String, String)> _cli(List<String> args) async {
  final out = CapturedSink();
  final err = CapturedSink();
  final code = await runCli(
    args,
    out: out.sink,
    err: err.sink,
    workingDirectory: packageDir,
  );
  return (code, await out.text(), await err.text());
}

/// One fixture under attack.
final class _Target {
  new(this.id)
    : gpx = _read('$id.gpx'),
      text = _read('$id.expect.json'),
      caseIds = [
        for (final c
            in (jsonDecode(_read('$id.expect.json')) as _J)['cases']! as List)
          (c as Map)['id']! as String,
      ];

  final String id;
  final String gpx;
  final String text;
  final List<String> caseIds;

  int indexOf(String caseId) {
    final i = caseIds.indexOf(caseId);
    if (i < 0) {
      throw ArgumentError('$id has no case $caseId');
    }
    return i;
  }

  /// `cases[i]` of [caseId] inside the decoded fixture [j].
  _J caseOf(_J j, String caseId) =>
      (j['cases']! as List)[indexOf(caseId)]! as _J;

  List<String> run(void Function(_J j) f) => validatePair(
    gpxLabel: '$id.gpx',
    gpxBytes: utf8.encode(gpx),
    expectLabel: '$id.expect.json',
    expectBytes: utf8.encode(_mutate(text, f)),
  );
}

void main() {
  final dh = _Target('train_hn_dh');
  final md = _Target('coach_md_tb');
  final off = _Target('coach_gb_phuly_offroute');

  /// Asserts an error `<label>:<path>: …<message>…` among [errors].
  void rejects(
    List<String> errors,
    String label,
    String path,
    Pattern message,
  ) {
    expect(
      errors.any((e) => e.startsWith('$label:$path: ') && e.contains(message)),
      isTrue,
      reason:
          'expected "$label:$path: …$message…", got:\n'
          '${errors.isEmpty ? '(none)' : errors.join('\n')}',
    );
  }

  group('TG33 validate rejects hand-broken fixtures', () {
    // (description, target, case id, mutation, path inside the case, message)
    final cases =
        <(String, _Target, String, void Function(_J c), String, Pattern)>[
          // ---- spec TG33 list
          (
            'final case without testIds',
            dh,
            'summary_unknown',
            (c) => c.remove('testIds'),
            'testIds',
            'a final case needs a non-empty testIds',
          ),
          (
            'final case with empty testIds',
            dh,
            'summary_unknown',
            (c) => c['testIds'] = <Object?>[],
            'testIds',
            'a final case needs a non-empty testIds',
          ),
          (
            r'testIds not matching ^TR\d{2}$',
            dh,
            'distance_1000',
            (c) => c['testIds'] = ['TR1'],
            'testIds[0]',
            'must match',
          ),
          (
            'duplicate testIds',
            dh,
            'distance_1000',
            (c) => c['testIds'] = ['TR01', 'TR01'],
            'testIds[1]',
            'duplicate test id',
          ),
          (
            'forbidMatch contradicting an expectAfter',
            dh,
            'distance_1000_kill_missing',
            (c) => c['forbidMatch'] = [
              {'event': 'alarm', 'reason': 'FALLBACK_MISSED'},
            ],
            'forbidMatch[0]',
            'forbids an event',
          ),
          (
            'forbidMatch without filter contradicting expect alarm',
            dh,
            'distance_1000',
            (c) => c['forbidMatch'] = [
              {'event': 'alarm'},
            ],
            'forbidMatch[0]',
            'forbids an event',
          ),
          (
            'expectFallback without asOfT',
            dh,
            'distance_1000_kill',
            (c) => (c['expectFallback']! as _J).remove('asOfT'),
            'expectFallback.asOfT',
            'missing required key',
          ),
          (
            'relaunch without kill',
            dh,
            'distance_1000_kill_rang',
            (c) => (c['config']! as _J).remove('kill'),
            'config.relaunch',
            'needs config.kill',
          ),
          (
            'withinS lo > hi',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['expectAfter', 1])['withinS'] = [85, 80],
            'expectAfter[1].withinS',
            'need 0 <= lo <= hi',
          ),
          (
            'withinS lo < 0',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['expectAfter', 0])['withinS'] = [-5, 0],
            'expectAfter[0].withinS',
            'need 0 <= lo <= hi',
          ),
          // ---- run anchors in inputs (review #2, TG37)
          for (final o in [0, -5])
            (
              'actions event:alarm offsetS $o',
              dh,
              'distance_1000_snooze',
              (c) => _obj(c, ['config', 'actions', 0, 'at'])['offsetS'] = o,
              'config.actions[0].at.offsetS',
              'requires offsetS >= sampleIntervalS (5)',
            ),
          for (final o in [0, -5])
            (
              'actions event:snoozed offsetS $o',
              dh,
              'distance_1000_snooze',
              (c) => _obj(c, ['config', 'actions', 1, 'at'])['offsetS'] = o,
              'config.actions[1].at.offsetS',
              'requires offsetS >= sampleIntervalS (5)',
            ),
          for (final o in [0, -5])
            (
              'actions relaunch offsetS $o',
              dh,
              'distance_1000_kill_rang',
              (c) => (c['config']! as _J)['actions'] = [
                {
                  'at': {'anchor': 'relaunch', 'offsetS': o},
                  'action': 'dismiss',
                },
              ],
              'config.actions[0].at.offsetS',
              'requires offsetS >= sampleIntervalS (5)',
            ),
          for (final o in [0, -5])
            (
              'relaunch.at osFallbackFired offsetS $o',
              dh,
              'distance_1000_kill_missing',
              (c) => _obj(c, ['config', 'relaunch', 'at'])['offsetS'] = o,
              'config.relaunch.at.offsetS',
              'requires offsetS >= sampleIntervalS (5)',
            ),
          for (final o in [0, -5])
            (
              'relaunch.at event:preAlert offsetS $o',
              dh,
              'distance_1000_kill_osdismiss',
              (c) => _obj(c, ['config', 'relaunch', 'at'])
                ..['anchor'] = 'event:preAlert'
                ..['offsetS'] = o,
              'config.relaunch.at.offsetS',
              'requires offsetS >= sampleIntervalS (5)',
            ),
          (
            'run anchor without offsetS',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['config', 'actions', 0, 'at']).remove('offsetS'),
            'config.actions[0].at.offsetS',
            'missing required key',
          ),
          (
            'run anchor offsetS not a multiple of I',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['config', 'actions', 0, 'at'])['offsetS'] = 22,
            'config.actions[0].at.offsetS',
            'multiple of sampleIntervalS',
          ),
          (
            'run anchor with a t',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['config', 'actions', 0, 'at'])['t'] = 33700,
            'config.actions[0].at.t',
            'a run-time anchor has no t',
          ),
          // ---- static At
          (
            'kill.t not a multiple of I',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'kill'])['t'] = 31391,
            'config.kill.t',
            'multiple of sampleIntervalS',
          ),
          (
            'static action after durationS',
            dh,
            'summary_unknown',
            (c) => _obj(c, ['config', 'actions', 0, 'at'])['t'] = 33910,
            'config.actions[0].at.t',
            'outside [0, durationS',
          ),
          (
            'static At before 0',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'kill'])['t'] = -5,
            'config.kill.t',
            'outside [0, durationS',
          ),
          (
            'static relaunch at kill.t',
            dh,
            'distance_1000_kill_pending',
            (c) => _obj(c, ['config', 'relaunch', 'at'])['t'] = 31390,
            'config.relaunch.at.t',
            'must be after config.kill',
          ),
          (
            'offsetS without anchor',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'kill'])
              ..remove('anchor')
              ..['offsetS'] = 0,
            'config.kill.offsetS',
            'only allowed together with anchor',
          ),
          // ---- relaunch / osSim / osDismiss
          (
            'osDismiss with fallbackStatus RANG',
            dh,
            'distance_1000_kill_osdismiss',
            (c) => _obj(c, ['config', 'relaunch'])['fallbackStatus'] = 'RANG',
            'config.osDismiss',
            'needs config.relaunch with fallbackStatus auto',
          ),
          (
            'osDismiss offsetS 0',
            dh,
            'distance_1000_kill_osdismiss',
            (c) => _obj(c, ['config', 'osDismiss'])['offsetS'] = 0,
            'config.osDismiss.offsetS',
            'must be > 0',
          ),
          (
            'osDismiss offsetS not a multiple of I',
            dh,
            'distance_1000_kill_osdismiss',
            (c) => _obj(c, ['config', 'osDismiss'])['offsetS'] = 22,
            'config.osDismiss.offsetS',
            'multiple of sampleIntervalS',
          ),
          (
            'osSim false with relaunch auto',
            dh,
            'distance_1000_kill_rang',
            (c) => (c['config']! as _J)['osSim'] = false,
            'config.osSim',
            'needs osSim',
          ),
          (
            'unknown fallbackStatus',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'relaunch'])['fallbackStatus'] = 'LOST',
            'config.relaunch.fallbackStatus',
            'unknown status',
          ),
          (
            'osRingMaxS 0',
            dh,
            'distance_1000_kill_rang',
            (c) => (c['config']! as _J)['osRingMaxS'] = 0,
            'config.osRingMaxS',
            'must be > 0',
          ),
          // ---- expectFallback formula (T11 §5.3 as revised by T11.1 §4)
          (
            'expectFallback asOfT = killT',
            dh,
            'distance_1000_kill',
            (c) => (c['expectFallback']! as _J)['asOfT'] = 31390,
            'expectFallback.asOfT',
            'must be killT - sampleIntervalS (31385)',
          ),
          (
            'expectFallback notBefore off by one tick',
            dh,
            'distance_1000_kill',
            (c) => (c['expectFallback']! as _J)['notBefore'] = 33008,
            'expectFallback.notBefore',
            'min(estimateT, hintEstimateT) + toleranceS[0] = 33003',
          ),
          (
            'expectFallback notAfter off by one tick',
            dh,
            'time_15_kill',
            (c) => (c['expectFallback']! as _J)['notAfter'] = 32820,
            'expectFallback.notAfter',
            'estimateT + toleranceS[1] = 32815',
          ),
          (
            'expectFallback modeAtT changed (estimate no longer matches)',
            dh,
            'distance_1000_kill',
            (c) => _obj(c, ['expectFallback', 'window'])['modeAtT'] = 33705,
            'expectFallback.window.estimateT',
            'T11 §5.3 gives',
          ),
          (
            'expectFallback window.killT ≠ config.kill.t',
            dh,
            'distance_1000_kill',
            (c) => _obj(c, ['expectFallback', 'window'])['killT'] = 31395,
            'expectFallback.window.killT',
            'but config.kill.t is 31390',
          ),
          (
            'expectFallback without kill',
            dh,
            'distance_1000_kill',
            (c) => (c['config']! as _J).remove('kill'),
            'expectFallback',
            'needs config.kill',
          ),
          (
            'expectFallback with params.fallbackLagS',
            dh,
            'distance_1000_kill',
            (c) => (c['config']! as _J)['params'] = {'fallbackLagS': 60},
            'expectFallback',
            'fallbackLagS',
          ),
          (
            'expectFallback modeAt run anchor',
            dh,
            'distance_1000_kill',
            (c) => _obj(c, ['expectFallback', 'window', 'modeAt'])['anchor'] =
                'event:alarm',
            'expectFallback.window.modeAt.anchor',
            'run-time anchor "event:alarm" is not allowed here',
          ),
          // ---- filters (§2.4)
          (
            'reason on gpsLost',
            dh,
            'distance_1000_kill_pending',
            (c) => _obj(c, ['expectAfter', 0])['reason'] = 'GPS_LOST',
            'expectAfter[0].reason',
            'reason is only allowed on alarm',
          ),
          (
            'unknown alarm reason',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 1])['reason'] = 'NEAR',
            'expect[1].reason',
            'unknown alarm reason "NEAR"',
          ),
          (
            'ringNow on preAlert',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 0])['ringNow'] = true,
            'expect[0].ringNow',
            'ringNow is only allowed on alarm',
          ),
          (
            'ringNow not a bool',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['expectAfter', 0])['ringNow'] = 'false',
            'expectAfter[0].ringNow',
            'must be true or false',
          ),
          (
            'fallbackAlarmChanged cause on gpsLost',
            dh,
            'distance_1000_kill_pending',
            (c) => _obj(c, ['expectAfter', 0])['cause'] = 'SUPERSEDED',
            'expectAfter[0].cause',
            'unknown gpsLost cause "SUPERSEDED"',
          ),
          // ---- consistency (§5.2)
          (
            'duplicate expect (event, reason, ringNow, cause)',
            dh,
            'distance_1000',
            (c) => (c['expect']! as List).add(deepCopy(_dig(c, ['expect', 1]))),
            'expect[2]',
            'duplicate expectation of "alarm" with the same filters',
          ),
          (
            'forbid contains an expected event',
            dh,
            'distance_1000',
            (c) => (c['forbid']! as List).add('alarm'),
            'forbid[2]',
            'event "alarm" is also expected',
          ),
          (
            'forbid contains an expectAfter event',
            dh,
            'distance_1000_kill_osdismiss',
            (c) => c['forbid'] = ['tripEnded'],
            'forbid[0]',
            'event "tripEnded" is also expected',
          ),
          (
            'forbid duplicate',
            dh,
            'distance_1000',
            (c) => (c['forbid']! as List).add('gpsLost'),
            'forbid[2]',
            'duplicate event',
          ),
          (
            'forbidAfter contradicting expectAfter (0 + 0 > −5)',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['forbidAfter', 0])
              ..remove('ringNow')
              ..['reason'] = 'FALLBACK',
            'forbidAfter[0]',
            'forbids an event that expectAfter requires after the same anchor',
          ),
          (
            'unknown event in forbid',
            dh,
            'distance_1000',
            (c) => (c['forbid']! as List).add('ring'),
            'forbid[2]',
            'unknown event',
          ),
          (
            'unknown event in expectAfter',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['expectAfter', 0])['event'] = 'snooze',
            'expectAfter[0].event',
            'unknown event',
          ),
          // ---- config values
          (
            'thresholdM 199',
            dh,
            'distance_1000',
            (c) => (c['config']! as _J)['thresholdM'] = 199,
            'config.thresholdM',
            'must be in [200, 10000]',
          ),
          (
            'thresholdM 10001',
            dh,
            'distance_1000',
            (c) => (c['config']! as _J)['thresholdM'] = 10001,
            'config.thresholdM',
            'must be in [200, 10000]',
          ),
          (
            'thresholdMin 4',
            dh,
            'time_15',
            (c) => (c['config']! as _J)['thresholdMin'] = 4,
            'config.thresholdMin',
            'must be in [5, 60]',
          ),
          (
            'smart with thresholdM',
            dh,
            'smart',
            (c) => (c['config']! as _J)['thresholdM'] = 1000,
            'config.thresholdM',
            'not allowed in smart mode',
          ),
          (
            'time with thresholdM',
            dh,
            'time_15',
            (c) => (c['config']! as _J)['thresholdM'] = 1000,
            'config.thresholdM',
            'not allowed in time mode',
          ),
          (
            'unknown mode',
            dh,
            'distance_1000',
            (c) => (c['config']! as _J)['mode'] = 'eta',
            'config.mode',
            'must be distance, time or smart',
          ),
          (
            'unknown vehicleHint',
            dh,
            'summary_unknown',
            (c) => (c['config']! as _J)['vehicleHint'] = 'plane',
            'config.vehicleHint',
            'unknown vehicle hint',
          ),
          (
            'unknown engine parameter',
            dh,
            'distance_1000',
            (c) => (c['config']! as _J)['params'] = {'foo': 1},
            'config.params.foo',
            'unknown engine parameter',
          ),
          (
            'type I parameter as a double',
            dh,
            'smart',
            (c) => (c['config']! as _J)['params'] = {'smartTargetS': 300.5},
            'config.params.smartTargetS',
            'type I parameter must be a JSON integer',
          ),
          (
            'type D parameter with 5 decimals',
            dh,
            'smart',
            (c) =>
                (c['config']! as _J)['params'] = {'routeFactorPrior': 1.23456},
            'config.params.routeFactorPrior',
            'more than 4 decimals',
          ),
          (
            'battery t not increasing',
            md,
            'distance_1000_battery',
            (c) => _obj(c, ['config', 'battery', 2])['t'] = 600,
            'config.battery[2].t',
            'must increase strictly',
          ),
          (
            'battery t not a multiple of I',
            md,
            'distance_1000_battery',
            (c) => _obj(c, ['config', 'battery', 1])['t'] = 601,
            'config.battery[1].t',
            'multiple of sampleIntervalS',
          ),
          (
            'battery levelPct 101',
            md,
            'distance_1000_battery',
            (c) => _obj(c, ['config', 'battery', 0])['levelPct'] = 101,
            'config.battery[0].levelPct',
            'must be in [0, 100]',
          ),
          (
            'battery without charging',
            md,
            'distance_1000_battery',
            (c) => _obj(c, ['config', 'battery', 0]).remove('charging'),
            'config.battery[0].charging',
            'missing required key',
          ),
          (
            'unknown action',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['config', 'actions', 0])['action'] = 'jump',
            'config.actions[0].action',
            'unknown action',
          ),
          (
            'unknown expectOutcome',
            dh,
            'distance_1000_snooze',
            (c) => c['expectOutcome'] = 'LATE',
            'expectOutcome',
            'unknown outcome',
          ),
          (
            'unknown vehicleGuess',
            dh,
            'summary_unknown',
            (c) => _obj(c, ['expectSummary'])['vehicleGuess'] = 'PLANE',
            'expectSummary.vehicleGuess',
            'unknown vehicle guess',
          ),
          (
            'samplingModes with both modes',
            dh,
            'distance_1000',
            (c) => c['samplingModes'] = ['all', 'policy'],
            'samplingModes',
            'must be ["all"] or ["policy"]',
          ),
          (
            'samplingModes unknown',
            dh,
            'distance_1000',
            (c) => c['samplingModes'] = ['fast'],
            'samplingModes',
            'must be ["all"] or ["policy"]',
          ),
          (
            'status done',
            dh,
            'distance_1000',
            (c) => c['status'] = 'done',
            'status',
            'must be draft or final',
          ),
          // ---- anchors: syntax, place of use, references
          (
            'run anchor in an expect window',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 1, 'window', 'notBefore'])['anchor'] =
                'event:preAlert',
            'expect[1].window.notBefore.anchor',
            'run-time anchor "event:preAlert" is not allowed here',
          ),
          (
            'kill anchored on kill',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'kill'])['anchor'] = 'kill',
            'config.kill.anchor',
            'anchor "kill" is not allowed in config.kill',
          ),
          (
            'kill anchored on a run anchor',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'kill'])
              ..remove('t')
              ..['anchor'] = 'event:alarm'
              ..['offsetS'] = 5,
            'config.kill.anchor',
            'anchor "event:alarm" is not allowed in config.kill',
          ),
          (
            'osFallbackFired in actions',
            dh,
            'distance_1000_kill_rang',
            (c) => (c['config']! as _J)['actions'] = [
              {
                'at': {'anchor': 'osFallbackFired', 'offsetS': 5},
                'action': 'dismiss',
              },
            ],
            'config.actions[0].at.anchor',
            'anchor "osFallbackFired" is not allowed in config.actions',
          ),
          (
            'relaunch anchor in relaunch.at',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['config', 'relaunch', 'at'])['anchor'] = 'relaunch',
            'config.relaunch.at.anchor',
            'anchor "relaunch" is not allowed in config.relaunch',
          ),
          (
            'event:<unknown>',
            dh,
            'distance_1000_snooze',
            (c) => _obj(c, ['config', 'actions', 0, 'at'])['anchor'] =
                'event:boom',
            'config.actions[0].at.anchor',
            'unknown event "boom" in "event:boom"',
          ),
          (
            'malformed anchor',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 1, 'window', 'notAfter'])['anchor'] =
                'route<700',
            'expect[1].window.notAfter.anchor',
            'invalid anchor "route<700"',
          ),
          (
            'gpsGap[0] on a trace without gaps',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 1, 'window', 'notAfter'])['anchor'] =
                'gpsGap[0].end',
            'expect[1].window.notAfter.anchor',
            'gap index 0 out of range',
          ),
          (
            'closest on a trace without truth.closest',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 1, 'window', 'notAfter'])['anchor'] =
                'closest.departT',
            'expect[1].window.notAfter.anchor',
            'needs destinationOffsetM',
          ),
          (
            'relaunch anchor without config.relaunch',
            dh,
            'distance_1000_kill',
            (c) => c['expectAfter'] = [
              {
                'event': 'gpsLost',
                'after': {'anchor': 'relaunch', 'offsetS': 0},
                'withinS': [0, 0],
                'ref': 'x',
              },
            ],
            'expectAfter[0].after.anchor',
            'needs config.relaunch',
          ),
          (
            'osFallbackFired without config.kill',
            dh,
            'distance_1000',
            (c) => c['forbidAfter'] = [
              {
                'event': 'preAlert',
                'after': {'anchor': 'osFallbackFired', 'offsetS': 0},
              },
            ],
            'forbidAfter[0].after.anchor',
            'needs config.kill',
          ),
          (
            'closest.departT with params.passedClosestOpenMinM',
            off,
            'distance_1000',
            (c) =>
                (c['config']! as _J)['params'] = {'passedClosestOpenMinM': 300},
            'expect[0].window.notBefore.anchor',
            'closest.departT',
          ),
          // ---- expect windows
          (
            'notBefore > notAfter',
            dh,
            'time_15',
            (c) => _obj(c, ['expect', 1])['notBefore'] = 32955,
            'expect[1]',
            'need 0 <= notBefore',
          ),
          (
            'notAfter > durationS',
            dh,
            'summary_unknown',
            (c) => _obj(c, ['expect', 0])['notAfter'] = 33910,
            'expect[0]',
            'need 0 <= notBefore',
          ),
          (
            'expect without ref',
            dh,
            'distance_1000',
            (c) => _obj(c, ['expect', 0]).remove('ref'),
            'expect[0].ref',
            'missing required key',
          ),
          // ---- unknown nested keys not covered by TG38 / the reviewer
          (
            'unknown key in expect[i].window.notAfter',
            dh,
            'time_15',
            (c) => _obj(c, ['expect', 1, 'window', 'notAfter'])['foo'] = 1,
            'expect[1].window.notAfter.foo',
            'unknown key',
          ),
          (
            'unknown key in config.osDismiss',
            dh,
            'distance_1000_kill_osdismiss',
            (c) => _obj(c, ['config', 'osDismiss'])['foo'] = 1,
            'config.osDismiss.foo',
            'unknown key',
          ),
          (
            'unknown key in expectFallback.window',
            dh,
            'time_15_kill',
            (c) => _obj(c, ['expectFallback', 'window'])['foo'] = 1,
            'expectFallback.window.foo',
            'unknown key',
          ),
          (
            'unknown key in forbidAfter[i].after',
            dh,
            'distance_1000_kill_osdismiss',
            (c) => _obj(c, ['forbidAfter', 0, 'after'])['foo'] = 1,
            'forbidAfter[0].after.foo',
            'unknown key',
          ),
          (
            'unknown filter key in expectAfter[i]',
            dh,
            'distance_1000_kill_rang',
            (c) => _obj(c, ['expectAfter', 0])['source'] = 'os',
            'expectAfter[0].source',
            'unknown key',
          ),
        ];

    for (final (name, t, caseId, mutate, path, message) in cases) {
      test(name, () {
        final errors = t.run((j) => mutate(t.caseOf(j, caseId)));
        rejects(
          errors,
          '${t.id}.expect.json',
          'cases[${t.indexOf(caseId)}].$path',
          message,
        );
      });
    }

    test('duplicate case id', () {
      final errors = dh.run(
        (j) => dh.caseOf(j, 'smart')['id'] = 'distance_1000',
      );
      rejects(
        errors,
        'train_hn_dh.expect.json',
        'cases[${dh.indexOf('smart')}].id',
        'duplicate case id',
      );
    });

    test('destination.offsetM 0 and truth.closest without departT', () {
      rejects(
        off.run((j) => (j['destination']! as _J)['offsetM'] = 0),
        'coach_gb_phuly_offroute.expect.json',
        'destination.offsetM',
        'must be omitted when 0',
      );
      rejects(
        off.run((j) => _obj(j, ['truth', 'closest']).remove('departT')),
        'coach_gb_phuly_offroute.expect.json',
        'truth.closest.departT',
        'missing required key',
      );
    });

    test('allowed edge cases stay valid (positive controls)', () {
      // Checks may use offsetS <= 0 (README §3.1); offset 5 = one tick.
      expect(
        dh.run((j) {
          final c = dh.caseOf(j, 'distance_1000_snooze');
          _obj(c, ['expectAfter', 0, 'after'])['offsetS'] = -5;
          _obj(c, ['config', 'actions', 0, 'at'])['offsetS'] = 5;
        }),
        isEmpty,
      );
      // A draft case may omit testIds.
      expect(
        dh.run(
          (j) => dh.caseOf(j, 'smart')
            ..['status'] = 'draft'
            ..remove('testIds'),
        ),
        isEmpty,
      );
      // forbidMatch more specific than the expectation is fine (TG09 d).
      expect(
        dh.run(
          (j) => dh.caseOf(j, 'distance_1000')['forbidMatch'] = [
            {'event': 'alarm', 'reason': 'OVERSHOOT'},
          ],
        ),
        isEmpty,
      );
    });

    test(
      'CLI: validate --dir prints <file>:<path>: <message> and exits 1',
      () async {
        final tmp = await Directory.systemTemp.createTemp('tracegen_tg33_');
        addTearDown(() => tmp.delete(recursive: true));
        for (final e in fixturesDir.listSync().whereType<File>()) {
          e.copySync('${tmp.path}/${e.uri.pathSegments.last}');
        }
        final f = File('${tmp.path}/train_hn_dh.expect.json');
        f.writeAsStringSync(
          _mutate(f.readAsStringSync(), (j) {
            dh.caseOf(j, 'summary_unknown').remove('testIds');
            _obj(dh.caseOf(j, 'distance_1000_snooze'), [
              'config',
              'actions',
              0,
              'at',
            ])['offsetS'] = 0;
          }),
        );
        final (code, out, err) = await _cli(['validate', '--dir', tmp.path]);
        expect(code, 1, reason: out);
        final lines = err.trim().split('\n');
        final su = dh.indexOf('summary_unknown');
        final sn = dh.indexOf('distance_1000_snooze');
        expect(
          lines.where(
            (l) => RegExp(
              '^.*train_hn_dh\\.expect\\.json:cases\\[$su\\]\\.testIds: ',
            ).hasMatch(l),
          ),
          hasLength(1),
          reason: err,
        );
        expect(
          lines.where(
            (l) => RegExp(
              '^.*train_hn_dh\\.expect\\.json:cases\\[$sn\\]\\.config\\.'
              r'actions\[0\]\.at\.offsetS: run anchor in an input requires '
              r'offsetS >= sampleIntervalS \(5\)$',
            ).hasMatch(l),
          ),
          hasLength(1),
          reason: err,
        );
        expect(lines.last, '2 error(s)');
      },
    );
  });

  group('limits of validate (only check catches these)', () {
    // validate reads one fixture pair and does not re-resolve static anchors
    // from truth (spec T11 §5.2 does not ask it to). Such hand edits are
    // still caught by check (byte comparison with the generator), which CI
    // runs as fixtures_up_to_date_test.
    test(
      'static At t ≠ anchor + offsetS, window or modeAtT ≠ resolved anchor',
      () async {
        void mutate(_J j) {
          _obj(dh.caseOf(j, 'distance_1000_kill_rang'), [
            'config',
            'kill',
          ])['t'] = 31395;
          _obj(dh.caseOf(j, 'time_15'), ['expect', 1])['notBefore'] = 32835;
          // TR28 modeAt = arrival − 900 = 32890; shift every derived number
          // by one tick so the T11.1 §4 arithmetic stays self-consistent
          // (hintEstimateT does not depend on modeAtT and stays later).
          final f = dh.caseOf(j, 'time_15_kill')['expectFallback']! as _J;
          (f['window']! as _J)
            ..['modeAtT'] = 32895
            ..['estimateT'] = 32700;
          f
            ..['notBefore'] = 32400
            ..['notAfter'] = 32820;
        }

        final tmp = await Directory.systemTemp.createTemp('tracegen_tg33_');
        addTearDown(() => tmp.delete(recursive: true));
        for (final e in fixturesDir.listSync().whereType<File>()) {
          e.copySync('${tmp.path}/${e.uri.pathSegments.last}');
        }
        final f = File('${tmp.path}/train_hn_dh.expect.json');
        f.writeAsStringSync(_mutate(f.readAsStringSync(), mutate));
        final (code, _, err) = await _cli(['check', '--out', tmp.path]);
        expect(code, 1);
        expect(err, contains('differs: ${tmp.path}/train_hn_dh.expect.json'));
      },
    );
  });

  group('TG35 check catches a profile edited without generate', () {
    test('one number changed in a new profile', () async {
      final tmp = await Directory.systemTemp.createTemp('tracegen_tg35_');
      addTearDown(() => tmp.delete(recursive: true));
      // Copy data/ and edit train_longstop: dwellS 420 → 425 at Minh Lệ.
      for (final e in dataDir.listSync(recursive: true).whereType<File>()) {
        final rel = e.path.substring(dataDir.path.length + 1);
        final dst = File('${tmp.path}/data/$rel')
          ..parent.createSync(recursive: true);
        e.copySync(dst.path);
      }
      final p = File('${tmp.path}/data/profiles/train_longstop.json');
      final before = p.readAsStringSync();
      final after = before.replaceFirst('"dwellS": 420', '"dwellS": 425');
      expect(after, isNot(before), reason: 'profile layout changed');
      p.writeAsStringSync(after);

      final (code, _, err) = await _cli([
        'check',
        '--data',
        '${tmp.path}/data',
      ]);
      expect(code, 1);
      final problems = err
          .split('\n')
          .where((l) => l.startsWith('differs: '))
          .toList();
      // Only train_longstop changes (train_longstop_nospd is its own file
      // with its own dwellS).
      expect(problems, hasLength(2), reason: err);
      expect(
        problems.every((l) => l.contains('/train_longstop.')),
        isTrue,
        reason: err,
      );
      expect(err, contains('generate --all'));

      // Unchanged data: ok.
      final (okCode, okOut, _) = await _cli(['check']);
      expect(okCode, 0);
      expect(okOut, contains('ok: 30 fixture file(s) up to date'));
    });
  });

  group('TG33 known validate gap (T11 test report, finding #1)', () {
    // README §3.1/§4 and spec T11 §2.3: "overshoot" needs truth.overshoot,
    // and validate checks "đủ điều kiện tham chiếu". Fixed by T11.1 (V13).
    test('overshoot anchor on a trace without truth.overshoot', () {
      final errors = dh.run((j) {
        _obj(dh.caseOf(j, 'distance_1000'), [
          'expect',
          1,
          'window',
          'notAfter',
        ])['anchor'] = 'overshoot';
      });
      rejects(
        errors,
        'train_hn_dh.expect.json',
        'cases[${dh.indexOf('distance_1000')}].expect[1].window.notAfter.'
            'anchor',
        'overshoot',
      );
    });
  });

  _tg48();
}

/// T11.1 TG48 (tester, extends TG33): every new rule V1–V13 of T11.1 §3 on
/// hand-broken copies of the committed fixtures, through the CLI
/// `validate --dir <copy>`. Each mutation gets its own directory holding only
/// the mutated pair; the test asserts exit 1, one `<file>:<path>: <message>`
/// line per expected error (and no other), and the `N error(s)` footer.
/// Positive controls (empty expectation list) must print
/// `ok: 1 fixture pair(s) valid` and exit 0.
void _tg48() {
  final md = _Target('coach_md_tb');
  final dh = _Target('train_hn_dh');
  final ov = _Target('coach_gb_phuly_overshoot');
  final slow = _Target('bus_hn_slow');
  final sg = _Target('train_hn_dh_stopgap');
  const ks = 'distance_1000_killsweep';
  const tr22 = 'distance_1000_kill';
  const tr28 = 'time_15_kill';
  const tr29 = 'smart_kill';
  const tr35 = 'distance_1000_fallback_silenced';

  /// Full path of [rel] inside `cases[i]` of [caseId].
  String p(_Target t, String caseId, String rel) =>
      'cases[${t.indexOf(caseId)}].$rel';

  /// Committed integer at [path] inside the case (for "gives <x>").
  int orig(_Target t, String caseId, List<Object> path) =>
      _dig(t.caseOf(jsonDecode(t.text) as _J, caseId), path)! as int;

  /// Committed `expectFallback.window.<key>`.
  int win(_Target t, String caseId, String key) =>
      orig(t, caseId, ['expectFallback', 'window', key]);

  group('TG48 validate --dir rejects every T11.1 rule (V1–V13)', () {
    late Directory root;
    var n = 0;
    setUpAll(() async {
      root = await Directory.systemTemp.createTemp('tracegen_tg48_');
    });
    tearDownAll(() => root.delete(recursive: true));

    Future<void> cli(
      _Target t,
      void Function(_J j) mutate,
      List<(String, Pattern)> want,
    ) async {
      final dir = Directory('${root.path}/m${n++}')..createSync();
      File('${fixturesDir.path}/${t.id}.gpx')
          .copySync('${dir.path}/${t.id}.gpx');
      File('${dir.path}/${t.id}.expect.json')
          .writeAsStringSync(_mutate(t.text, mutate));
      final (code, out, err) = await _cli(['validate', '--dir', dir.path]);
      final reason = 'stdout:\n$out\nstderr:\n$err';
      if (want.isEmpty) {
        expect(code, 0, reason: reason);
        expect(out.trim(), 'ok: 1 fixture pair(s) valid', reason: reason);
        expect(err, isEmpty);
        return;
      }
      expect(code, 1, reason: reason);
      final lines = err.trim().split('\n').map((l) => l.trimRight()).toList();
      expect(lines.last, '${want.length} error(s)', reason: reason);
      final shape = RegExp(
        '^.*/${RegExp.escape(t.id)}'
        r'\.expect\.json:(\S+): (.+)$',
      );
      final got = <(String, String)>[];
      for (final l in lines.take(lines.length - 1)) {
        final m = shape.firstMatch(l);
        expect(m, isNotNull, reason: 'not <file>:<path>: <message>: $l');
        got.add((m!.group(1)!, m.group(2)!));
      }
      for (final (path, message) in want) {
        expect(
          got.where((g) => g.$1 == path && g.$2.contains(message)),
          hasLength(1),
          reason: 'want "$path: …$message…"\n$reason',
        );
      }
    }

    String ksAt(_Target t, String rel) => p(t, ks, 'killSweep$rel');

    // (name, target, mutation of the whole fixture, expected errors)
    final muts = <_Mut>[
      // ---- V1-V4 policyPhaseSweep
      for (final v in <Object?>['yes', 1, null, 'true'])
        (
          'V1 policyPhaseSweep ${jsonEncode(v)}',
          md,
          (j) => md.caseOf(j, 'distance_1000')['policyPhaseSweep'] = v,
          [
            (
              p(md, 'distance_1000', 'policyPhaseSweep'),
              'must be true or false',
            ),
          ],
        ),
      (
        'V1 policyPhaseSweep false is accepted',
        md,
        (j) => md.caseOf(j, 'distance_1000')['policyPhaseSweep'] = false,
        [],
      ),
      (
        'V2 policyPhaseSweep with samplingModes ["all"]',
        md,
        (j) => md.caseOf(j, 'distance_1000')
          ..['samplingModes'] = ['all']
          ..['policyPhaseSweep'] = true,
        [
          (
            p(md, 'distance_1000', 'policyPhaseSweep'),
            'policyPhaseSweep cannot be used with samplingModes ["all"]',
          ),
        ],
      ),
      (
        'V2 policyPhaseSweep with samplingModes ["policy"] is accepted',
        md,
        (j) => md.caseOf(j, 'distance_1000')
          ..['samplingModes'] = ['policy']
          ..['policyPhaseSweep'] = true,
        [],
      ),
      (
        'V2 samplingModes ["all"] without policyPhaseSweep is accepted',
        md,
        (j) => md.caseOf(j, 'distance_1000')['samplingModes'] = ['all'],
        [],
      ),
      (
        'V3 policyPhaseSweep with a second action batteryMaxSaving',
        md,
        (j) {
          final c = md.caseOf(j, 'distance_1000_permission');
          c['policyPhaseSweep'] = true;
          ((c['config']! as _J)['actions']! as List).add({
            'at': {'t': 600},
            'action': 'batteryMaxSaving',
          });
        },
        [
          (
            p(md, 'distance_1000_permission', 'policyPhaseSweep'),
            'policyPhaseSweep cannot be used with action batteryMaxSaving',
          ),
        ],
      ),
      (
        'V3 batteryMaxSaving without policyPhaseSweep is accepted',
        md,
        (j) {
          (md.caseOf(j, 'distance_1000')['config']! as _J)['actions'] = [
            {
              'at': {'t': 600},
              'action': 'batteryMaxSaving',
            },
          ];
        },
        [],
      ),
      for (final (sparse, ok) in [(182, false), (180, true), (185, true)])
        (
          'V4 policyPhaseSweep with samplingSparseIntervalS $sparse',
          md,
          (j) {
            final c = md.caseOf(j, 'distance_1000')
              ..['policyPhaseSweep'] = true;
            (c['config']! as _J)['params'] = {
              'samplingSparseIntervalS': sparse,
            };
          },
          [
            if (!ok)
              (
                p(md, 'distance_1000', 'policyPhaseSweep'),
                'policyPhaseSweep needs samplingSparseIntervalS ($sparse) '
                    'to be a multiple of sampleIntervalS (5)',
              ),
          ],
        ),
      (
        'V4 samplingSparseIntervalS 182 without policyPhaseSweep is '
            'accepted',
        md,
        (j) {
          (md.caseOf(j, 'distance_1000')['config']! as _J)['params'] = {
            'samplingSparseIntervalS': 182,
          };
        },
        [],
      ),
      (
        'V4 samplingSparseIntervalS 7.5: only the type error',
        md,
        (j) {
          final c = md.caseOf(j, 'distance_1000')..['policyPhaseSweep'] = true;
          (c['config']! as _J)['params'] = {'samplingSparseIntervalS': 7.5};
        },
        [
          (
            p(md, 'distance_1000', 'config.params.samplingSparseIntervalS'),
            'type I parameter must be a JSON integer',
          ),
        ],
      ),

      // ---- V5 killSweep keys
      for (final key in ['from', 'everyS', 'notAfter', 'earlyFrom'])
        (
          'V5 killSweep without $key',
          md,
          (j) => _obj(md.caseOf(j, ks), ['killSweep']).remove(key),
          [(ksAt(md, '.$key'), 'missing required key')],
        ),
      (
        'V5 empty killSweep',
        md,
        (j) => md.caseOf(j, ks)['killSweep'] = <String, Object?>{},
        [
          for (final key in ['from', 'everyS', 'notAfter', 'earlyFrom'])
            (ksAt(md, '.$key'), 'missing required key'),
        ],
      ),
      (
        'V5 killSweep not an object',
        md,
        (j) => md.caseOf(j, ks)['killSweep'] = true,
        [(ksAt(md, ''), 'must be an object')],
      ),
      for (final where in [
        <String>[],
        ['from'],
        ['notAfter'],
        ['earlyFrom'],
      ])
        for (final key in ['foo', if (where.isEmpty) 'ref'])
          (
            'V5 unknown key killSweep.${[...where, key].join('.')}',
            md,
            (j) => _obj(md.caseOf(j, ks), ['killSweep', ...where])[key] = 1,
            [
              (ksAt(md, '.${[...where, key].join('.')}'), 'unknown key'),
            ],
          ),

      // ---- V6 from.t >= I
      (
        'V6 killSweep.from {t: 0}',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep', 'from'])['t'] = 0,
        [(ksAt(md, '.from.t'), 'must be >= sampleIntervalS (5)')],
      ),
      (
        'V6 killSweep.from {t: 0, anchor: start}',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep'])['from'] = {
          't': 0,
          'anchor': 'start',
          'offsetS': 0,
        },
        [(ksAt(md, '.from.t'), 'must be >= sampleIntervalS (5)')],
      ),
      (
        'V6 killSweep.from {t: -5}',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep', 'from'])['t'] = -5,
        [
          (ksAt(md, '.from.t'), 'outside [0, durationS'),
          (ksAt(md, '.from.t'), 'must be >= sampleIntervalS (5)'),
        ],
      ),
      (
        'V6 killSweep.from {t: 3} (not a multiple, < I)',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep', 'from'])['t'] = 3,
        [
          (ksAt(md, '.from.t'), 'must be a multiple of sampleIntervalS (5)'),
          (ksAt(md, '.from.t'), 'must be >= sampleIntervalS (5)'),
        ],
      ),
      (
        'V6 killSweep.from {t: 5} (= I) is accepted',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep', 'from'])['t'] = 5,
        [],
      ),

      // ---- V7 everyS
      for (final (v, message) in <(Object?, String)>[
        (0, 'must be > 0'),
        (-60, 'must be > 0'),
        (62, 'must be a multiple of sampleIntervalS (5)'),
        ('60', 'must be an integer'),
        (60.5, 'must be an integer'),
        (null, 'must be an integer'),
      ])
        (
          'V7 killSweep.everyS ${jsonEncode(v)}',
          md,
          (j) => _obj(md.caseOf(j, ks), ['killSweep'])['everyS'] = v,
          [(ksAt(md, '.everyS'), message)],
        ),
      (
        'V7 killSweep.everyS 5 (= I) is accepted',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep'])['everyS'] = 5,
        [],
      ),

      // ---- V8 statsOnly
      for (final v in <Object?>['true', 1, null, 0])
        (
          'V8 killSweep.statsOnly ${jsonEncode(v)}',
          md,
          (j) => _obj(md.caseOf(j, ks), ['killSweep'])['statsOnly'] = v,
          [(ksAt(md, '.statsOnly'), 'must be true or false')],
        ),
      for (final v in [true, false])
        (
          'V8 killSweep.statsOnly $v is accepted',
          md,
          (j) => _obj(md.caseOf(j, ks), ['killSweep'])['statsOnly'] = v,
          [],
        ),

      // ---- V9 run anchors and kill in killSweep
      for (final key in ['from', 'notAfter', 'earlyFrom'])
        for (final (anchor, extra) in <(String, String?)>[
          ('event:alarm', null),
          ('event:preAlert', null),
          ('osFallbackFired', 'anchor "osFallbackFired" needs config.kill'),
          ('relaunch', 'anchor "relaunch" needs config.relaunch'),
          ('kill', 'anchor "kill" needs config.kill'),
        ])
          (
            'V9 killSweep.$key anchor $anchor',
            md,
            (j) => _obj(md.caseOf(j, ks), ['killSweep'])[key] = {
              // A static anchor keeps a t (run anchors carry none).
              if (anchor == 'kill') 't': 600,
              'anchor': anchor,
              'offsetS': 0,
            },
            [
              (
                ksAt(md, '.$key.anchor'),
                'anchor "$anchor" is not allowed in killSweep',
              ),
              if (extra != null) (ksAt(md, '.$key.anchor'), extra),
            ],
          ),
      (
        'V9 gpsGap[0] on a trace without gaps',
        md,
        (j) => _obj(md.caseOf(j, ks), ['killSweep'])['earlyFrom'] = {
          't': 600,
          'anchor': 'gpsGap[0].start',
          'offsetS': 0,
        },
        [
          (
            ksAt(md, '.earlyFrom.anchor'),
            'gap index 0 out of range (0 gap(s))',
          ),
        ],
      ),
      (
        'V9 gpsGap[0].end on the stopgap trace is accepted',
        sg,
        (j) => _obj(sg.caseOf(j, ks), ['killSweep'])['earlyFrom'] = {
          't': 35405,
          'anchor': 'gpsGap[0].end',
          'offsetS': 0,
        },
        [],
      ),

      // ---- V10 killSweep with kill / relaunch / osDismiss / osSim false
      (
        'V10 killSweep with config.kill',
        md,
        (j) => (md.caseOf(j, ks)['config']! as _J)['kill'] = {'t': 5510},
        [(ksAt(md, ''), 'killSweep cannot be used with config.kill')],
      ),
      (
        'V10 killSweep with config.kill + relaunch (reports kill once)',
        md,
        (j) => (md.caseOf(j, ks)['config']! as _J)
          ..['kill'] = {'t': 5510}
          ..['relaunch'] = {
            'at': {'t': 6110},
            'fallbackStatus': 'PENDING',
          },
        [(ksAt(md, ''), 'killSweep cannot be used with config.kill')],
      ),
      (
        'V10 killSweep with config.relaunch alone',
        md,
        (j) => (md.caseOf(j, ks)['config']! as _J)['relaunch'] = {
          'at': {'t': 6110},
          'fallbackStatus': 'PENDING',
        },
        [
          (p(md, ks, 'config.relaunch'), 'needs config.kill'),
          (ksAt(md, ''), 'killSweep cannot be used with config.relaunch'),
        ],
      ),
      (
        'V10 killSweep with config.osDismiss alone',
        md,
        (j) =>
            (md.caseOf(j, ks)['config']! as _J)['osDismiss'] = {'offsetS': 20},
        [
          (
            p(md, ks, 'config.osDismiss'),
            'needs config.relaunch with fallbackStatus auto',
          ),
          (ksAt(md, ''), 'killSweep cannot be used with config.osDismiss'),
        ],
      ),
      (
        'V10 killSweep with config.osSim false',
        md,
        (j) => (md.caseOf(j, ks)['config']! as _J)['osSim'] = false,
        [(ksAt(md, ''), 'killSweep cannot be used with config.osSim false')],
      ),
      (
        'V10 killSweep with config.osSim true is accepted',
        md,
        (j) => (md.caseOf(j, ks)['config']! as _J)['osSim'] = true,
        [],
      ),
      (
        'V10 killSweep with policyPhaseSweep is accepted (TR37 c, f, g)',
        md,
        (j) => md.caseOf(j, ks)['policyPhaseSweep'] = true,
        [],
      ),

      // ---- V11 the 12 formula parameters
      for (final (name, value) in <(String, num)>[
        ('fallbackLagS', 45),
        ('fallbackEarlyFrac', 0.3),
        ('fallbackEarlyMaxS', 1800),
        ('fallbackNearS', 300),
        ('fallbackHintSpeedFactor', 0.9),
        ('routeFactorPrior', 1.3),
        ('expectedSpeedKmhTrain', 70),
        ('expectedSpeedKmhCoach', 70),
        ('expectedSpeedKmhBus', 25),
        ('expectedSpeedKmhUnknown', 70),
        ('etaStopPenaltyS', 30),
        ('smartTargetS', 500),
      ])
        (
          'V11 TR29 with params.$name',
          md,
          (j) {
            (md.caseOf(j, tr29)['config']! as _J)['params'] = {name: value};
          },
          [
            (
              p(md, tr29, 'expectFallback'),
              'cannot be checked when params override $name',
            ),
          ],
        ),
      (
        'V11 TR29 with two formula params: one error naming both',
        md,
        (j) {
          (md.caseOf(j, tr29)['config']! as _J)['params'] = {
            'fallbackLagS': 45,
            'smartTargetS': 500,
          };
        },
        [
          (
            p(md, tr29, 'expectFallback'),
            'cannot be checked when params override fallbackLagS, '
                'smartTargetS',
          ),
        ],
      ),
      (
        'V11 TR29 with parameters outside the formula is accepted',
        md,
        (j) {
          (md.caseOf(j, tr29)['config']! as _J)['params'] = {
            'lostSpeedGuardUpdates': 3,
            'fallbackNearSlackS': 120,
          };
        },
        [],
      ),

      // ---- V12 every recomputed number, each checked on its own
      for (final (t, caseId) in [
        (md, tr29),
        (ov, tr35),
        (dh, tr22),
        (dh, tr28),
      ]) ...[
        for (final (key, delta) in [('estimateT', 5), ('hintEstimateT', -5)])
          (
            'V12 ${t.id}/$caseId window.$key ${delta > 0 ? '+' : ''}$delta',
            t,
            (j) {
              _obj(t.caseOf(j, caseId), ['expectFallback', 'window'])[key] =
                  orig(t, caseId, ['expectFallback', 'window', key]) + delta;
            },
            [
              (
                p(t, caseId, 'expectFallback.window.$key'),
                'is ${win(t, caseId, key) + delta} but T11 §5.3 gives '
                    '${win(t, caseId, key)}',
              ),
            ],
          ),
        for (final (key, delta, formula) in [
          ('notBefore', 5, 'min(estimateT, hintEstimateT) + toleranceS[0]'),
          ('notAfter', -5, 'estimateT + toleranceS[1]'),
        ])
          (
            'V12 ${t.id}/$caseId $key ${delta > 0 ? '+' : ''}$delta',
            t,
            (j) {
              _obj(t.caseOf(j, caseId), ['expectFallback'])[key] =
                  orig(t, caseId, ['expectFallback', key]) + delta;
            },
            [
              (
                p(t, caseId, 'expectFallback.$key'),
                'is ${orig(t, caseId, ['expectFallback', key]) + delta} '
                    'but $formula = '
                    '${orig(t, caseId, ['expectFallback', key])}',
              ),
            ],
          ),
        for (final (v, message) in <(Object?, String)>[
          (-1, 'must be >= 0'),
          ('17350', 'must be an integer'),
          (17350.5, 'must be an integer'),
        ])
          (
            'V12 ${t.id}/$caseId window.asOfStraightM ${jsonEncode(v)}',
            t,
            (j) {
              _obj(t.caseOf(j, caseId), [
                'expectFallback',
                'window',
              ])['asOfStraightM'] = v;
            },
            [(p(t, caseId, 'expectFallback.window.asOfStraightM'), message)],
          ),
        (
          'V12 ${t.id}/$caseId asOfT + 5',
          t,
          (j) {
            _obj(t.caseOf(j, caseId), ['expectFallback'])['asOfT'] =
                orig(t, caseId, ['expectFallback', 'asOfT']) + 5;
          },
          [
            (
              p(t, caseId, 'expectFallback.asOfT'),
              'must be killT - sampleIntervalS '
                  '(${orig(t, caseId, ['expectFallback', 'asOfT'])})',
            ),
          ],
        ),
        (
          'V12 ${t.id}/$caseId toleranceS [-295, 120]',
          t,
          (j) {
            _obj(t.caseOf(j, caseId), [
              'expectFallback',
              'window',
            ])['toleranceS'] = [
              -295,
              120,
            ];
          },
          [
            (
              p(t, caseId, 'expectFallback.notBefore'),
              'min(estimateT, hintEstimateT) + toleranceS[0] = '
                  '${orig(t, caseId, ['expectFallback', 'notBefore']) + 5}',
            ),
          ],
        ),
      ],
      // Hand-computed (T11.1 §4) from a changed sM: the lower edge must
      // follow min(estimateT, hintEstimateT).
      for (final (t, caseId, sM, hint, nb)
          in <(_Target, String, int, int, int?)>[
            // TR29 smart coach: 30000·432 ~/ 6000 = 2160; +20 −600 = 1580;
            // 1580 + 30 − 980 ~/ 4 (245) = 1365 → H 6870 > E 6590 → NB 6290.
            (md, tr29, 30000, 6870, 6290),
            // TR22 D1000 train: 19000·432 ~/ 5500 = 1492; 1492 + 30 − 223 =
            // 1299 → H 32684 < E 33303 → NB 32384.
            (dh, tr22, 20000, 32684, 32384),
            // TR22 sM 0: hT 0 → floor 600 → H 31985 → NB 31685.
            (dh, tr22, 0, 31985, 31685),
            // TR28 T15 train: 20000·432 ~/ 5500 = 1570; +20 −900 = 690;
            // 690 + 30 − 22 = 698 → H 32083 < E 32695 → NB 31783.
            (dh, tr28, 20000, 32083, 31783),
            // TR35 D1000 coach: 13288·432 ~/ 6000 = 956; 956 + 30 − 89 = 897
            // → H 2717 > E 2370 → NB unchanged.
            (ov, tr35, 14288, 2717, null),
            // TR35 sM 0: floor 600 → H 2420 > E 2370 → NB unchanged.
            (ov, tr35, 0, 2420, null),
          ])
        (
          'V12 ${t.id}/$caseId asOfStraightM $sM → hintEstimateT $hint',
          t,
          (j) {
            _obj(t.caseOf(j, caseId), [
              'expectFallback',
              'window',
            ])['asOfStraightM'] = sM;
          },
          [
            (
              p(t, caseId, 'expectFallback.window.hintEstimateT'),
              'but T11 §5.3 gives $hint',
            ),
            if (nb != null)
              (
                p(t, caseId, 'expectFallback.notBefore'),
                'min(estimateT, hintEstimateT) + toleranceS[0] = $nb',
              ),
          ],
        ),
      (
        // modeAtT + 5 moves E and the upper edge; H still sets the lower.
        'V12 coach_md_tb/smart_kill modeAtT + 5',
        md,
        (j) {
          _obj(md.caseOf(j, tr29), ['expectFallback', 'window'])['modeAtT'] =
              6715;
        },
        [
          (
            p(md, tr29, 'expectFallback.window.estimateT'),
            'is 6590 but T11 §5.3 gives 6594',
          ),
          (
            p(md, tr29, 'expectFallback.notAfter'),
            'is 6710 but estimateT + toleranceS[1] = 6714',
          ),
        ],
      ),
      (
        // Hint train 55: 17350·432 ~/ 5500 = 1362; +20 −600 = 782;
        // 782 + 30 − 45 = 767 → H 6272 → NB 5972.
        'V12 coach_md_tb/smart_kill vehicleHint train',
        md,
        (j) {
          (md.caseOf(j, tr29)['config']! as _J)['vehicleHint'] = 'train';
        },
        [
          (
            p(md, tr29, 'expectFallback.window.hintEstimateT'),
            'but T11 §5.3 gives 6272',
          ),
          (
            p(md, tr29, 'expectFallback.notBefore'),
            'min(estimateT, hintEstimateT) + toleranceS[0] = 5972',
          ),
        ],
      ),
      (
        'V12 coach_md_tb/smart_kill vehicleHint unknown (60 = coach) is '
            'accepted',
        md,
        (j) {
          (md.caseOf(j, tr29)['config']! as _J)['vehicleHint'] = 'unknown';
        },
        [],
      ),
      (
        'V12 unknown vehicleHint: input error only, no recomputation',
        md,
        (j) {
          (md.caseOf(j, tr29)['config']! as _J)['vehicleHint'] = 'plane';
        },
        [(p(md, tr29, 'config.vehicleHint'), 'unknown vehicle hint "plane"')],
      ),
      (
        // T15 → T10 changes hT only: 3079 + 20 − 600 = 2499;
        // 2499 + 30 − 474 = 2055 → H 33440 > E.
        'V12 train_hn_dh/time_15_kill thresholdMin 10',
        dh,
        (j) {
          (dh.caseOf(j, tr28)['config']! as _J)['thresholdMin'] = 10;
        },
        [
          (
            p(dh, tr28, 'expectFallback.window.hintEstimateT'),
            'but T11 §5.3 gives 33440',
          ),
        ],
      ),

      // ---- V13 anchor "overshoot" without truth.overshoot, everywhere a
      // static anchor can appear in a fixture case. With a key, the time
      // point at path.key is replaced (run anchor → static); otherwise
      // only the anchor name changes.
      for (final (t, caseId, path, key)
          in <(_Target, String, List<Object>, String?)>[
            (dh, 'distance_1000', ['expect', 0, 'window', 'notBefore'], null),
            (dh, 'distance_1000', ['expect', 1, 'window', 'notAfter'], null),
            (dh, tr22, ['expectFallback', 'window', 'modeAt'], null),
            (dh, tr22, ['config', 'kill'], null),
            (
              dh,
              'distance_1000_kill_pending',
              ['config', 'relaunch', 'at'],
              null,
            ),
            (dh, 'summary_unknown', ['config', 'actions', 0, 'at'], null),
            (dh, 'distance_1000_kill_rang', ['expectAfter', 0], 'after'),
            (dh, 'distance_1000_kill_rang', ['forbidAfter', 0], 'after'),
            (dh, ks, ['killSweep'], 'from'),
            (dh, ks, ['killSweep', 'notAfter'], null),
            (dh, ks, ['killSweep', 'earlyFrom'], null),
            (dh, 'time_15_killsweep', ['killSweep', 'earlyFrom'], null),
            (md, ks, ['killSweep', 'notAfter'], null),
            (md, tr29, ['expectFallback', 'window', 'modeAt'], null),
            (slow, ks, ['killSweep', 'earlyFrom'], null),
            (sg, ks, ['killSweep', 'notAfter'], null),
          ])
        (
          'V13 overshoot at ${t.id}/$caseId '
              '${_pathText([...path, ?key])}',
          t,
          (j) {
            final o = _obj(t.caseOf(j, caseId), path);
            if (key == null) {
              o['anchor'] = 'overshoot';
            } else {
              o[key] = {
                't': key == 'from' ? 60 : 33000,
                'anchor': 'overshoot',
                'offsetS': 0,
              };
            }
          },
          [
            (
              p(t, caseId, '${_pathText([...path, ?key])}.anchor'),
              'anchor "overshoot" needs truth.overshoot',
            ),
          ],
        ),
      (
        'V13 overshoot in killSweep on a trace with truth.overshoot is '
            'accepted',
        ov,
        (j) {
          final k = _obj(ov.caseOf(j, ks), ['killSweep']);
          _obj(k, ['notAfter'])['anchor'] = 'overshoot';
          _obj(k, ['earlyFrom'])['anchor'] = 'overshoot';
        },
        [],
      ),
    ];

    test('positive control: the committed pairs are valid', () async {
      for (final t in [md, dh, ov, slow, sg]) {
        await cli(t, (_) {}, []);
      }
    });

    for (final (name, t, mutate, want) in muts) {
      test(name, () => cli(t, mutate, want));
    }

    test(
      'one run over all 15 pairs reports every error of every file',
      () async {
        final dir = Directory('${root.path}/all')..createSync();
        for (final e in fixturesDir.listSync().whereType<File>()) {
          e.copySync('${dir.path}/${e.uri.pathSegments.last}');
        }
        final (okCode, okOut, _) = await _cli(['validate', '--dir', dir.path]);
        expect(okCode, 0);
        expect(okOut.trim(), 'ok: 15 fixture pair(s) valid');

        File('${dir.path}/coach_md_tb.expect.json').writeAsStringSync(
          _mutate(md.text, (j) {
            md.caseOf(j, 'distance_1000')
              ..['samplingModes'] = ['all']
              ..['policyPhaseSweep'] = true;
            _obj(md.caseOf(j, ks), ['killSweep'])['everyS'] = 62;
            (md.caseOf(j, tr29)['config']! as _J)['params'] = {
              'routeFactorPrior': 1.3,
            };
          }),
        );
        File('${dir.path}/train_hn_dh.expect.json').writeAsStringSync(
          _mutate(dh.text, (j) {
            _obj(dh.caseOf(j, ks), ['killSweep', 'earlyFrom'])['anchor'] =
                'overshoot';
            (dh.caseOf(j, 'time_15_killsweep')['config']! as _J)['kill'] = {
              't': 31390,
            };
          }),
        );
        final (code, out, err) = await _cli(['validate', '--dir', dir.path]);
        expect(code, 1, reason: out);
        final lines = err.trim().split('\n').map((l) => l.trimRight()).toList();
        expect(lines.last, '5 error(s)', reason: err);
        final body = lines.take(lines.length - 1).toList();
        for (final (file, count) in [('coach_md_tb', 3), ('train_hn_dh', 2)]) {
          expect(
            body.where((l) => l.contains('/$file.expect.json:')),
            hasLength(count),
            reason: err,
          );
        }
        for (final (file, path, message) in [
          (
            'coach_md_tb',
            p(md, 'distance_1000', 'policyPhaseSweep'),
            'policyPhaseSweep cannot be used with samplingModes ["all"]',
          ),
          (
            'coach_md_tb',
            ksAt(md, '.everyS'),
            'must be a multiple of sampleIntervalS (5)',
          ),
          (
            'coach_md_tb',
            p(md, tr29, 'expectFallback'),
            'cannot be checked when params override routeFactorPrior',
          ),
          (
            'train_hn_dh',
            ksAt(dh, '.earlyFrom.anchor'),
            'anchor "overshoot" needs truth.overshoot',
          ),
          (
            'train_hn_dh',
            p(dh, 'time_15_killsweep', 'killSweep'),
            'killSweep cannot be used with config.kill',
          ),
        ]) {
          expect(
            body.where(
              (l) =>
                  l.contains('/$file.expect.json:$path: ') &&
                  l.contains(message),
            ),
            hasLength(1),
            reason: 'want $file $path: $message\n$err',
          );
        }
      },
    );
  });
}

/// TG48 mutation: (name, target, mutation of the whole fixture, expected
/// `(path, message)` errors).
typedef _Mut = (String, _Target, void Function(_J j), List<(String, Pattern)>);

/// `['expect', 0, 'window']` → `expect[0].window`.
String _pathText(List<Object> path) {
  final b = StringBuffer();
  for (final k in path) {
    if (k is int) {
      b.write('[$k]');
    } else {
      if (b.isNotEmpty) {
        b.write('.');
      }
      b.write(k);
    }
  }
  return b.toString();
}
