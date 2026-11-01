import 'package:flutter/foundation.dart' show FlutterError, Uint8List;
import 'package:flutter_test/flutter_test.dart';

/// Share of differing pixels a golden may have and still pass (0.1%).
/// [ComparisonResult.diffPercent] is a ratio from 0 to 1 (locked by the
/// comparator test, TC41).
const double kGoldenTolerance = 0.001;

/// True when [result] passed or differs by at most [tolerance].
bool goldenWithinTolerance(ComparisonResult result, double tolerance) =>
    result.passed || result.diffPercent <= tolerance;

/// [LocalFileComparator] that accepts a small pixel difference, so goldens
/// generated on Windows also pass on CI Linux (spec T20 section 7.2).
final class NapGoldenComparator extends LocalFileComparator {
  new(super.testFile, {required this.tolerance});

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (goldenWithinTolerance(result, tolerance)) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
