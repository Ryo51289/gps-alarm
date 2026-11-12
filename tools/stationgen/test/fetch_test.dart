// TC15: fetch with a fake transport (no network).
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class FakeTransport {
  new(this.response);

  final TransportResponse response;
  final List<(Uri, Map<String, String>, String)> calls = [];

  Future<TransportResponse> call(
    Uri endpoint,
    Map<String, String> headers,
    String body,
  ) async {
    calls.add((endpoint, headers, body));
    return response;
  }
}

void main() {
  late Directory data;
  const query = '[out:json][timeout:300];\nnode["name"="Đồng Hới"];\nout;\n';
  const oldRaw = '{"old": true}\n';

  setUp(() {
    data = Directory.systemTemp.createTempSync('stationgen_fetch_');
    File('${data.path}/query.overpassql').writeAsStringSync(query);
    Directory('${data.path}/raw').createSync();
    File('${data.path}/raw/overpass.json').writeAsStringSync(oldRaw);
  });

  tearDown(() => data.deleteSync(recursive: true));

  Future<CliRun> fetch(FakeTransport t) => runCliCaptured(
    [
      'fetch',
      '--endpoint',
      'https://overpass.example.test/api/interpreter',
      '--data',
      data.path,
    ],
    transport: t.call,
    clock: () => DateTime.utc(2026, 11, 1, 12, 30, 5, 999),
  );

  String rawNow() => File('${data.path}/raw/overpass.json').readAsStringSync();

  test('valid response is stored byte for byte', () async {
    final body = utf8.encode(
      overpassJson([
        node(1, 17.4, 106.6, {'railway': 'station', 'name': 'Đồng Hới'}),
      ]),
    );
    final t = FakeTransport(TransportResponse(status: 200, bytes: body));
    final r = await fetch(t);
    expect(r.exitCode, 0, reason: r.err);
    expect(File('${data.path}/raw/overpass.json').readAsBytesSync(), body);
    final meta = parseFetchMeta(
      File('${data.path}/raw/fetch-meta.json').readAsStringSync(),
    );
    expect(meta.query, query);
    expect(meta.osmBase, kTestOsmBase);
    expect(meta.bytes, body.length);
    expect(meta.fetchedAt, '2026-11-01T12:30:05Z');
    expect(meta.endpoint, 'https://overpass.example.test/api/interpreter');

    final (uri, headers, sent) = t.calls.single;
    expect(uri.toString(), 'https://overpass.example.test/api/interpreter');
    expect(headers['User-Agent'], startsWith('NapStop-stationgen/1.1.0'));
    expect(
      headers['Content-Type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect(sent, startsWith('data='));
    expect(Uri.splitQueryString(sent)['data'], query);
  });

  for (final (label, response) in [
    ('HTTP 429', TransportResponse(status: 429, bytes: utf8.encode('busy'))),
    ('HTTP 504', TransportResponse(status: 504, bytes: utf8.encode('busy'))),
    (
      '200 with remark',
      TransportResponse(
        status: 200,
        bytes: utf8.encode(
          overpassJson([], extra: {'remark': 'runtime error: timed out'}),
        ),
      ),
    ),
    (
      '200 not UTF-8',
      const TransportResponse(status: 200, bytes: [0xFF, 0xFE, 0x7B]),
    ),
    (
      '200 not JSON',
      TransportResponse(status: 200, bytes: utf8.encode('<html>x</html>')),
    ),
    (
      '25 MB',
      TransportResponse(status: 200, bytes: List.filled(25 << 20, 0x20)),
    ),
  ]) {
    test('$label: exit 1, previous snapshot kept', () async {
      final t = FakeTransport(response);
      final r = await fetch(t);
      expect(r.exitCode, 1);
      expect(t.calls, hasLength(1), reason: 'no retry');
      expect(rawNow(), oldRaw);
      expect(File('${data.path}/raw/fetch-meta.json').existsSync(), isFalse);
    });
  }

  test('transport exception: exit 1', () async {
    final r = await runCliCaptured(
      ['fetch', '--data', data.path],
      transport: (_, _, _) async =>
          throw const SocketException('no route to host'),
    );
    expect(r.exitCode, 1);
    expect(rawNow(), oldRaw);
  });

  test('endpoint must be https', () async {
    final r = await runCliCaptured(
      ['fetch', '--endpoint', 'http://insecure.test/api', '--data', data.path],
      transport: FakeTransport(const TransportResponse(status: 200, bytes: []))
          .call,
    );
    expect(r.exitCode, 64);
  });
}
