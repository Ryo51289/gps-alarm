// TC41: tolerance of the golden comparator and the unit of diffPercent.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nap_golden_comparator.dart';

Future<Uint8List> _png({required bool withDot}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  if (withDot) {
    canvas.drawRect(
      const Rect.fromLTWH(3, 3, 1, 1),
      Paint()..color = const Color(0xFF000000),
    );
  }
  final image = await recorder.endRecording().toImage(10, 10);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  test('TC41 goldenWithinTolerance', () {
    expect(
      goldenWithinTolerance(
        ComparisonResult(passed: false, diffPercent: 0.0009),
        kGoldenTolerance,
      ),
      isTrue,
    );
    expect(
      goldenWithinTolerance(
        ComparisonResult(passed: false, diffPercent: 0.0011),
        kGoldenTolerance,
      ),
      isFalse,
    );
    expect(
      goldenWithinTolerance(
        ComparisonResult(passed: true, diffPercent: 0.5),
        kGoldenTolerance,
      ),
      isTrue,
    );
    expect(kGoldenTolerance, 0.001);
  });

  testWidgets('TC41 diffPercent is a 0-1 ratio (1 of 100 pixels = 0.01)', (
    tester,
  ) async {
    final result = await tester.runAsync(() async {
      // Encoding and decoding need real async work (runAsync).
      final a = await _png(withDot: false);
      final b = await _png(withDot: true);
      return await GoldenFileComparator.compareLists(a, b);
    });
    expect(result!.passed, isFalse);
    expect(result.diffPercent, closeTo(0.01, 1e-9));
    expect(goldenWithinTolerance(result, kGoldenTolerance), isFalse);
    result.dispose();
  });
}
