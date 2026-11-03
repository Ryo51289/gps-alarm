// Tester T23: ranking regression of the T23 search against the frozen T24
// implementation (`fixtures/t24_ref/station_search_t24.dart`, HEAD copy) on
// the real asset, for every query WITHOUT a kind hint (spec §4.2: "thứ tự y
// hệt T24 trừ hai luật bỏ khoảng trắng (bước 2, 5) và chặn E ≥ 4").
//
// Corpus (deterministic, seed 23): per station the folded name, the name with
// diacritics, its core, the first core token, core prefixes, the province,
// one/two-letter typos, the core without spaces, and aliases.
//
// Invariants per query (limit: everything):
//  I1 every T24 result with score > 0 is still there, score not lower;
//  I2 a T24 result that disappeared scored <= 0 (fuzzy E >= 4);
//  I3 a new or raised result is a compact match: exact 990 / prefix 890
//     (minus 25 via an alias);
//  I4 results whose score did not change keep their T24 relative order;
//  I5 queries where nothing was raised or added give the T24 list exactly
//     (minus the <= 0 ones).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/domain/station_query.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

import '../fixtures/t24_ref/station_search_t24.dart' as t24;

const _compactScores = {990, 965, 890, 865};

String _typo(String s, Random rng, int edits) {
  final chars = s.split('');
  for (var e = 0; e < edits; e++) {
    final letters = [
      for (var i = 0; i < chars.length; i++)
        if (chars[i] != ' ') i,
    ];
    if (letters.isEmpty) {
      break;
    }
    final i = letters[rng.nextInt(letters.length)];
    chars[i] = String.fromCharCode('a'.codeUnitAt(0) + rng.nextInt(26));
  }
  return chars.join();
}

void main() {
  final catalog = buildStationCatalog(
    File('assets/stations.json').readAsStringSync(),
  );
  final stations = catalog.dataset.stations;
  final ref = t24.StationSearchIndex(stations);
  final now = catalog.index;

  Set<String> corpus() {
    final rng = Random(23);
    final out = <String>{};
    for (final s in stations) {
      final core = stationCoreTokens(s.name);
      final coreText = core.join(' ');
      out
        ..add(foldVi(s.name))
        ..add(s.name)
        ..add(coreText)
        ..add(s.province)
        ..add(foldVi(s.province))
        ..add(coreText.replaceAll(' ', ''))
        ..add(_typo(coreText, rng, 1))
        ..add(_typo(coreText, rng, 2))
        ..add(_typo(foldVi(s.name), rng, 3));
      if (core.isNotEmpty) {
        out.add(core.first);
      }
      for (var n = 2; n < coreText.length; n += 3) {
        out.add(coreText.substring(0, n));
      }
      for (final a in s.aliases) {
        out
          ..add(a)
          ..add(foldVi(a));
      }
    }
    // Queries with a kind prefix are T23's intended change: excluded.
    return {
      for (final q in out)
        if (parseStationQuery(q).kindHint == null &&
            parseStationQuery(q).tokens.isNotEmpty)
          q,
    };
  }

  test('T23 vs frozen T24: no-hint ranking only gains compact matches', () {
    final queries = corpus();
    expect(queries.length, greaterThan(3000));
    var identical = 0;
    var changed = 0;
    for (final q in queries) {
      final a = ref.search(q, limit: 100000);
      final b = now.search(q, limit: 100000);
      final scoreA = {for (final m in a) m.station.id: m.score};
      final scoreB = {for (final m in b) m.station.id: m.score};

      // I1, I2
      for (final m in a) {
        final sb = scoreB[m.station.id];
        if (sb == null) {
          expect(m.score, lessThanOrEqualTo(0), reason: '$q dropped $m');
        } else {
          expect(sb, greaterThanOrEqualTo(m.score), reason: '$q lowered $m');
        }
      }
      // I3
      final raised = <String>{};
      for (final m in b) {
        final sa = scoreA[m.station.id];
        if (sa == null || sa != m.score) {
          raised.add(m.station.id);
          expect(_compactScores, contains(m.score), reason: '$q new $m');
          expect(
            m.tier,
            anyOf(StationMatchTier.exact, StationMatchTier.prefix),
          );
        }
        expect(m.score, greaterThan(0), reason: '$q $m');
      }
      // I4
      final keptOrderA = [
        for (final m in a)
          if (scoreB[m.station.id] == m.score) m.station.id,
      ];
      final keptOrderB = [
        for (final m in b)
          if (!raised.contains(m.station.id)) m.station.id,
      ];
      expect(keptOrderB, keptOrderA, reason: q);
      // I5
      if (raised.isEmpty) {
        identical++;
        expect(b.map((m) => m.toString()).toList(), [
          for (final m in a)
            if (m.score > 0) m.toString(),
        ], reason: q);
      } else {
        changed++;
      }
    }
    // The corpus must exercise both sides.
    expect(identical, greaterThan(1000));
    expect(changed, greaterThan(50));
  });

  test('frozen copy is the T24 algorithm (TS14 baseline still matches it)', () {
    final baseline = File(
      'test/features/destination/fixtures/t24_search_baseline.json',
    ).readAsStringSync();
    for (final q in ['dong hoi', 'my dinh', 'giap bat', 'ha noi', 'vinh']) {
      expect(
        baseline,
        contains('"$q": "${ref.search(q, limit: 100)}"'),
        reason: q,
      );
    }
  });
}
