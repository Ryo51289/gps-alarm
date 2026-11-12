// BS-G12 (no network), BS-G13 (golden: committed bus_stops.json and
// BUS_BUILD_REPORT.md), BS-G14 (build twice, B1–B4 on the real snapshot).
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'bus_helpers.dart';
import 'helpers.dart';

const String _fix = 'cd tools/stationgen && dart run bin/stationgen.dart build';

final class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('no network in build/check');
  }
}

void main() {
  final stations = buildDataset(BuildInputs.read(dataDir)).stations;
  final result = buildBusDataset(BusBuildInputs.read(dataDir), stations);

  test('B1–B4 pass on the committed snapshot', () {
    expect(result.failures, isEmpty, reason: result.failures.join('\n'));
    expect(result.provinces, ['Hà Nội', 'TP. Hồ Chí Minh']);
  });

  test('app/assets/bus_stops.json is up to date (BS-G13)', () {
    expect(busAssetFile.existsSync(), isTrue, reason: 'missing; fix: $_fix');
    final line = firstDifferentLine(
      busAssetFile.readAsBytesSync(),
      utf8.encode(result.busStopsJson),
    );
    expect(line, isNull, reason: 'differs at line $line; fix: $_fix');
  });

  test('data/stations/BUS_BUILD_REPORT.md is up to date (BS-G13)', () {
    final f = File('${dataDir.path}/BUS_BUILD_REPORT.md');
    expect(f.existsSync(), isTrue, reason: 'missing; fix: $_fix');
    final line = firstDifferentLine(
      f.readAsBytesSync(),
      utf8.encode(result.report),
    );
    expect(line, isNull, reason: 'differs at line $line; fix: $_fix');
  });

  test('a second build gives the same bytes (BS-G14)', () {
    final again = buildBusDataset(BusBuildInputs.read(dataDir), stations);
    expect(again.busStopsJson, result.busStopsJson);
    expect(again.report, result.report);
  });

  test('build and check of both datasets use no network (BS-G12)', () async {
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final guard = _NoNetwork();
    final out = '${tmp.path}/stations.json';
    final (build, check) = await HttpOverrides.runWithHttpOverrides(
      () async => (
        await runCliCaptured(['build', '--data', tmp.path, '--out', out]),
        await runCliCaptured(['check', '--data', tmp.path, '--out', out]),
      ),
      guard,
    );
    expect(build.exitCode, 0, reason: build.err);
    expect(check.exitCode, 0, reason: check.err);
    expect(check.out, contains('B1–B4 pass'));
    expect(guard.attempts, 0);
    expect(
      firstDifferentLine(
        File('${tmp.path}/bus_stops.json').readAsBytesSync(),
        busAssetFile.readAsBytesSync(),
      ),
      isNull,
    );
  });

  test('check reports a stale bus_stops.json (exit 1)', () async {
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = '${tmp.path}/stations.json';
    await runCliCaptured(['build', '--data', tmp.path, '--out', out]);
    File('${tmp.path}/bus_stops.json').writeAsStringSync('{}\n');
    final r = await runCliCaptured(['check', '--data', tmp.path, '--out', out]);
    expect(r.exitCode, 1);
    expect(r.err, contains('differs: ${tmp.path}/bus_stops.json'));
  });
}
