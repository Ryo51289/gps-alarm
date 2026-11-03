// T23 TI01 (hook of T24 TC37, docs/test-protocols/T24.md): first load of the
// station dataset and 50 searches, on a real device in profile mode:
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/station_search_perf_test.dart -d <serial>
// Results: build/integration_response_data.json (loadMs, p50Ms, p95Ms, maxMs).
// Never prints the queries.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/features/destination/data/station_repository.dart';

/// The 10 queries of the protocol, 5 times.
const List<String> _queries = [
  'dong hoi',
  'my dinh',
  'giap bat',
  'ga ha noi',
  'hue',
  'da nang',
  'sai gon',
  'nha trang',
  'vinh',
  'quy nhon',
];

double _percentile(List<double> sorted, double p) {
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TI01 load and 50 searches', (tester) async {
    late StationCatalog catalog;
    var loadMs = 0.0;
    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      catalog = await StationRepository().load();
      loadMs = watch.elapsedMicroseconds / 1000;
    });
    final times = <double>[];
    for (var round = 0; round < 5; round++) {
      for (final q in _queries) {
        final watch = Stopwatch()..start();
        final r = catalog.index.search(q);
        times.add(watch.elapsedMicroseconds / 1000);
        expect(r, isNotEmpty);
      }
    }
    times.sort();
    binding.reportData = {
      'loadMs': loadMs,
      'p50Ms': _percentile(times, 0.5),
      'p95Ms': _percentile(times, 0.95),
      'maxMs': times.last,
      'searches': times.length,
    };
    expect(times, hasLength(50));
  });
}
