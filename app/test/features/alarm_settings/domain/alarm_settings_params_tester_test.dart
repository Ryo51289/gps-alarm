// Tester T25: adversarial checks of the screen-3 rules that must match the
// engine bit for bit (T10 §4.7, §5; T12 C12/C15; T12 test report blank set).
//
// Every expected value in the "Kotlin-verified" groups was produced by
// running the same input through app/android/core-trip (MiniJson.parse,
// EngineParamsFactory.fromOverrides, String.isBlank, TripRules) on the JVM:
// 586 inputs + 5 256 warning-grid lines, Dart and Kotlin output identical
// (docs/test-reports/T25.md, "Đối chiếu Kotlin").
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/strict_json.dart';
import 'package:napstop/core/text/kotlin_blank.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';

const AlarmSettingsParams _d = AlarmSettingsParams.defaults;

/// The 14 values in T25 §2.3 table order, as one string.
String _line(AlarmSettingsParams p) => [
  p.shortDistanceWarnS,
  p.expectedSpeedKmhTrain,
  p.expectedSpeedKmhCoach,
  p.expectedSpeedKmhBus,
  p.expectedSpeedKmhUnknown,
  p.smartTargetS,
  p.preAlertLeadS,
  p.preAlertDistanceFactor,
  p.preAlertMinDistanceM,
  p.preAlertMinGapS,
  p.lowBatteryAlarmPct,
  p.lowBatteryEarlierPct,
  p.snoozeS,
  p.maxSnoozes,
].join(',');

const String _defaults = '240,55,60,20,60,600,1800,5,3000,300,5,15,60,1';

/// [_defaults] with the given values replaced.
String _e({
  int warnS = 240,
  int train = 55,
  int coach = 60,
  int bus = 20,
  int unknown = 60,
  int smart = 600,
  int lead = 1800,
  int factor = 5,
  int minDist = 3000,
  int minGap = 300,
  int lowAlarm = 5,
  int lowEarlier = 15,
  int snoozeS = 60,
  int maxSnoozes = 1,
}) => [
  warnS,
  train,
  coach,
  bus,
  unknown,
  smart,
  lead,
  factor,
  minDist,
  minGap,
  lowAlarm,
  lowEarlier,
  snoozeS,
  maxSnoozes,
].join(',');

String _parseResult(String s) {
  try {
    parseStrictJson(s);
    return 'OK';
  } on FormatException catch (e) {
    return e.message;
  }
}

