import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/nap_golden_comparator.dart';

/// Applies to every test under test/ (spec T20 section 7.2): golden
/// comparisons tolerate [kGoldenTolerance] of differing pixels.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = NapGoldenComparator(
      current.basedir.resolve('golden_test.dart'),
      tolerance: kGoldenTolerance,
    );
  }
  await testMain();
}
