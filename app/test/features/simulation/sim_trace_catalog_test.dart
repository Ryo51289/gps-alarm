import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

/// T18 SM40–SM42: catalog of the bundled simulation traces.
void main() {
  Map<String, Object?> entry({
    String id = 'train_hn_dh',
    String vehicle = 'train',
    Map<String, Object?>? destination,
  }) => {
    'id': id,
    'gpx': '$id.gpx',
    'vehicle': vehicle,
    'sampleIntervalS': 5,
    'durationS': 33905,
    'arrivalT': 33790,
    'destination':
        destination ??
        {
          'id': 'ga_dong_hoi',
          'name': 'Ga Đồng Hới',
          'lat': 17.4689199,
          'lng': 106.5997285,
        },
  };

  String doc(List<Map<String, Object?>> traces, {int version = 1}) =>
      jsonEncode({'schemaVersion': version, 'traces': traces});

  Matcher formatError(String key) => throwsA(
    isA<FormatException>()
        .having((e) => e.message, 'message', contains(key))
        .having((e) => e.message, 'message', isNot(contains('17.4'))),
  );

  final assetFile = File('assets/sim/catalog.json');

  group('SM40 parseSimTraceCatalog', () {
    test('parses the six bundled traces', () {
      final c = parseSimTraceCatalog(assetFile.readAsStringSync());
      expect(c.traces, hasLength(6));
      final train = c.byId(SimTraces.trainHnDh)!;
      expect(train.vehicle, VehicleKindMsg.train);
      expect(train.sampleIntervalS, 5);
      expect(train.durationS, 33905);
      expect(train.arrivalT, 33790);
      expect(train.destination.id, 'ga_dong_hoi');
      expect(train.destination.name, 'Ga Đồng Hới');
      expect(train.destination.lat, closeTo(17.4689199, 1e-9));
      expect(train.destination.lng, closeTo(106.5997285, 1e-9));
      expect(c.byId(SimTraces.busHnBrt01)!.vehicle, VehicleKindMsg.bus);
      expect(c.byId('nope'), isNull);
    });

    test('a destination without a name and integer coordinates', () {
      final c = parseSimTraceCatalog(
        doc([
          entry(destination: {'id': 'x', 'lat': 17, 'lng': 106}),
        ]),
      );
      expect(c.traces.single.destination.name, isNull);
      expect(c.traces.single.destination.lat, 17.0);
    });

    test('rejects what it cannot read, naming the key only', () {
      expect(
        () => parseSimTraceCatalog(doc([entry()], version: 2)),
        formatError('schemaVersion'),
      );
      expect(
        () => parseSimTraceCatalog(
          doc([
            entry(destination: {'id': 'ga_dong_hoi', 'lng': 106.5997285}),
          ]),
        ),
        formatError('traces[0].destination.lat'),
      );
      expect(
        () => parseSimTraceCatalog(doc([entry(), entry()])),
        formatError('traces[1].id duplicate'),
      );
      expect(
        () => parseSimTraceCatalog(doc([entry(vehicle: 'boat')])),
        formatError('traces[0].vehicle'),
      );
      expect(
        () => parseSimTraceCatalog(doc([entry(id: '../x')])),
        formatError('traces[0].id'),
      );
      expect(
        () => parseSimTraceCatalog('{"schemaVersion": 1}'),
        formatError('traces'),
      );
      expect(() => parseSimTraceCatalog('['), formatError('invalid JSON'));
      final wrongType = entry()..['durationS'] = '33905';
      expect(
        () => parseSimTraceCatalog(doc([wrongType])),
        formatError('traces[0].durationS'),
      );
    });

    test('loadSimTraceCatalog reads the asset through a bundle', () async {
      final c = await loadSimTraceCatalog(_FileBundle());
      expect(c.traces.map((t) => t.id), SimTraces.all);
    });
  });

  test('SM41 the bundled catalog lists SimTraces.all in order and every '
      'gpx exists', () {
    final raw =
        jsonDecode(assetFile.readAsStringSync()) as Map<String, Object?>;
    final traces = (raw['traces']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(traces.map((t) => t['id']), SimTraces.all);
    for (final t in traces) {
      expect(
        File('assets/sim/${t['gpx']}').existsSync(),
        isTrue,
        reason: '${t['gpx']}',
      );
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sim/'));
  });

  test('SM42 toString has no coordinates', () {
    const d = SimDestination(
      id: 'ga_dong_hoi',
      name: 'Ga Đồng Hới',
      lat: 17.4689199,
      lng: 106.5997285,
    );
    const t = SimTrace(
      id: 'train_hn_dh',
      vehicle: VehicleKindMsg.train,
      sampleIntervalS: 5,
      durationS: 33905,
      arrivalT: 33790,
      destination: d,
    );
    for (final s in ['$d', '$t']) {
      expect(s, isNot(contains('17.46')));
      expect(s, isNot(contains('106.59')));
    }
    expect('$d', contains('ga_dong_hoi'));
    expect('$t', contains('train_hn_dh'));
  });
}

/// Reads assets from the app directory (flutter test runs in app/).
final class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}
