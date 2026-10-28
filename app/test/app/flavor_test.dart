import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';

/// Set by CI:
/// `flutter test [--flavor prod] --dart-define=NAPSTOP_EXPECT_FLAVOR=<flavor>`
/// where `<flavor>` is `dev` or `prod`.
/// Empty when running plain `flutter test` locally, so the check is skipped.
const String _expectedFlavor = String.fromEnvironment('NAPSTOP_EXPECT_FLAVOR');

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

  group('AppFlavor.current', () {
    test(
      'matches the --flavor of this test run',
      () {
        // Compare the raw flavor first: AppFlavor.parse maps null/unknown to
        // dev, so only the raw value proves pubspec default-flavor is dev.
        expect(appFlavor, _expectedFlavor);
        expect(AppFlavor.current.name, _expectedFlavor);
      },
      skip: _expectedFlavor.isEmpty ? 'NAPSTOP_EXPECT_FLAVOR is not set' : null,
    );
  });
}
