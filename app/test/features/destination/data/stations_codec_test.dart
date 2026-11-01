// TC30: decoding of the station asset.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';

Map<String, Object?> doc({List<Map<String, Object?>>? stations}) => {
  'schemaVersion': 1,
  'generator': {'name': 'stationgen', 'version': '1.0.0'},
  'source': {
    'osmBase': '2026-11-01T00:00:00Z',
    'attribution': '© OpenStreetMap contributors',
    'license': 'ODbL-1.0',
    'licenseUrl': 'https://opendatacommons.org/licenses/odbl/1-0/',
    'copyrightUrl': 'https://www.openstreetmap.org/copyright',
  },
  'counts': {'train': 1, 'coach': 0, 'bus': 0},
  'stations':
      stations ??
      [
        {
          'id': 'osm:w1',
          'name': 'Ga Đồng Hới',
          'nameAscii': 'ga dong hoi',
          'kind': 'train',
          'province': 'Quảng Trị',
          'lat': 17.46892,
          'lng': 106.59973,
          'aliases': ['Đồng Hới'],
        },
      ],
};

Map<String, Object?> station([Map<String, Object?> change = const {}]) => {
  'id': 'osm:n1',
  'name': 'Bến xe A',
  'nameAscii': 'ben xe a',
  'kind': 'coach',
  'province': 'Hà Nội',
  'lat': 21,
  'lng': 105,
  'aliases': <Object?>[],
  ...change,
};

void main() {
  test('valid document', () {
    final d = decodeStationsJson(jsonEncode(doc()));
    expect(d.osmBase, '2026-11-01T00:00:00Z');
    expect(d.attribution, contains('OpenStreetMap'));
    expect(d.licenseUrl, contains('odbl'));
    final s = d.stations.single;
    expect(s.id, 'osm:w1');
    expect(s.kind, StationKind.train);
    expect(s.lat, 17.46892);
    expect(s.aliases, ['Đồng Hới']);
  });

  test('integer coordinates and missing aliases are accepted', () {
    final raw = station()..remove('aliases');
    final s = decodeStationsJson(jsonEncode(doc(stations: [raw])))
        .stations
        .single;
    expect(s.lat, 21.0);
    expect(s.aliases, isEmpty);
  });

  test('unknown fields are ignored', () {
    final d = decodeStationsJson(
      jsonEncode(
        doc(
          stations: [
            station({'importance': 3, 'ref': 'X'}),
          ],
        )..['extra'] = true,
      ),
    );
    expect(d.stations.single.name, 'Bến xe A');
  });

  for (final (label, source) in [
    ('schemaVersion 2', jsonEncode(doc()..['schemaVersion'] = 2)),
    ('missing lat', jsonEncode(doc(stations: [station()..remove('lat')]))),
    (
      'unknown kind',
      jsonEncode(
        doc(
          stations: [
            station({'kind': 'ferry'}),
          ],
        ),
      ),
    ),
    ('not JSON', '{"schemaVersion": 1,'),
    ('not an object', '[]'),
    ('missing source', jsonEncode(doc()..remove('source'))),
  ]) {
    test('rejects: $label', () {
      expect(
        () => decodeStationsJson(source),
        throwsA(isA<StationDataException>()),
      );
    });
  }
}
