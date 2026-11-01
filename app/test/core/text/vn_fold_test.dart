// TC20: the app's foldVi runs the vectors shared with tools/stationgen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';

void main() {
  final vectors = (jsonDecode(
    File('../data/stations/fold_vectors.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();

  test('shared fold vectors', () {
    expect(vectors, isNotEmpty);
    for (final v in vectors) {
      expect(foldVi(v['in']! as String), v['out'], reason: '${v['in']}');
    }
  });

  test('table has 67 lower + 67 upper case letters', () {
    expect(kViFold.length, 134);
  });

  test('NFD and NFC fold the same way', () {
    expect(foldVi('Đồng Hới'), 'dong hoi');
    expect(foldVi('ĐỒNG HỚI'), 'dong hoi');
  });

  test('foldTokens', () {
    expect(foldTokens('Bến xe   Mỹ Đình'), ['ben', 'xe', 'my', 'dinh']);
    expect(foldTokens('  '), isEmpty);
  });
}
