// Renders the NapStop app icon (tools/appicon/icon.svg) to the iOS AppIcon
// PNGs without any third-party tool. The shapes are hard-coded here and must
// stay in sync with icon.svg.
//
// Usage (from the repo root):
//   dart run tools/appicon/render.dart
//
// Every size listed in AppIcon.appiconset/Contents.json is rendered directly
// at its pixel size with 4x4 supersampling, as opaque RGB (App Store icons
// must not have an alpha channel).

import 'dart:io';
import 'dart:typed_data';

const _bg = [0xF5, 0xB8, 0x3D];
const _ink = [0x16, 0x18, 0x1D];
const _moon = [0xFF, 0xFF, 0xFF];

const _iconSet = 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _ss = 4;

void main() {
  final contents = File('$_iconSet/Contents.json').readAsStringSync();
  final entry = RegExp(
    r'"size"\s*:\s*"([\d.]+)x[\d.]+"[^}]*?"filename"\s*:\s*"([^"]+)"[^}]*?"scale"\s*:\s*"(\d)x"',
  );
  final bell = _bellPolygon();
  final done = <String>{};
  for (final m in entry.allMatches(contents)) {
    final file = m.group(2)!;
    if (!done.add(file)) continue;
    final px = (double.parse(m.group(1)!) * int.parse(m.group(3)!)).round();
    File('$_iconSet/$file').writeAsBytesSync(_png(px, _render(px, bell)));
    stdout.writeln('$file  ${px}x$px');
  }
  if (done.isEmpty) {
    stderr.writeln('no icon entries found in Contents.json');
    exitCode = 1;
  }
}

/// Bell outline from icon.svg, cubic segments flattened.
List<List<double>> _bellPolygon() {
  final pts = <List<double>>[];
  void cubic(List<double> p0, List<double> c1, List<double> c2, List<double> p1) {
    for (var i = 1; i <= 64; i++) {
      final t = i / 64, u = 1 - t;
      pts.add([
        u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p1[0],
        u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p1[1],
      ]);
    }
  }

  pts.add([50, 16]);
  cubic([50, 16], [34, 16], [27, 30], [27, 45]);
  pts
    ..add([27, 61])
    ..add([21, 70])
    ..add([79, 70])
    ..add([73, 61])
    ..add([73, 45]);
  cubic([73, 45], [73, 30], [66, 16], [50, 16]);
  return pts;
}

bool _inPolygon(List<List<double>> poly, double x, double y) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i][0], yi = poly[i][1], xj = poly[j][0], yj = poly[j][1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

bool _inCircle(double x, double y, double cx, double cy, double r) =>
    (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;

List<int> _sample(List<List<double>> bell, double x, double y) {
  // Painter's order, same as icon.svg.
  if (_inCircle(x, y, 56, 39, 11) && _inPolygon(bell, x, y)) return _ink;
  if (_inCircle(x, y, 49, 45, 13)) return _moon;
  if (_inCircle(x, y, 50, 79, 6) || _inPolygon(bell, x, y)) return _ink;
  return _bg;
}

Uint8List _render(int px, List<List<double>> bell) {
  final out = Uint8List(px * px * 3);
  final n = _ss * _ss;
  for (var py = 0; py < px; py++) {
    for (var qx = 0; qx < px; qx++) {
      var r = 0, g = 0, b = 0;
      for (var sy = 0; sy < _ss; sy++) {
        for (var sx = 0; sx < _ss; sx++) {
          final c = _sample(
            bell,
            (qx + (sx + 0.5) / _ss) * 100 / px,
            (py + (sy + 0.5) / _ss) * 100 / px,
          );
          r += c[0];
          g += c[1];
          b += c[2];
        }
      }
      final o = (py * px + qx) * 3;
      out[o] = (r / n).round();
      out[o + 1] = (g / n).round();
      out[o + 2] = (b / n).round();
    }
  }
  return out;
}

Uint8List _png(int px, Uint8List rgb) {
  final raw = BytesBuilder();
  for (var y = 0; y < px; y++) {
    raw
      ..addByte(0)
      ..add(Uint8List.sublistView(rgb, y * px * 3, (y + 1) * px * 3));
  }
  final ihdr = ByteData(13)
    ..setUint32(0, px)
    ..setUint32(4, px)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  final png = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_chunk('IDAT', Uint8List.fromList(ZLibEncoder(level: 9).convert(raw.takeBytes()))))
    ..add(_chunk('IEND', Uint8List(0)));
  return png.takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final body = Uint8List.fromList([...type.codeUnits, ...data]);
  final b = ByteData(8 + data.length + 4)
    ..setUint32(0, data.length);
  final bytes = b.buffer.asUint8List()..setRange(4, 4 + body.length, body);
  b.setUint32(8 + data.length, _crc32(body));
  return bytes;
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(Uint8List data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
}
