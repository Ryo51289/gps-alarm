// T25 U01-U07: shortDistanceWarning (T10 §4.7, U16) and the override reader
// (T10 §5 + T12 C12, bit-compatible with EngineParamsFactory.fromOverrides).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';

const AlarmSettingsParams _d = AlarmSettingsParams.defaults;

int _warnS(String json) =>
    AlarmSettingsParams.fromOverrideJson(json).shortDistanceWarnS;

void main() {
  test('U01 = T10 U16 table', () {
    final cases = <(int, VehicleKindMsg, bool)>[
      (1000, VehicleKindMsg.coach, true),
      (5000, VehicleKindMsg.coach, false),
      (4000, VehicleKindMsg.coach, false),
      (2000, VehicleKindMsg.bus, false),
      (1000, VehicleKindMsg.bus, true),
      (1333, VehicleKindMsg.bus, true),
      (1334, VehicleKindMsg.bus, false),
      (4000, VehicleKindMsg.train, false),
      (3600, VehicleKindMsg.train, true),
      (3667, VehicleKindMsg.train, false),
    ];
    for (final (m, v, expected) in cases) {
      expect(shortDistanceWarning(m, v, _d), expected, reason: '$m ${v.name}');
    }
  });

  test('U02 bounds', () {
    const slow = AlarmSettingsParams(
      shortDistanceWarnS: 60,
      expectedSpeedKmhUnknown: 5,
    );
    expect(shortDistanceWarning(200, VehicleKindMsg.unknown, slow), isFalse);
    const fast = AlarmSettingsParams(
      shortDistanceWarnS: 600,
      expectedSpeedKmhUnknown: 150,
    );
    expect(shortDistanceWarning(10000, VehicleKindMsg.unknown, fast), isTrue);
    expect(shortDistanceWarning(3999, VehicleKindMsg.unknown, _d), isTrue);
    expect(shortDistanceWarning(4000, VehicleKindMsg.unknown, _d), isFalse);
  });

  test('U03 shortDistanceLeadS rounds down', () {
    expect(shortDistanceLeadS(1000, 60), 60);
    expect(shortDistanceLeadS(1000, 55), 65);
    expect(shortDistanceLeadS(3600, 55), 235);
    expect(shortDistanceLeadS(1333, 20), 239);
    expect(shortDistanceLeadS(200, 150), 4);
  });

  test('U04 no usable object: defaults', () {
    for (final json in [null, '', 'abc', '[]', '42', '"x"', 'null']) {
      expect(AlarmSettingsParams.fromOverrideJson(json), _d, reason: json);
    }
  });

  test('U05 type I rule per key', () {
    expect(_warnS('{"shortDistanceWarnS":300}'), 300);
    expect(_warnS('{"shortDistanceWarnS":300.0}'), 300);
    expect(_warnS('{"shortDistanceWarnS":3e2}'), 300);
    expect(_warnS('{"shortDistanceWarnS":3E+2}'), 300);
    // String.toDouble() / double.parse both round this lexeme to 300.0.
    expect(_warnS('{"shortDistanceWarnS":300.0000000000000001}'), 300);
    for (final v in [
      '300.5',
      '"300"',
      'true',
      'null',
      '59',
      '601',
      '1e300',
      '1e400',
      '-1e400',
      '[300]',
      '{"v":300}',
    ]) {
      expect(_warnS('{"shortDistanceWarnS":$v}'), 240, reason: v);
    }
    expect(_warnS('{"shortDistanceWarnS":60}'), 60);
    expect(_warnS('{"shortDistanceWarnS":600}'), 600);
    expect(AlarmSettingsParams.fromOverrideJson('{"foo":1,"bar":"x"}'), _d);
    final zero = AlarmSettingsParams.fromOverrideJson(
      '{"preAlertMinGapS":-0.0}',
    );
    expect(zero.preAlertMinGapS, 0);
    expect(zero.preAlertMinGapS.isNegative, isFalse);
    expect(
      AlarmSettingsParams.fromOverrideJson('{"preAlertMinGapS":-0}')
          .preAlertMinGapS,
      0,
    );
  });

  test('U05 every key is read with its own range', () {
    final p = AlarmSettingsParams.fromOverrideJson(
      '''
{"shortDistanceWarnS":120,"expectedSpeedKmhTrain":70,
 "expectedSpeedKmhCoach":80,"expectedSpeedKmhBus":25,
 "expectedSpeedKmhUnknown":40,"smartTargetS":900,"preAlertLeadS":2400,
 "preAlertDistanceFactor":3,"preAlertMinDistanceM":2000,"preAlertMinGapS":600,
 "lowBatteryAlarmPct":8,"lowBatteryEarlierPct":20,"snoozeS":90,"maxSnoozes":2}''',
    );
    expect(p.shortDistanceWarnS, 120);
    expect(p.expectedSpeedKmh(VehicleKindMsg.train), 70);
    expect(p.expectedSpeedKmh(VehicleKindMsg.coach), 80);
    expect(p.expectedSpeedKmh(VehicleKindMsg.bus), 25);
    expect(p.expectedSpeedKmh(VehicleKindMsg.unknown), 40);
    expect(p.smartTargetS, 900);
    expect(p.preAlertLeadS, 2400);
    expect(p.preAlertDistanceFactor, 3);
    expect(p.preAlertMinDistanceM, 2000);
    expect(p.preAlertMinGapS, 600);
    expect(p.lowBatteryAlarmPct, 8);
    expect(p.lowBatteryEarlierPct, 20);
    expect(p.snoozeS, 90);
    expect(p.maxSnoozes, 2);
    final out = AlarmSettingsParams.fromOverrideJson('''
{"expectedSpeedKmhTrain":4,"expectedSpeedKmhCoach":151,"smartTargetS":299,
 "preAlertLeadS":3601,"preAlertDistanceFactor":1,"preAlertMinDistanceM":10001,
 "preAlertMinGapS":901,"snoozeS":29,"maxSnoozes":4}''');
    expect(out, _d);
  });

  test('U06 G4 cross check of the battery thresholds', () {
    AlarmSettingsParams p(String json) =>
        AlarmSettingsParams.fromOverrideJson(json);
    final a = p('{"lowBatteryAlarmPct":15}');
    expect((a.lowBatteryAlarmPct, a.lowBatteryEarlierPct), (5, 15));
    final b = p('{"lowBatteryAlarmPct":10,"lowBatteryEarlierPct":12}');
    expect((b.lowBatteryAlarmPct, b.lowBatteryEarlierPct), (10, 12));
    final c = p('{"lowBatteryAlarmPct":10,"lowBatteryEarlierPct":4}');
    expect((c.lowBatteryAlarmPct, c.lowBatteryEarlierPct), (10, 15));
    final d = p('{"lowBatteryEarlierPct":5}');
    expect((d.lowBatteryAlarmPct, d.lowBatteryEarlierPct), (5, 15));
  });

  test('U07 override changes the warning', () {
    final p = AlarmSettingsParams.fromOverrideJson(
      '{"expectedSpeedKmhBus":30,"shortDistanceWarnS":300}',
    );
    expect(shortDistanceWarning(2400, VehicleKindMsg.bus, p), isTrue);
    expect(shortDistanceWarning(2500, VehicleKindMsg.bus, p), isFalse);
  });

  test('C12/C15: same as the engine on edge strings', () {
    const valid = '{"shortDistanceWarnS":300}';
    // Duplicate key: the last value is checked.
    expect(_warnS('{"shortDistanceWarnS":100,"shortDistanceWarnS":700}'), 240);
    expect(_warnS('{"shortDistanceWarnS":700,"shortDistanceWarnS":100}'), 100);
    // RFC whitespace around the object is fine.
    expect(_warnS(' \t\r\n$valid\n '), 300);
    // Anything the engine treats as malformed: every key back to default.
    for (final json in [
      '\uFEFF$valid',
      '\u00A0$valid',
      '\u3000$valid',
      '\u2028$valid',
      '{"shortDistanceWarnS":300,}',
      '{"shortDistanceWarnS":0300}',
      r'{"shortDistanceWarnS":300,"x":"\ud800"}',
      '{"shortDistanceWarnS":300,"x":"\ud800"}',
      '{"shortDistanceWarnS":300,"x":${'[' * 64}${']' * 64}}',
    ]) {
      expect(_warnS(json), 240, reason: json.codeUnits.take(8).toString());
    }
    // Depth 64 in total is still accepted.
    expect(
      _warnS('{"shortDistanceWarnS":300,"x":${'[' * 63}${']' * 63}}'),
      300,
    );
    // Blank (Kotlin isBlank): defaults.
    expect(AlarmSettingsParams.fromOverrideJson(' \u00A0\u3000\n'), _d);
  });

  test('toString hides values', () {
    expect(_d.toString(), isNot(contains('240')));
  });
}
