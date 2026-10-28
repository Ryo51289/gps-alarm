import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';

void main() {
  group('AppFlavor.parse', () {
    const cases = <String?, AppFlavor>{
      'prod': AppFlavor.prod,
      'dev': AppFlavor.dev,
      null: AppFlavor.dev,
      '': AppFlavor.dev,
      'staging': AppFlavor.dev,
      'PROD': AppFlavor.dev,
    };

    cases.forEach((raw, expected) {
      test('maps ${raw == null ? 'null' : "'$raw'"} to $expected', () {
        expect(AppFlavor.parse(raw), expected);
      });
    });
  });
}
