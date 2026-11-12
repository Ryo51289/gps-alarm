// BS-G11: fetch --dataset bus with a fake transport (no network).
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'bus_helpers.dart';
import 'fetch_test.dart' show FakeTransport;
import 'helpers.dart';

void main() {
  late Directory data;
  const busQuery = '[out:json][timeout:300];\nnode[highway=bus_stop];\nout;\n';
  const stationQuery = '[out:json];\nnode(1);\nout;\n';
  const oldRaw = '{"old": true}\n';

  setUp(() {
    data = Directory.systemTemp.createTempSync('stationgen_bus_fetch_');
    File('${data.path}/bus_query.overpassql').writeAsStringSync(busQuery);
    File('${data.path}/query.overpassql').writeAsStringSync(stationQuery);
    Directory('${data.path}/raw').createSync();
    File('${data.path}/raw/bus_overpass.json').writeAsStringSync(oldRaw);
    File('${data.path}/raw/overpass.json').writeAsStringSync(oldRaw);
  });

  tearDown(() => data.deleteSync(recursive: true));

  Future<CliRun> fetch(FakeTransport t) => runCliCaptured(
    [
      'fetch',
      '--dataset',
      'bus',
      '--endpoint',
      'https://overpass.example.test/api/interpreter',
      '--data',
      data.path,
    ],
    transport: t.call,
    clock: () => DateTime.utc(2026, 11, 7, 8, 10),
  );

  String read(String rel) => File('${data.path}/$rel').readAsStringSync();

  test(
    '200: raw/bus_* written byte for byte; station files untouched',
    () async {
      final body = utf8.encode(
        overpassJson([node(1, 21, 105.8, stopTags('Kim Mã'))]),
      );
      final t = FakeTransport(TransportResponse(status: 200, bytes: body));
      final r = await fetch(t);
      expect(r.exitCode, 0, reason: r.err);
      expect(
        File('${data.path}/raw/bus_overpass.json').readAsBytesSync(),
        body,
      );
      final meta = parseFetchMeta(read('raw/bus_fetch-meta.json'));
      expect(meta.query, busQuery);
      expect(meta.fetchedAt, '2026-11-07T08:10:00Z');
      expect(Uri.splitQueryString(t.calls.single.$3)['data'], busQuery);
      expect(read('raw/overpass.json'), oldRaw);
      expect(File('${data.path}/raw/fetch-meta.json').existsSync(), isFalse);
      expect(r.out, contains('wrote raw/bus_overpass.json'));
    },
  );

  for (final (label, response) in [
    ('HTTP 429', TransportResponse(status: 429, bytes: utf8.encode('busy'))),
    (
      '200 with remark',
      TransportResponse(
        status: 200,
        bytes: utf8.encode(overpassJson([], extra: {'remark': 'timed out'})),
      ),
    ),
    (
      '25 MB',
      TransportResponse(status: 200, bytes: List.filled(25 << 20, 0x20)),
    ),
  ]) {
    test('$label: exit 1, nothing overwritten', () async {
      final t = FakeTransport(response);
      final r = await fetch(t);
      expect(r.exitCode, 1);
      expect(t.calls, hasLength(1), reason: 'no retry');
      expect(read('raw/bus_overpass.json'), oldRaw);
      expect(
        File('${data.path}/raw/bus_fetch-meta.json').existsSync(),
        isFalse,
      );
    });
  }

  test('unknown --dataset: usage error', () async {
    final r = await runCliCaptured(
      ['fetch', '--dataset', 'tram', '--data', data.path],
      transport: FakeTransport(const TransportResponse(status: 200, bytes: []))
          .call,
    );
    expect(r.exitCode, 64);
  });

  test('missing bus_query.overpassql: exit 65', () async {
    File('${data.path}/bus_query.overpassql').deleteSync();
    final r = await fetch(
      FakeTransport(const TransportResponse(status: 200, bytes: [])),
    );
    expect(r.exitCode, 65);
  });
}
