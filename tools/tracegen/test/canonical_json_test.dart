// -0.0 must stay a double literal here.
// ignore_for_file: prefer_int_literals

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

void main() {
  group('canonicalJson (TC17)', () {
    test('writes the exact canonical layout', () {
      final text = canonicalJson({
        'name': 'Ga Đồng Hới → "x"\\\n\u0001',
        'lat': const Fixed(21.0242144, 7),
        'neg': const Fixed(-0.0, 2),
        'count': 3,
        'ok': true,
        'none': null,
        'emptyList': <Object?>[],
        'emptyMap': <String, Object?>{},
        'list': [
          1,
          {'a': false},
          <Object?>[],
        ],
      });
      const expected =
          '{\n'
          '  "name": "Ga Đồng Hới → \\"x\\"\\\\\\n\\u0001",\n'
          '  "lat": 21.0242144,\n'
          '  "neg": 0.00,\n'
          '  "count": 3,\n'
          '  "ok": true,\n'
          '  "none": null,\n'
          '  "emptyList": [],\n'
          '  "emptyMap": {},\n'
          '  "list": [\n'
          '    1,\n'
          '    {\n'
          '      "a": false\n'
          '    },\n'
          '    []\n'
          '  ]\n'
          '}\n';
      expect(text, expected);
      expect(text.contains('\r'), isFalse);
    });

    test('escapes control characters', () {
      expect(canonicalJson('\b\f\r\t\u001f/'), '"\\b\\f\\r\\t\\u001f/"\n');
    });

    test('rejects plain doubles', () {
      expect(() => canonicalJson({'x': 1.5}), throwsArgumentError);
    });
  });
}
