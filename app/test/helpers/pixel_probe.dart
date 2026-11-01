import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Key of the `RepaintBoundary` that [pixelAt] reads.
const ValueKey<String> kPixelProbeKey = ValueKey('pixel-probe');

/// Color of the pixel at the global [position] inside the RepaintBoundary
/// keyed [kPixelProbeKey], as painted (device pixel ratio 1).
Future<Color> pixelAt(WidgetTester tester, Offset position) async {
  final finder = find.byKey(kPixelProbeKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final local = position - tester.getTopLeft(finder);
  final argb = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    final i = (local.dy.floor() * width + local.dx.floor()) * 4;
    final (r, g, b, a) = (
      bytes!.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
      bytes.getUint8(i + 3),
    );
    return (a << 24) | (r << 16) | (g << 8) | b;
  });
  return Color(argb!);
}
