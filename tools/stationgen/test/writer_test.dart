// TC12: byte format of stations.json.
import 'dart:convert';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _golden = r'''
{
  "schemaVersion": 1,
  "generator": {"name": "stationgen", "version": "1.0.0"},
  "source": {"osmBase": "2026-11-01T00:00:00Z", "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/", "copyrightUrl": "https://www.openstreetmap.org/copyright"},
  "counts": {"train": 1, "coach": 1, "bus": 1},
  "stations": [
    {"id":"osm:w367260095","name":"Ga Đồng Hới","nameAscii":"ga dong hoi","kind":"train","province":"Quảng Trị","lat":17.46892,"lng":106.59973,"aliases":[]},
    {"id":"osm:r21430094","name":"Bến xe Mỹ Đình","nameAscii":"ben xe my dinh","kind":"coach","province":"Hà Nội","lat":21.02827,"lng":105.77752,"aliases":["Bến xe \"MĐ\"","BX Mỹ Đình"]},
    {"id":"man:diem-a","name":"Điểm trung chuyển A","nameAscii":"diem trung chuyen a","kind":"bus","province":"Hà Nội","lat":21.00000,"lng":105.80000,"aliases":[]}
  ]
}
''';

void main() {
  final stations = [
    cand('man:diem-a', 'Điểm trung chuyển A', kind: StationKind.bus),
    cand(
      'osm:r21430094',
      'Bến xe Mỹ Đình',
      lat: 21.028271,
      lng: 105.777524,
      aliases: ['Bến xe "MĐ"', 'BX Mỹ Đình'],
    ),
    cand(
      'osm:w367260095',
      'Ga Đồng Hới',
      kind: StationKind.train,
      province: 'Quảng Trị',
      lat: 17.468924,
      lng: 106.599726,
    ),
  ];

  test('matches the golden bytes', () {
    final text = encodeStationsJson(osmBase: kTestOsmBase, stations: stations);
    expect(text, _golden);
    expect(text.endsWith('}\n'), isTrue);
    expect(text.contains('\r'), isFalse);
    // Valid JSON with the key order of the spec.
    final json = jsonDecode(text) as Map<String, Object?>;
    expect(json.keys, [
      'schemaVersion',
      'generator',
      'source',
      'counts',
      'stations',
    ]);
    final first = (json['stations']! as List<Object?>).first! as Map;
    expect(first.keys, [
      'id',
      'name',
      'nameAscii',
      'kind',
      'province',
      'lat',
      'lng',
      'aliases',
    ]);
  });

  test('empty dataset', () {
    final text = encodeStationsJson(osmBase: kTestOsmBase, stations: []);
    expect(text, contains('"stations": []\n}\n'));
    expect(jsonDecode(text), isA<Map<String, Object?>>());
  });

  test('sort: kind, then nameAscii, then id', () {
    final a = cand('osm:n2', 'Bến xe B');
    final b = cand('osm:n1', 'Bến xe B');
    final c = cand('osm:n3', 'Bến xe A');
    final t = cand('osm:n9', 'Ga Z', kind: StationKind.train);
    final sorted = [a, b, c, t]..sort(compareStations);
    expect(sorted.map((s) => s.id), ['osm:n9', 'osm:n3', 'osm:n1', 'osm:n2']);
  });
}
