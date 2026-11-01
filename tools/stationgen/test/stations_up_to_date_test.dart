// Golden test (TC18): the committed app asset and build report must be
// byte-identical to what `build` produces on this machine. CI runs it on
// Linux against files built on Windows.
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _fix = 'cd tools/stationgen && dart run bin/stationgen.dart build';

void main() {
  final result = buildDataset(BuildInputs.read(dataDir));

  test('acceptance thresholds pass on the committed snapshot', () {
    expect(result.failures, isEmpty, reason: result.failures.join('\n'));
  });

  test('app/assets/stations.json is up to date', () {
    expect(assetFile.existsSync(), isTrue, reason: 'missing; fix: $_fix');
    final line = firstDifferentLine(
      assetFile.readAsBytesSync(),
      utf8.encode(result.stationsJson),
    );
    expect(line, isNull, reason: 'differs at line $line; fix: $_fix');
  });

  test('data/stations/BUILD_REPORT.md is up to date', () {
    final f = File('${dataDir.path}/BUILD_REPORT.md');
    expect(f.existsSync(), isTrue, reason: 'missing; fix: $_fix');
    final line = firstDifferentLine(
      f.readAsBytesSync(),
      utf8.encode(result.report),
    );
    expect(line, isNull, reason: 'differs at line $line; fix: $_fix');
  });
}