void main() {
  group('shortDistanceWarning boundaries (T10 §4.7, U16)', () {
    test('default speeds: last warned metre per vehicle', () {
      // thr·36 < 240·speed·10. Equality (lead exactly 240 s) does NOT warn.
      const lastWarned = {
        VehicleKindMsg.train: 3666, // 3666.67
        VehicleKindMsg.coach: 3999, // 4000 → exactly 240 s
        VehicleKindMsg.bus: 1333, // 1333.33
        VehicleKindMsg.unknown: 3999,
      };
      for (final MapEntry(key: v, value: last) in lastWarned.entries) {
        for (var m = 200; m <= 10000; m++) {
          expect(
            shortDistanceWarning(m, v, _d),
            m <= last,
            reason: '${v.name} $m',
          );
        }
      }
    });

    test('slider values (multiples of 100 m): first one without warning', () {
      int firstQuiet(VehicleKindMsg v) {
        for (var m = 200; m <= 10000; m += 100) {
          if (!shortDistanceWarning(m, v, _d)) {
            return m;
          }
        }
        return -1;
      }

      expect(firstQuiet(VehicleKindMsg.train), 3700);
      expect(firstQuiet(VehicleKindMsg.coach), 4000);
      expect(firstQuiet(VehicleKindMsg.bus), 1400);
      expect(firstQuiet(VehicleKindMsg.unknown), 4000);
      // The four chips: 500 m and 1 km warn for train/coach/unknown; 2 km
      // warns for train/coach but not bus; 5 km never.
      expect(shortDistanceWarning(500, VehicleKindMsg.bus, _d), isTrue);
      expect(shortDistanceWarning(1000, VehicleKindMsg.bus, _d), isTrue);
      expect(shortDistanceWarning(2000, VehicleKindMsg.bus, _d), isFalse);
      expect(shortDistanceWarning(2000, VehicleKindMsg.train, _d), isTrue);
      for (final v in VehicleKindMsg.values) {
        expect(shortDistanceWarning(5000, v, _d), isFalse, reason: v.name);
      }
    });

    test('exact equality with overrides never warns ("ETA = ngưỡng")', () {
      // 36·thr == warnS·speed·10 → lead == warnS exactly.
      for (final (warnS, speed, thr) in const [
        (100, 36, 1000),
        (60, 6, 100), // below the slider, formula only
        (600, 150, 25000),
        (240, 60, 4000),
        (360, 10, 1000),
        (180, 120, 6000),
      ]) {
        final p = AlarmSettingsParams(
          shortDistanceWarnS: warnS,
          expectedSpeedKmhTrain: speed,
        );
        expect(
          shortDistanceWarning(thr, VehicleKindMsg.train, p),
          isFalse,
          reason: '$warnS $speed $thr',
        );
        expect(
          shortDistanceWarning(thr - 1, VehicleKindMsg.train, p),
          isTrue,
          reason: '$warnS $speed ${thr - 1}',
        );
        expect(shortDistanceLeadS(thr, speed), warnS);
      }
    });

    test('extreme params: whole slider warns / never warns', () {
      const loud = AlarmSettingsParams(
        shortDistanceWarnS: 600,
        expectedSpeedKmhBus: 150,
      );
      const quiet = AlarmSettingsParams(
        shortDistanceWarnS: 60,
        expectedSpeedKmhBus: 5,
      );
      for (var m = 200; m <= 10000; m += 100) {
        expect(shortDistanceWarning(m, VehicleKindMsg.bus, loud), isTrue);
        // 200 m at 5 km/h = 144 s ≥ 60 s.
        expect(shortDistanceWarning(m, VehicleKindMsg.bus, quiet), isFalse);
      }
    });

    test('lead shown under a warning is always < warnS (never "4 phút")', () {
      for (final warnS in const [60, 239, 240, 241, 600]) {
        for (var speed = 5; speed <= 150; speed++) {
          final p = AlarmSettingsParams(
            shortDistanceWarnS: warnS,
            expectedSpeedKmhCoach: speed,
          );
          for (var m = 200; m <= 10000; m += 100) {
            if (shortDistanceWarning(m, VehicleKindMsg.coach, p)) {
              final lead = shortDistanceLeadS(m, speed);
              expect(lead, lessThan(warnS), reason: '$warnS $speed $m');
              expect(lead, greaterThan(0));
              if (warnS == 240) {
                expect(lead ~/ 60, lessThanOrEqualTo(3));
              }
            }
          }
        }
      }
    });

    test('only integer maths: no overflow at the largest inputs', () {
      // 10 000 · 36 = 360 000; 600 · 150 · 10 = 900 000 (T25 §2.3).
      const p = AlarmSettingsParams(
        shortDistanceWarnS: 600,
        expectedSpeedKmhTrain: 150,
      );
      expect(shortDistanceWarning(10000, VehicleKindMsg.train, p), isTrue);
      expect(shortDistanceWarning(25000, VehicleKindMsg.train, p), isFalse);
      expect(shortDistanceLeadS(10000, 150), 240);
    });
  });

  group('fromOverrideJson = Kotlin fromOverrides (Kotlin-verified)', () {
    final cases = <(String, String)>[
      ('{"shortDistanceWarnS":300}', _e(warnS: 300)),
      // Duplicate key: last value is validated; invalid last → default.
      ('{"shortDistanceWarnS":100,"shortDistanceWarnS":300}', _e(warnS: 300)),
      ('{"shortDistanceWarnS":300,"shortDistanceWarnS":"x"}', _defaults),
      ('{"shortDistanceWarnS":300,"shortDistanceWarnS":59}', _defaults),
      ('{"shortDistanceWarnS":300,"shortDistanceWarnS":null}', _defaults),
      // Escaped key = same key.
      (r'{"shortDistance\u0057arnS":300}', _e(warnS: 300)),
      (
        r'{"shortDistanceWarnS":300,"shortDistance\u0057arnS":301}',
        _e(warnS: 301),
      ),
      ('{"":300,"shortDistanceWarnS ":300}', _defaults),
      // G4 after duplicate resolution.
      (
        '{"lowBatteryAlarmPct":10,"lowBatteryEarlierPct":12,'
            '"lowBatteryAlarmPct":15}',
        _defaults,
      ),
      (
        '{"lowBatteryAlarmPct":15,"lowBatteryEarlierPct":12,'
            '"lowBatteryAlarmPct":10}',
        _e(lowAlarm: 10, lowEarlier: 12),
      ),
      ('{"lowBatteryEarlierPct":5}', _defaults),
      ('{"lowBatteryEarlierPct":6}', _e(lowEarlier: 6)),
      ('{"lowBatteryAlarmPct":14}', _e(lowAlarm: 14)),
      ('{"lowBatteryAlarmPct":21,"lowBatteryEarlierPct":6}', _e(lowEarlier: 6)),
      (
        '{"lowBatteryAlarmPct":12,"lowBatteryEarlierPct":11,"snoozeS":90}',
        _e(snoozeS: 90),
      ),
      // -0 / underflow / overflow.
      ('{"preAlertMinGapS":-0}', _e(minGap: 0)),
      ('{"maxSnoozes":-0.0e-0}', _e(maxSnoozes: 0)),
      ('{"maxSnoozes":-1e-400}', _e(maxSnoozes: 0)),
      ('{"preAlertMinGapS":1e-400}', _e(minGap: 0)),
      ('{"shortDistanceWarnS":1e400}', _defaults),
      ('{"shortDistanceWarnS":-1e400}', _defaults),
      ('{"shortDistanceWarnS":1e308}', _defaults),
      ('{"maxSnoozes":9223372036854775808}', _defaults),
      // Rounding of the lexeme to the nearest double.
      ('{"shortDistanceWarnS":300.0000000000000001}', _e(warnS: 300)),
      ('{"shortDistanceWarnS":300.00000000000006}', _defaults),
      ('{"shortDistanceWarnS":299.99999999999997}', _defaults),
      ('{"shortDistanceWarnS":299.999999999999999}', _e(warnS: 300)),
      ('{"shortDistanceWarnS":59.999999999999999}', _e(warnS: 60)),
      ('{"shortDistanceWarnS":59.99999999999999}', _defaults),
      ('{"shortDistanceWarnS":600.0000000000001}', _defaults),
      ('{"shortDistanceWarnS":0.${'0' * 400}1e403}', _e(warnS: 100)),
      ('{"shortDistanceWarnS":3000e-1}', _e(warnS: 300)),
      ('{"shortDistanceWarnS":6.0E1}', _e(warnS: 60)),
      // Wrong types.
      ('{"shortDistanceWarnS":"300"}', _defaults),
      ('{"shortDistanceWarnS":[300]}', _defaults),
      ('{"shortDistanceWarnS":{"v":300}}', _defaults),
      ('{"shortDistanceWarnS":true}', _defaults),
      // Unknown engine keys and other cross groups do not touch these keys.
      (
        '{"denseEnterS":3600,"mediumEnterS":1200,"shortDistanceWarnS":300}',
        _e(warnS: 300),
      ),
      ('{"fallbackLagS":10,"shortDistanceWarnS":300}', _e(warnS: 300)),
      (
        '{"fixMaxAgeS":30,"shortDistanceWarnS":120,"expectedSpeedKmhTrain":70,'
            '"expectedSpeedKmhCoach":80,"expectedSpeedKmhBus":25,'
            '"expectedSpeedKmhUnknown":40,"smartTargetS":900,'
            '"preAlertLeadS":2400,'
            '"preAlertDistanceFactor":4,"preAlertMinDistanceM":5000,'
            '"preAlertMinGapS":0,"lowBatteryAlarmPct":8,'
            '"lowBatteryEarlierPct":20,'
            '"snoozeS":120,"maxSnoozes":3,"denseEnterS":100000}',
        _e(
          warnS: 120,
          train: 70,
          coach: 80,
          bus: 25,
          unknown: 40,
          smart: 900,
          lead: 2400,
          factor: 4,
          minDist: 5000,
          minGap: 0,
          lowAlarm: 8,
          lowEarlier: 20,
          snoozeS: 120,
          maxSnoozes: 3,
        ),
      ),
      // Malformed for the engine: every key back to default.
      ('{"shortDistanceWarnS":300}\u00A0', _defaults),
      ('\u0085{"shortDistanceWarnS":300}', _defaults),
      ('{"shortDistanceWarnS":\u000C300}', _defaults),
      (r'{"shortDistanceWarnS":300,"k":"\uD83D\u0041"}', _defaults),
      (
        '{"shortDistanceWarnS":300,"k":"\\uD83D${String.fromCharCode(0xDE00)}"}',
        _defaults,
      ),
      (
        '{"shortDistanceWarnS":300,"k":"${String.fromCharCode(0xD83D)}\\uDE00"}',
        _defaults,
      ),
      (r'{"shortDistanceWarnS":300,"k":"\ud83d\ude00"}', _e(warnS: 300)),
      ('{"shortDistanceWarnS":300,"x":${'[' * 63}${']' * 63}}', _e(warnS: 300)),
      ('{"shortDistanceWarnS":300,"x":${'[' * 64}${']' * 64}}', _defaults),
    ];
    for (final (i, (json, expected)) in cases.indexed) {
      test('case $i', () {
        expect(_line(AlarmSettingsParams.fromOverrideJson(json)), expected);
      });
    }

    test('every key: min-1 / min / max / max+1 / x.5 / max.0 / -min', () {
      // (key, position in _line, min, max, default); the battery pair is
      // covered by the G4 cases above.
      const specs = [
        ('shortDistanceWarnS', 0, 60, 600, 240),
        ('expectedSpeedKmhTrain', 1, 5, 150, 55),
        ('expectedSpeedKmhCoach', 2, 5, 150, 60),
        ('expectedSpeedKmhBus', 3, 5, 150, 20),
        ('expectedSpeedKmhUnknown', 4, 5, 150, 60),
        ('smartTargetS', 5, 300, 1200, 600),
        ('preAlertLeadS', 6, 600, 3600, 1800),
        ('preAlertDistanceFactor', 7, 2, 10, 5),
        ('preAlertMinDistanceM', 8, 1000, 10000, 3000),
        ('preAlertMinGapS', 9, 0, 900, 300),
        ('snoozeS', 12, 30, 600, 60),
        ('maxSnoozes', 13, 0, 3, 1),
      ];
      for (final (key, at, mn, mx, def) in specs) {
        int read(String v) => int.parse(
          _line(AlarmSettingsParams.fromOverrideJson('{"$key":$v}'))
              .split(',')[at],
        );

        expect(read('${mn - 1}'), def, reason: '$key min-1');
        expect(read('$mn'), mn, reason: '$key min');
        expect(read('$mx'), mx, reason: '$key max');
        expect(read('${mx + 1}'), def, reason: '$key max+1');
        expect(read('$mn.5'), def, reason: '$key min.5');
        expect(read('$mx.0'), mx, reason: '$key max.0');
        expect(read('${mn}e0'), mn, reason: '$key min e0');
        // -0 is 0, so "-min" is accepted only when min is 0.
        expect(read('-$mn'), mn == 0 ? 0 : def, reason: '$key -min');
      }
    });
  });

  group('parseStrictJson errors = MiniJson messages (Kotlin-verified)', () {
    final cases = <(String, String)>[
      ('${'[' * 64}${']' * 64}', 'OK'),
      ('${'[' * 65}${']' * 65}', 'json: too deep at 64'),
      ('${'{"a":' * 63}{}${'}' * 63}', 'OK'),
      ('${'{"a":' * 64}{}${'}' * 64}', 'json: too deep at 320'),
      ('{"x":[{"y":[${'[' * 60}${']' * 60}]}]}', 'OK'),
      ('{"x":[{"y":[${'[' * 61}${']' * 61}]}]}', 'json: too deep at 72'),
      (r'"\uD800"', 'json: lone surrogate at 6'),
      (r'"\uDC00"', 'json: lone surrogate at 6'),
      (r'"\uD83D\u0041"', 'json: lone surrogate at 6'),
      (r'"\uD83D"', 'json: lone surrogate at 6'),
      (r'"\uD83D\uDE0"', 'json: invalid unicode escape at 6'),
      ('"${String.fromCharCode(0xD800)}"', 'json: lone surrogate at 1'),
      ('"${String.fromCharCode(0xDC00)}"', 'json: lone surrogate at 1'),
      (
        '"${String.fromCharCodes([0xDE00, 0xD83D])}"',
        'json: lone surrogate at 1',
      ),
      ('"\\uD83D${String.fromCharCode(0xDE00)}"', 'json: lone surrogate at 6'),
      ('"${String.fromCharCode(0xD83D)}\\uDE00"', 'json: lone surrogate at 1'),
      ('"${String.fromCharCodes([0xD83D, 0xDE00])}"', 'OK'),
      (r'"\ud83d\ude00"', 'OK'),
      ('', 'json: unexpected end at 0'),
      ('\uFEFF{}', 'json: unexpected character at 0'),
      ('{}\u00A0', 'json: trailing content at 2'),
      ('{"a":1,}', 'json: expected key at 7'),
      ('"a\u0001"', 'json: control character in string at 2'),
      (r'"a\u0001"', 'OK'),
      (r'"\x"', 'json: invalid escape at 2'),
      ('{"a":01}', 'json: leading zero at 6'),
      ('{"a":1.}', 'json: invalid number at 7'),
      ('{"a":NaN}', 'json: unexpected character at 5'),
      ('{"a":1}}', 'json: trailing content at 7'),
    ];
    for (final (i, (s, expected)) in cases.indexed) {
      test('case $i', () => expect(_parseResult(s), expected));
    }
  });

  group('blank set = Kotlin isBlank (T12 test report)', () {
    test('blank units', () {
      for (final u in const [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0xA0, //
        0x1680, 0x2000, 0x2007, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
        0x3000,
      ]) {
        final ch = String.fromCharCode(u);
        expect(isBlankLikeKotlin('$ch$ch '), isTrue, reason: u.toString());
        expect(AlarmSettingsParams.fromOverrideJson(ch), _d);
        expect(parseEngineParamsOverride(ch), EngineParamsOverride.defaults);
      }
      expect(isBlankLikeKotlin(''), isTrue);
    });

    test('not blank: malformed → defaults / invalid', () {
      for (final u in const [
        0x00, 0x85, 0x180E, 0x200B, 0x2060, 0xFEFF, 0xFFFE, 0xD800, //
      ]) {
        final ch = String.fromCharCode(u);
        expect(isBlankLikeKotlin(ch), isFalse, reason: u.toString());
        expect(AlarmSettingsParams.fromOverrideJson(ch), _d);
        expect(parseEngineParamsOverride(ch), EngineParamsOverride.invalid);
        // Dart trim() differs from Kotlin isBlank on these: not relied upon.
      }
    });
  });

  group('parseEngineParamsOverride length (V11, UTF-16 units)', () {
    String padded(int units, {String body = '{"shortDistanceWarnS":300}'}) =>
        body + ' ' * (units - body.length);

    test('16 384 units with spaces: kept verbatim', () {
      final raw = padded(16384);
      final o = parseEngineParamsOverride(raw);
      expect(o.json, same(raw));
      expect(o.id, fnv1a32Hex(raw));
      expect(AlarmSettingsParams.fromOverrideJson(raw).shortDistanceWarnS, 300);
    });

    test('16 385 units: invalid (json null → engine defaults)', () {
      final o = parseEngineParamsOverride(padded(16385));
      expect(o, EngineParamsOverride.invalid);
      expect(o.json, isNull);
    });

    test('surrogate pairs count as 2 units', () {
      // 8 000 emoji = 16 000 units inside a string value.
      final emoji = '\u{1F600}' * 8000;
      final body = '{"x":"$emoji","shortDistanceWarnS":300}';
      final atLimit = padded(16384, body: body);
      expect(atLimit.length, 16384);
      expect(atLimit.runes.length, lessThan(16384));
      expect(parseEngineParamsOverride(atLimit).json, same(atLimit));
      expect(
        parseEngineParamsOverride(padded(16385, body: body)),
        EngineParamsOverride.invalid,
      );
    });
  });
}
