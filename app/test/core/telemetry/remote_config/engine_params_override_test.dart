// T25 U22 = T29 TC16, TC17 (engine_params_override.dart created by T25).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';

void main() {
  test('TC16 parseEngineParamsOverride', () {
    expect(parseEngineParamsOverride(''), EngineParamsOverride.defaults);
    expect(parseEngineParamsOverride('  '), EngineParamsOverride.defaults);
    expect(
      parseEngineParamsOverride('{}'),
      EngineParamsOverride(json: '{}', id: fnv1a32Hex('{}')),
    );
    expect(parseEngineParamsOverride('[1]'), EngineParamsOverride.invalid);
    expect(parseEngineParamsOverride('not json'), EngineParamsOverride.invalid);
    final long = '{"a":"${'x' * (kEngineParamsMaxChars - 7)}"}';
    expect(long.length, kEngineParamsMaxChars + 1);
    expect(parseEngineParamsOverride(long), EngineParamsOverride.invalid);
    final atLimit = '{"a":"${'x' * (kEngineParamsMaxChars - 8)}"}';
    expect(atLimit.length, kEngineParamsMaxChars);
    expect(parseEngineParamsOverride(atLimit).json, atLimit);
    const raw = '{"gpsLostMinS": 60.0}';
    final o = parseEngineParamsOverride(raw);
    expect(o.json!.codeUnits, raw.codeUnits);
    expect(o.id, fnv1a32Hex(raw));
  });

  test('blank set is Kotlin isBlank; engine-malformed JSON is invalid', () {
    expect(
      parseEngineParamsOverride(' \u00A0\t\u3000\n'),
      EngineParamsOverride.defaults,
    );
    expect(parseEngineParamsOverride('\uFEFF'), EngineParamsOverride.invalid);
    expect(parseEngineParamsOverride('\u0085'), EngineParamsOverride.invalid);
    expect(
      parseEngineParamsOverride('\uFEFF{"a":1}'),
      EngineParamsOverride.invalid,
    );
    // dart:convert accepts these; the engine does not (C15).
    expect(
      parseEngineParamsOverride(r'{"a":"\ud800"}'),
      EngineParamsOverride.invalid,
    );
    expect(
      parseEngineParamsOverride('{"a":${'[' * 64}${']' * 64}}'),
      EngineParamsOverride.invalid,
    );
  });

  test('TC17 fnv1a32Hex', () {
    expect(fnv1a32Hex(''), '811c9dc5');
    expect(fnv1a32Hex('a'), 'e40c292c');
    expect(fnv1a32Hex('{}'), fnv1a32Hex('{}'));
    expect(fnv1a32Hex('{}'), hasLength(8));
    // UTF-8 bytes of U+00E9 are C3 A9: FNV-1a of those two bytes.
    var h = 0x811c9dc5;
    for (final b in [0xC3, 0xA9]) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    expect(fnv1a32Hex('é'), h.toRadixString(16).padLeft(8, '0'));
  });

  test('default reader and toString without the JSON', () {
    expect(
      const DefaultEngineParamsReader().current(),
      EngineParamsOverride.defaults,
    );
    final o = parseEngineParamsOverride('{"snoozeS":120}');
    expect(o.toString(), isNot(contains('snoozeS')));
  });
}
