// BS-G07: byte format of bus_stops.json.
import 'dart:convert';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'bus_helpers.dart';
import 'helpers.dart';

const String _golden = r'''
{
  "schemaVersion": 1,
  "generator": {"name": "stationgen", "version": "1.1.0"},
  "source": {"osmBase": "2026-11-01T00:00:00Z", "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/", "copyrightUrl": "https://www.openstreetmap.org/copyright"},
  "provinces": ["Hà Nội", "TP. Hồ Chí Minh"],
  "counts": {"Hà Nội": 2, "TP. Hồ Chí Minh": 1},
  "stops": [
    ["w987654321","Công viên \"Thống Nhất\"",0,21.01711,105.84342,""],
    ["n123456789","Đại học Bách khoa",0,21.00512,105.84321,"03;14"],
    ["n5","Chợ Bến Thành",1,10.77200,106.69800,"01"]
  ]
}
''';

void main() {
  final provinces = realProvinces().names;
  final stops = [
    busStop(
      'n5',
      'Chợ Bến Thành',
      province: 'TP. Hồ Chí Minh',
      lat: 10.772,
      lng: 106.698,
      routes: ['01'],
    ),
    busStop(
      'n123456789',
      'Đại học Bách khoa',
      lat: 21.005124,
      lng: 105.843206,
      routes: ['03', '14'],
    ),
    busStop(
      'w987654321',
      'Công viên "Thống Nhất"',
      lat: 21.01711,
      lng: 105.84342,
    ),
  ];

  test('matches the golden bytes', () {
    final text = encodeBusStopsJson(
      osmBase: kTestOsmBase,
      stops: stops,
      provinceOrder: provinces,
    );
    expect(text, _golden);
    expect(text.contains('\r'), isFalse);
    final json = jsonDecode(text) as Map<String, Object?>;
    expect(json.keys, [
      'schemaVersion',
      'generator',
      'source',
      'provinces',
      'counts',
      'stops',
    ]);
  });

  test('empty dataset', () {
    final text = encodeBusStopsJson(
      osmBase: kTestOsmBase,
      stops: const [],
      provinceOrder: provinces,
    );
    expect(text, contains('"provinces": [],\n'));
    expect(text, endsWith('"stops": []\n}\n'));
    expect(jsonDecode(text), isA<Map<String, Object?>>());
  });

  test('sort: province index, folded name, id', () {
    final sorted = sortBusStops(
      [
        busStop('n2', 'B'),
        busStop('n1', 'B'),
        busStop('n3', 'a'),
        busStop('n0', 'A', province: 'TP. Hồ Chí Minh'),
      ],
      ['Hà Nội', 'TP. Hồ Chí Minh'],
    );
    expect(sorted.map((s) => s.id), ['n3', 'n1', 'n2', 'n0']);
  });
}
