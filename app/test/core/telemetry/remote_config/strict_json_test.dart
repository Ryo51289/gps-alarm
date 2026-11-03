// T25 §2.3: the Dart reader accepts exactly what the engine MiniJson accepts
// (T12 §7.1, C12, C15).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/remote_config/strict_json.dart';

String _nested(int depth) => '${'[' * depth}${']' * depth}';

void main() {
  test('values: object, array, string, literals, number lexemes', () {
    final v =
        parseStrictJson(
              ' \t\r\n{"a":[1,-0.0,2.5e3,true,false,null],"b":"x\\u00e9\\n"}\n ',
            )!
            as Map<String, Object?>;
    expect(v.keys, ['a', 'b']);
    expect(v['a'], [
      const JsonNumberLexeme('1'),
      const JsonNumberLexeme('-0.0'),
      const JsonNumberLexeme('2.5e3'),
      true,
      false,
      null,
    ]);
    expect(v['b'], 'x\u00e9\n');
  });

  test('duplicate key: last value, first position (C12)', () {
    final v = parseStrictJson('{"a":1,"b":2,"a":3}')! as Map<String, Object?>;
    expect(v.keys, ['a', 'b']);
    expect(v['a'], const JsonNumberLexeme('3'));
  });

  test('surrogate pairs: escaped and raw accepted', () {
    expect(parseStrictJson(r'"\ud83d\ude00"'), '\u{1F600}');
    expect(parseStrictJson('"\u{1F600}"'), '\u{1F600}');
  });

  test('depth 64 accepted, 65 rejected (C15)', () {
    expect(parseStrictJson(_nested(64)), isA<List<Object?>>());
    expect(() => parseStrictJson(_nested(65)), throwsFormatException);
    expect(
      () => parseStrictJson('{"x":${_nested(64)}}'),
      throwsFormatException,
    );
  });

  test('rejected like MiniJson', () {
    for (final s in [
      '',
      ' ',
      '\uFEFF{}',
      '\u00A0{}',
      '{} x',
      '{"a":1,}',
      '[1,]',
      '{"a":01}',
      '{"a":-}',
      '{"a":1.}',
      '{"a":.5}',
      '{"a":1e}',
      '{"a":+1}',
      '{"a":NaN}',
      '{"a":Infinity}',
      "{'a':1}",
      '{a:1}',
      '{"a" 1}',
      '"\u0001"',
      r'"\x"',
      r'"\u12"',
      r'"\ud800"',
      r'"\udc00"',
      r'"\ud800\u0041"',
      // Escaped high surrogate followed by a raw low one: MiniJson needs
      // "\u" right after the high escape.
      '"\\ud83d\ude00"',
      '"\ud800"',
      '"\udc00"',
      'tru',
      'nul',
      '"abc',
    ]) {
      expect(
        () => parseStrictJson(s),
        throwsFormatException,
        reason: s.codeUnits.toString(),
      );
    }
  });

  test('error messages never quote the input', () {
    expect(
      () => parseStrictJson('{"secretName": nope}'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(
            startsWith('json: '),
            isNot(contains('secretName')),
            isNot(contains('nope')),
          ),
        ),
      ),
    );
  });
}
