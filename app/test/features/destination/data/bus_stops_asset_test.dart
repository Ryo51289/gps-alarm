// T24.3 BS-A03 (asset sanity), BS-P01 (bucketed index ≡ full scan without
// the substring tier), BS-P02 (performance, T24 TC34) on the real
// assets/bus_stops.json.
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/bus_stop_repository.dart';
import 'package:napstop/features/destination/data/bus_stops_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// Swaps two adjacent letters of [s] at a random place.
String _swap(String s, Random rng) {
  if (s.length < 3) {
    return s;
  }
  final i = 1 + rng.nextInt(s.length - 2);
  final c = s.split('');
  final t = c[i];
  c[i] = c[i - 1];
  c[i - 1] = t;
  return c.join();
}

/// Mixed queries from the real names (seeded, deterministic).
List<String> _queries(List<Station> stops, int n, int seed) {
  final rng = Random(seed);
  final out = <String>[];
  while (out.length < n) {
    final s = stops[rng.nextInt(stops.length)];
    final folded = foldVi(s.name);
    final tokens = stationCoreTokens(s.name);
    if (tokens.isEmpty) {
      continue;
    }
    switch (out.length % 6) {
      case 0:
        out.add(folded);
      case 1:
        // Typed halfway.
        out.add(folded.substring(0, max(2, folded.length ~/ 2)));
      case 2:
        out.add(_swap(folded, rng));
      case 3:
        out.add(tokens.length >= 2 ? '${tokens[1]} ${tokens[0]}' : tokens[0]);
      case 4:
        out.add('${tokens.last} ${foldVi(s.province)}');
      case 5:
        out.add(rng.nextBool() ? 'xqz${rng.nextInt(99)}' : s.name);
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationDataset dataset;

  setUpAll(() async {
    final text = await rootBundle.loadString(kBusStopsAssetKey, cache: false);
    dataset = decodeBusStopsJson(text);
  });

  group('asset (BS-A03)', () {
    test('schema, counts per city, attribution', () {
      final perProvince = <String, int>{};
      for (final s in dataset.stations) {
        perProvince[s.province] = (perProvince[s.province] ?? 0) + 1;
      }
      expect(perProvince.keys, unorderedEquals(['Hà Nội', 'TP. Hồ Chí Minh']));
      for (final n in perProvince.values) {
        expect(n, greaterThanOrEqualTo(2000));
      }
      expect(dataset.stations.length, lessThanOrEqualTo(15000));
      expect(dataset.attribution, contains('OpenStreetMap'));
      expect(dataset.licenseUrl, contains('odbl'));
      expect(
        File('assets/bus_stops.json').lengthSync(),
        lessThanOrEqualTo(900000),
      );
    });

    test('ids unique, kind busStop, coordinates in Viet Nam, routes D7', () {
      final ids = <String>{};
      for (final s in dataset.stations) {
        expect(ids.add(s.id), isTrue, reason: 'duplicate ${s.id}');
        expect(s.id, startsWith('osm:'));
        expect(s.kind, StationKind.busStop);
        expect(s.nameAscii, foldVi(s.name));
        expect(s.name.runes.length, inInclusiveRange(1, 120), reason: s.id);
        expect(s.lat, inInclusiveRange(8.0, 23.5), reason: s.id);
        expect(s.lng, inInclusiveRange(102.0, 110.0), reason: s.id);
        expect(s.routeRefs.length, lessThanOrEqualTo(6), reason: s.id);
        expect(s.routeRefs.toSet().length, s.routeRefs.length, reason: s.id);
        for (final r in s.routeRefs) {
          expect(r.runes.length, inInclusiveRange(1, 8), reason: s.id);
        }
      }
    });
  });

  test('bucketed index gives the same results as a full scan (BS-P01)', () {
    final bucketed = StationSearchIndex(
      dataset.stations,
      bucketByFirstChar: true,
      substringTier: false,
    );
    final full = StationSearchIndex(dataset.stations, substringTier: false);
    final queries = _queries(dataset.stations, 1000, 243);
    var nonEmpty = 0;
    for (final (i, q) in queries.indexed) {
      final hint = i.isEven ? null : StationKind.busStop;
      final a = bucketed.search(q, limit: 100, kindHint: hint);
      final b = full.search(q, limit: 100, kindHint: hint);
      expect(a.toString(), b.toString(), reason: q);
      if (a.isNotEmpty) {
        nonEmpty++;
      }
    }
    expect(nonEmpty, greaterThan(800), reason: 'the corpus finds things');
  });

  test('performance (BS-P02): build < 400 ms, mean query < 5 ms', () {
    final build = Stopwatch()..start();
    final index = StationSearchIndex(
      dataset.stations,
      bucketByFirstChar: true,
      substringTier: false,
    );
    build.stop();
    final queries = _queries(dataset.stations, 500, 7);
    // Warm-up (JIT), then measure.
    for (final q in queries.take(50)) {
      index.search(q, limit: 60);
    }
    final run = Stopwatch()..start();
    for (final q in queries) {
      index.search(q, limit: 60, kindHint: StationKind.busStop);
    }
    run.stop();
    final meanMs = run.elapsedMicroseconds / queries.length / 1000;
    // Numbers for the Implementation notes (BS-P02).
    printOnFailure(
      'bus index: build ${build.elapsedMilliseconds} ms, '
      'mean ${meanMs.toStringAsFixed(3)} ms over ${queries.length} queries',
    );
    // Review T24.3 #5: shared CI runners (CI=true) get 4x the margin so a
    // slow or busy runner does not flake; locally the spec thresholds hold.
    final slack = Platform.environment['CI'] == 'true' ? 4 : 1;
    expect(build.elapsedMilliseconds, lessThan(400 * slack));
    expect(meanMs, lessThan(5 * slack));
  });
}
