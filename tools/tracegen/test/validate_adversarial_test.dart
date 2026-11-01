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
          // ---- expectFallback formula (T11 §5.3)
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
            (c) => (c['expectFallback']! as _J)['notBefore'] = 33264,
            'expectFallback.notBefore',
            'estimateT + toleranceS[0] = 33259',
          ),
          (
            'expectFallback notAfter off by one tick',
            dh,
            'time_15_kill',
            (c) => (c['expectFallback']! as _J)['notAfter'] = 32955,
            'expectFallback.notAfter',
            'estimateT + toleranceS[1] = 32950',
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
          // by one tick so the §5.3 arithmetic stays self-consistent.
          final f = dh.caseOf(j, 'time_15_kill')['expectFallback']! as _J;
          (f['window']! as _J)
            ..['modeAtT'] = 32895
            ..['estimateT'] = 32835;
          f
            ..['notBefore'] = 32535
            ..['notAfter'] = 32955;
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
    // and validate checks "đủ điều kiện tham chiếu". validate checks the
    // kill/relaunch/closest/gpsGap references but not overshoot, so this
    // hand-broken fixture is accepted (check still rejects it). Unskip once
    // validate reports it.
    test(
      'overshoot anchor on a trace without truth.overshoot',
      () {
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
      },
      skip:
          'T11 test report finding #1: validate does not check that the '
          '"overshoot" anchor needs truth.overshoot',
    );
  });
}
