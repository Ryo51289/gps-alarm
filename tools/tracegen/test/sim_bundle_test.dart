// T18 §7: the simulation traces bundled with the app (TG60–TG62).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const List<String> _ids = [
  'train_hn_dh',
  'coach_md_tb',
  'bus_hn_brt01',
  'coach_dn_langco_tunnel',
  'coach_gb_phuly_overshoot',
  'bus_hn_brt01_noisy',
];

Future<(int, String, String)> _cli(List<String> args) async {
  final out = CapturedSink();
  final err = CapturedSink();
  final code = await runCli(
    args,
    out: out.sink,
    err: err.sink,
    workingDirectory: packageDir,
  );
  return (code, await out.text(), await err.text());
}

Future<Directory> _temp() async {
  final dir = await Directory.systemTemp.createTemp('tracegen_sim_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

List<String> _names(Directory dir) => [
  for (final e in dir.listSync())
    if (e is File) e.uri.pathSegments.last,
]..sort();

Directory get _assets => Directory('${packageDir.path}/../../app/assets/sim');

void main() {
  test('sim_bundle.json lists the six T02 traces in PRD order', () {
    final ids = parseSimBundleIds(
      File('${dataDir.path}/$kSimBundleListFile').readAsStringSync(),
    );
    expect(ids, _ids);
  });

  test('TG60 bundle-sim copies the GPX byte for byte and writes the catalog '
      'from expect.json', () async {
    final tmp = await _temp();
    File('${tmp.path}/stale.gpx').writeAsStringSync('old');
    final (code, out, err) = await _cli(['bundle-sim', '--out', tmp.path]);
    expect(code, kExitOk, reason: err);
    expect(out, contains('deleted'));
    expect(
      _names(tmp),
      [...(_ids.map((id) => '$id.gpx')), 'catalog.json']..sort(),
    );
    for (final id in _ids) {
      expect(
        File('${tmp.path}/$id.gpx').readAsBytesSync(),
        File('${fixturesDir.path}/$id.gpx').readAsBytesSync(),
        reason: id,
      );
    }
    final text = File('${tmp.path}/catalog.json').readAsStringSync();
    expect(text, endsWith('}\n'));
    expect(text, isNot(contains('\r')));
    expect(
      text,
      '${const JsonEncoder.withIndent('  ').convert(jsonDecode(text))}\n',
    );
    final catalog = jsonDecode(text) as Map<String, Object?>;
    expect(catalog.keys, ['schemaVersion', 'traces']);
    expect(catalog['schemaVersion'], 1);
    final traces = (catalog['traces']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(traces.map((t) => t['id']), _ids);
    for (final t in traces) {
      final id = t['id']! as String;
      final expectJson = jsonDecode(
        File('${fixturesDir.path}/$id.expect.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final trace = expectJson['trace']! as Map<String, Object?>;
      final dest = expectJson['destination']! as Map<String, Object?>;
      final truth = expectJson['truth']! as Map<String, Object?>;
      expect(t.keys, [
        'id',
        'gpx',
        'vehicle',
        'sampleIntervalS',
        'durationS',
        'arrivalT',
        'destination',
      ]);
      expect(t['gpx'], '$id.gpx');
      expect(t['vehicle'], trace['vehicle']);
      expect(t['sampleIntervalS'], trace['sampleIntervalS']);
      expect(t['durationS'], trace['durationS']);
      expect(t['arrivalT'], truth['arrivalT']);
      expect(t['destination'], {
        'id': dest['id'],
        if (dest['name'] != null) 'name': dest['name'],
        'lat': dest['lat'],
        'lng': dest['lng'],
      });
    }
    final train = traces.first;
    expect(train['durationS'], 33905);
    expect(train['arrivalT'], 33790);
    expect((train['destination']! as Map)['name'], 'Ga Đồng Hới');
  });

  test('TG60 a destination without a name has no name key', () {
    List<int>? read(String name) => switch (name) {
      'x.gpx' => utf8.encode('<gpx/>\n'),
      'x.expect.json' => utf8.encode(
        jsonEncode({
          'trace': {
            'id': 'x',
            'gpx': 'x.gpx',
            'vehicle': 'bus',
            'sampleIntervalS': 5,
            'durationS': 10,
          },
          'truth': {'arrivalT': 5},
          'destination': {'id': 'd', 'lat': 1.5, 'lng': 2.5},
        }),
      ),
      _ => null,
    };
    final bundle = buildSimBundle(['x'], read);
    final catalog = jsonDecode(
      utf8.decode(bundle['catalog.json']!),
    ) as Map<String, Object?>;
    final entry = (catalog['traces']! as List<Object?>).single!;
    expect((entry as Map<String, Object?>)['destination'], {
      'id': 'd',
      'lat': 1.5,
      'lng': 2.5,
    });
    expect(
      () => buildSimBundle(['y'], read),
      throwsA(
        isA<ProfileException>().having((e) => '$e', 'msg', contains('y.gpx')),
      ),
    );
    expect(
      () => parseSimBundleIds('{"ids": ["a", "a"]}'),
      throwsA(isA<ProfileException>()),
    );
    expect(
      () => parseSimBundleIds('{"ids": ["../x"]}'),
      throwsA(isA<ProfileException>()),
    );
  });

  group('TG61 check reports a changed, missing or extra bundled file', () {
    Future<Directory> copyOfAssets() async {
      final tmp = await _temp();
      for (final e in _assets.listSync().whereType<File>()) {
        e.copySync('${tmp.path}/${e.uri.pathSegments.last}');
      }
      return tmp;
    }

    test('one byte changed', () async {
      final tmp = await copyOfAssets();
      final f = File('${tmp.path}/bus_hn_brt01.gpx');
      final bytes = f.readAsBytesSync();
      bytes[bytes.length - 3] ^= 0x01;
      f.writeAsBytesSync(bytes);
      final (code, _, err) = await _cli(['check', '--sim-out', tmp.path]);
      expect(code, kExitFailed);
      expect(err, contains('differs: ${tmp.path}/bus_hn_brt01.gpx'));
      expect(err, contains('bundle-sim'));
      expect(err, isNot(contains('generate --all')));
    });

    test('a file missing', () async {
      final tmp = await copyOfAssets();
      File('${tmp.path}/catalog.json').deleteSync();
      final (code, _, err) = await _cli(['check', '--sim-out', tmp.path]);
      expect(code, kExitFailed);
      expect(err, contains('missing: ${tmp.path}/catalog.json'));
    });

    test('an extra file', () async {
      final tmp = await copyOfAssets();
      File('${tmp.path}/train_longstop.gpx').writeAsStringSync('x');
      final (code, _, err) = await _cli(['check', '--sim-out', tmp.path]);
      expect(code, kExitFailed);
      expect(err, contains('unexpected: ${tmp.path}/train_longstop.gpx'));
    });
  });

  test('TG62 check is green on the repository', () async {
    final (code, out, err) = await _cli(['check']);
    expect(code, kExitOk, reason: err);
    expect(out, contains('simulation bundle'));
  });
}
