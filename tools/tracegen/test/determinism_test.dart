// Determinism (TC23): same bytes on every run, and no libm transcendental
// functions or dart:math Random in lib/ (spec T02 §2 D1, D2).
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

void main() {
  final repo = ProfileRepository(dataDir);

  for (final id in repo.profileIds()) {
    test('$id generates identical bytes twice', () {
      final (p1, r1) = repo.load(id);
      final (p2, r2) = repo.load(id);
      final a = generateTrace(p1, r1);
      final b = generateTrace(p2, r2);
      expect(a.gpx, b.gpx);
      expect(a.expect, b.expect);
    });
  }

  test('lib/ uses no transcendental functions and no Random', () {
    final sources = Directory('${packageDir.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final mathImport = RegExp(r'''import\s+['"]dart:math['"]([^;]*);''');
    final forbiddenCall = RegExp(
      r'\b(sin|cos|tan|asin|acos|atan|atan2|exp|log|pow)\s*\(',
    );
    const allowed = {'max', 'min', 'sqrt'};
    var files = 0;
    for (final f in sources) {
      files++;
      final text = f.readAsStringSync();
      for (final m in mathImport.allMatches(text)) {
        final clause = m.group(1)!.trim();
        expect(
          clause.startsWith('show '),
          isTrue,
          reason: '${f.path}: dart:math must be imported with show',
        );
        final names = clause
            .substring(5)
            .split(',')
            .map((s) => s.trim())
            .toSet();
        expect(
          names.difference(allowed),
          isEmpty,
          reason: '${f.path}: dart:math may only show max, min, sqrt',
        );
      }
      expect(
        forbiddenCall.hasMatch(text),
        isFalse,
        reason: '${f.path}: transcendental call',
      );
      expect(
        RegExp(r'\bRandom\b').hasMatch(text),
        isFalse,
        reason: '${f.path}: Random',
      );
    }
    expect(files, greaterThan(10));
  });
}
