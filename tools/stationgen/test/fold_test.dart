// TC01: Vietnamese folding against the vectors shared with the app.
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final vectors = (jsonDecode(
    File('${dataDir.path}/fold_vectors.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();

  test('shared vectors', () {
    expect(vectors.length, greaterThanOrEqualTo(30));
    for (final v in vectors) {
      expect(foldVi(v['in']! as String), v['out'], reason: '${v['in']}');
    }
  });

  test('vectors cover all 134 letters with diacritics', () {
    final covered = <int>{
      for (final v in vectors) ...(v['in']! as String).runes,
    };
    expect(kViFold.length, 134);
    expect(kViFold.keys.where(covered.contains).length, 134);
  });

  test('upper case table matches lower case table', () {
    for (final MapEntry(key: r, value: base) in kViFold.entries) {
      final c = String.fromCharCode(r);
      final lower = c.toLowerCase();
      expect(kViFold[lower.runes.single], base, reason: c);
    }
  });

  test('NFD input folds like NFC', () {
    const nfd = 'Đồng Hới';
    expect(foldVi(nfd), 'dong hoi');
    expect(foldVi('Đồng Hới'), 'dong hoi');
  });

  test('foldTokens', () {
    expect(foldTokens('  Ga   Đồng Hới '), ['ga', 'dong', 'hoi']);
    expect(foldTokens(' -- '), isEmpty);
  });
}
