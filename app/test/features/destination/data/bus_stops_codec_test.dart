// T24.3 BS-A01 (decodeBusStopsJson), BS-A02 (stations.json rejects busStop),
// BS-A04 (BusStopRepository: lazy, shared, retryable).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/data/bus_stop_repository.dart';
import 'package:napstop/features/destination/data/bus_stops_codec.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';

const String _head = '''
{
  "schemaVersion": 1,
  "generator": {"name": "stationgen", "version": "1.1.0"},
  "source": {"osmBase": "2026-11-12T01:24:05Z", "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/", "copyrightUrl": "https://www.openstreetmap.org/copyright"},
  "provinces": ["Hà Nội", "TP. Hồ Chí Minh"],
  "counts": {"Hà Nội": 2, "TP. Hồ Chí Minh": 1},
''';

String _file(List<String> rows) =>
    '$_head  "stops": [\n    ${rows.join(',\n    ')}\n  ]\n}\n';

final String _valid = _file([
  '["n123456789","Đại học Bách khoa",0,21.00512,105.84321,"03;14"]',
  '["w987654321","Công viên Thống Nhất",0,21.01711,105.84342,""]',
  '["man:tram-a","Chợ Bến Thành",1,10.772,106.698,""]',
]);

Matcher _bad() => throwsA(isA<StationDataException>());

final class _Bundle extends CachingAssetBundle {
  new({this.failFirst = 0});

  int failFirst;
  final List<(String, bool)> calls = [];

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    calls.add((key, cache));
    if (failFirst > 0) {
      failFirst--;
      return Future.error(StateError('missing'));
    }
    return Future.value(_valid);
  }

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(_valid));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeBusStopsJson (BS-A01)', () {
    test('valid file', () {
      final d = decodeBusStopsJson(_valid);
      expect(d.osmBase, '2026-11-12T01:24:05Z');
      expect(d.attribution, contains('OpenStreetMap'));
      final [a, b, c] = d.stations;
      expect(a.id, 'osm:n123456789');
      expect(a.name, 'Đại học Bách khoa');
      expect(a.nameAscii, 'dai hoc bach khoa');
      expect(a.kind, StationKind.busStop);
      expect(a.province, 'Hà Nội');
      expect(a.lat, 21.00512);
      expect(a.lng, 105.84321);
      expect(a.routeRefs, ['03', '14']);
      expect(a.aliases, isEmpty);
      expect(b.id, 'osm:w987654321');
      expect(b.routeRefs, isEmpty);
      expect(c.id, 'man:tram-a', reason: 'manual ids keep their prefix');
      expect(c.province, 'TP. Hồ Chí Minh');
      expect(c.lat, 10.772);
    });

    test('schemaVersion 2', () {
      expect(
        () => decodeBusStopsJson(
          _valid.replaceFirst('"schemaVersion": 1', '"schemaVersion": 2'),
        ),
        _bad(),
      );
    });

    test('row with a missing column', () {
      expect(
        () => decodeBusStopsJson(_file(['["n1","A",0,21.0,105.8]'])),
        _bad(),
      );
    });

    test('province index 5', () {
      expect(
        () => decodeBusStopsJson(_file(['["n1","A",5,21.0,105.8,""]'])),
        _bad(),
      );
      expect(
        () => decodeBusStopsJson(_file(['["n1","A",-1,21.0,105.8,""]'])),
        _bad(),
      );
    });

    test('lat as a string', () {
      expect(
        () => decodeBusStopsJson(_file(['["n1","A",0,"21.0",105.8,""]'])),
        _bad(),
      );
    });

    test('routes not a string', () {
      expect(
        () => decodeBusStopsJson(_file(['["n1","A",0,21.0,105.8,["03"]]'])),
        _bad(),
      );
    });

    test('other shapes', () {
      for (final s in [
        'not json',
        '[]',
        _valid.replaceFirst('"stops": [', '"stopz": ['),
        _file(['{"id": "n1"}']),
        _file(['["",  "A",0,21.0,105.8,""]']),
        _file(['[1,"A",0,21.0,105.8,""]']),
      ]) {
        expect(() => decodeBusStopsJson(s), _bad(), reason: s);
      }
    });
  });

  test('stations.json rejects kind "busStop" (BS-A02)', () {
    const station = '''
{
  "schemaVersion": 1,
  "source": {"osmBase": "x", "attribution": "© OpenStreetMap contributors", "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/"},
  "stations": [
    {"id":"osm:n1","name":"Kim Mã","nameAscii":"kim ma","kind":"busStop","province":"Hà Nội","lat":21.0,"lng":105.8,"aliases":[]}
  ]
}
''';
    expect(
      () => decodeStationsJson(station),
      throwsA(
        isA<StationDataException>().having(
          (e) => e.message,
          'message',
          contains('unknown kind'),
        ),
      ),
    );
    expect(
      decodeStationsJson(station.replaceFirst('"busStop"', '"bus"'))
          .stations
          .single
          .kind,
      StationKind.bus,
    );
  });

  group('BusStopRepository (BS-A04)', () {
    test('two concurrent loads read the asset once, cache: false', () async {
      final bundle = _Bundle();
      final repo = BusStopRepository(bundle: bundle);
      final results = await Future.wait([repo.load(), repo.load()]);
      expect(identical(results[0], results[1]), isTrue);
      expect(bundle.calls, [(kBusStopsAssetKey, false)]);
      expect(results[0].index.length, 3);
      expect(
        results[0].index.search('bach khoa').single.station.id,
        'osm:n123456789',
      );
      await repo.load();
      expect(bundle.calls, hasLength(1), reason: 'memoised');
    });

    test('a failure clears the memo; the next call succeeds', () async {
      final bundle = _Bundle(failFirst: 1);
      final repo = BusStopRepository(bundle: bundle);
      await expectLater(
        repo.load(),
        throwsA(
          isA<StationDataException>().having(
            (e) => e.message,
            'message',
            contains(kBusStopsAssetKey),
          ),
        ),
      );
      final catalog = await repo.load();
      expect(catalog.dataset.stations, hasLength(3));
      expect(bundle.calls, hasLength(2));
    });
  });
}
