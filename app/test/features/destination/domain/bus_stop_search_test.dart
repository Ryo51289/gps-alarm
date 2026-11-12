// T24.3 BS-P04 (query prefixes), BS-P05 (ranking of bus stops), BS-P03
// (station index unchanged by the new options), bucketed index edge cases,
// pure logic of screen 2 for bus stops (§6.4, D10, D11), BS-A05, BS-T01,
// BS-T02 (destination kind, vehicle hint, short-distance warning).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/trip_config_builder.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

import '../../../helpers/test_station_catalog.dart';

Station _stop(
  String id,
  String name, {
  String province = 'Hà Nội',
  double lat = 21,
  double lng = 105.8,
  List<String> routes = const [],
}) => Station(
  id: id,
  name: name,
  nameAscii: name.toLowerCase(),
  kind: StationKind.busStop,
  province: province,
  lat: lat,
  lng: lng,
  routeRefs: routes,
);

final List<Station> _stops = [
  _stop('osm:n1', 'Đại học Bách khoa'),
  _stop('osm:n2', 'Đại học Bách khoa', lat: 21.01),
  _stop('osm:n3', 'Đại học Bách khoa', province: 'TP. Hồ Chí Minh', lat: 10.77),
  _stop('osm:n4', 'Bách Khoa Hà Nội'),
  _stop('osm:n5', 'Kim Mã'),
  _stop('osm:n6', 'Bachkhoa'),
];

StationSearchIndex _bucketed(List<Station> s) =>
    StationSearchIndex(s, bucketByFirstChar: true, substringTier: false);

void main() {
  group('parseStationQuery (BS-P04)', () {
    String parse(String q) {
      final p = parseStationQuery(q);
      return '${p.kindHint?.name} ${p.tokens}';
    }

    test('bus stop prefixes', () {
      expect(parse('tram buyt bach khoa'), 'busStop [bach, khoa]');
      expect(parse('Điểm dừng Bách Khoa'), 'busStop [bach, khoa]');
      expect(parse('trạm xe buýt bách khoa'), 'busStop [bach, khoa]');
      expect(parse('diem dung xe buyt kim ma'), 'busStop [kim, ma]');
      expect(parse('tram dung kim ma'), 'busStop [kim, ma]');
      expect(parse('ben xe buyt kim ma'), 'bus [kim, ma]');
      expect(parse('xe buyt kim ma'), 'bus [kim, ma]');
      expect(parse('ga hue'), 'train [hue]');
      expect(parse('tram buyt'), 'null [tram, buyt]', reason: 'nothing left');
    });
  });

  group('ranking (BS-P05)', () {
    final index = _bucketed(_stops);

    test('"bach khoa": every Bách khoa stop, T24 scores, stable order', () {
      final r = index.search('bach khoa', limit: 50);
      expect(r.map((m) => '${m.station.id} ${m.score} ${m.tier.name}'), [
        // Typed together equals "Bachkhoa" (990); "Bách Khoa Hà Nội" starts
        // with the query (900); the others have both words in order (700).
        'osm:n6 990 exact',
        'osm:n4 900 prefix',
        'osm:n1 700 orderedTokens',
        'osm:n2 700 orderedTokens',
        'osm:n3 700 orderedTokens',
      ]);
    });

    test('"dai hoc bach khoa": exact matches, then by id', () {
      final r = index.search('dai hoc bach khoa', limit: 50);
      expect(r.map((m) => '${m.station.id} ${m.score}'), [
        'osm:n1 1000',
        'osm:n2 1000',
        'osm:n3 1000',
      ]);
    });

    test('kind hint busStop adds 150 to every stop', () {
      final r = index.search('kim ma', kindHint: StationKind.busStop);
      expect(r.single.score, 1150);
      final viaPrefix = index.search('tram buyt kim ma');
      expect(viaPrefix.single.score, 1150);
    });

    test('province name with the hint', () {
      final r = index.search('ho chi minh', kindHint: StationKind.busStop);
      expect(r.single.station.id, 'osm:n3');
      expect(r.single.tier, StationMatchTier.provinceAssisted);
    });
  });

  group('bucketed index', () {
    test('equals a full scan without substring on the synthetic set', () {
      final full = StationSearchIndex(_stops, substringTier: false);
      final bucketed = _bucketed(_stops);
      for (final q in [
        'bach khoa',
        'khoa bach',
        'bachkhoa',
        'bach khoa ha noi',
        'bahc khoa',
        'dai hco',
        'kim',
        'ma kim',
        'ha noi',
        'khoa ha noi',
        'xyz',
        'b',
      ]) {
        for (final hint in [null, StationKind.busStop]) {
          expect(
            bucketed.search(q, limit: 50, kindHint: hint).toString(),
            full.search(q, limit: 50, kindHint: hint).toString(),
            reason: '$q $hint',
          );
        }
      }
    });

    test('"bach khoa" typed together finds the two-word name', () {
      final r = _bucketed(_stops).search('bachkhoa', limit: 50);
      expect(r.map((m) => m.station.id), contains('osm:n4'));
    });

    test('no substring tier: a query inside a word finds nothing', () {
      final stops = [_stop('osm:n1', 'Nguyễn Trãi')];
      expect(
        StationSearchIndex(stops).search('guyen').single.tier,
        StationMatchTier.substring,
      );
      expect(_bucketed(stops).search('guyen'), isEmpty);
    });

    test('limit keeps the best ones in order (many matches)', () {
      final many = [
        for (var i = 0; i < 400; i++)
          _stop('osm:n${1000 + i}', 'Trạm ${i.toString().padLeft(3, '0')}'),
      ];
      final index = _bucketed(many);
      final all = index.search('tram', limit: 1000);
      expect(all, hasLength(400));
      expect(
        index.search('tram', limit: 7).toString(),
        all.take(7).toList().toString(),
      );
    });
  });

  test('station index with default options keeps T24 results (BS-P03)', () {
    final index = kTestStationCatalog.index;
    expect(index.search('dong hoi').first.station.name, 'Ga Đồng Hới');
    expect(index.search('my dinh').first.station.province, 'Hà Nội');
    final legacy = StationSearchIndex(kTestStationCatalog.dataset.stations);
    for (final q in ['vinh', 'ben xe vinh', 'hanoi', 'giap', 'ninh binh']) {
      expect(
        index.search(q, limit: 100).toString(),
        legacy.search(q, limit: 100).toString(),
      );
    }
  });

  group('screen 2 logic (§6.4, D10, D11)', () {
    final index = _bucketed(_stops);

    test('shouldLoadBusStops: second letter or the bus stop chip', () {
      expect(shouldLoadBusStops('', DestinationFilter.all), isFalse);
      expect(shouldLoadBusStops('b', DestinationFilter.all), isFalse);
      expect(shouldLoadBusStops('ba', DestinationFilter.all), isTrue);
      expect(shouldLoadBusStops('ba', DestinationFilter.train), isTrue);
      expect(shouldLoadBusStops('', DestinationFilter.busStop), isTrue);
    });

    test('busStopResults per chip', () {
      final many = _bucketed([
        for (var i = 0; i < 30; i++) _stop('osm:n${100 + i}', 'Chợ $i'),
      ]);
      expect(busStopResults(many, 'cho', DestinationFilter.all), hasLength(5));
      expect(busStopResults(many, 'ch', DestinationFilter.all), isEmpty);
      expect(
        busStopResults(many, 'ch', DestinationFilter.busStop),
        hasLength(20),
      );
      expect(busStopResults(many, 'c', DestinationFilter.busStop), isEmpty);
      expect(busStopResults(many, 'cho', DestinationFilter.train), isEmpty);
      expect(busStopResults(many, 'cho', DestinationFilter.coach), isEmpty);
      expect(
        busStopResults(many, 'tram buyt cho', DestinationFilter.all),
        hasLength(20),
        reason: 'a bus stop query lists up to 20 on chip all',
      );
      expect(
        offlineResults(
          kTestStationCatalog.index,
          'dong hoi',
          DestinationFilter.busStop,
        ),
        isEmpty,
      );
      expect(
        busStopResults(index, 'bach khoa', DestinationFilter.all).first.score,
        990,
      );
    });

    test('busStopsFirst only on chip all with a bus stop prefix', () {
      expect(busStopsFirst('tram buyt kim ma', DestinationFilter.all), isTrue);
      expect(busStopsFirst('diem dung kim', DestinationFilter.all), isTrue);
      expect(busStopsFirst('kim ma', DestinationFilter.all), isFalse);
      expect(busStopsFirst('ben xe buyt kim', DestinationFilter.all), isFalse);
      expect(
        busStopsFirst('tram buyt kim', DestinationFilter.busStop),
        isFalse,
      );
    });

    test('preview radius: 500 m for a bus stop, 1 km otherwise (D11)', () {
      final stop = _stops.first;
      Selection sel(Station s, {required bool busStop}) => Selection(
        destination: TripDestination.fromStation(s),
        source: DestinationSource.station,
        anchor: MapPoint(s.lat, s.lng),
        anchorName: s.name,
        busStop: busStop,
      );
      expect(previewRadiusM(null), 1000);
      expect(previewRadiusM(sel(stop, busStop: true)), 500);
      expect(sel(stop, busStop: true).isBusStop, isTrue);
      final station = kTestStationCatalog.dataset.stations.first;
      expect(previewRadiusM(sel(station, busStop: false)), 1000);
      // A pin is never a bus stop, whatever the flag says.
      const pin = Selection(
        destination: TripDestination(
          name: 'Ghim',
          lat: 21,
          lng: 105.8,
          kind: DestinationKind.pin,
        ),
        source: DestinationSource.mapPin,
        anchor: MapPoint(21, 105.8),
        anchorName: 'Ghim',
        busStop: true,
      );
      expect(pin.isBusStop, isFalse);
      expect(previewRadiusM(pin), 1000);
      expect(
        sel(stop, busStop: true),
        isNot(sel(stop, busStop: false)),
        reason: 'the flag is part of equality',
      );
    });
  });

  group('trip (BS-A05, BS-T01, BS-T02)', () {
    final stop = _stops.first;

    test('a bus stop is a bus destination with the province as detail', () {
      final d = TripDestination.fromStation(stop);
      expect(d.kind, DestinationKind.bus);
      expect(d.detail, 'Hà Nội');
      expect(d.name, 'Đại học Bách khoa');
      expect(
        DestinationKind.fromStation(StationKind.busStop),
        DestinationKind.bus,
      );
      expect(vehicleHintFor(d.kind), VehicleKindMsg.bus);
    });

    test('short distance warning with the bus hint (T25 U01)', () {
      const p = AlarmSettingsParams.defaults;
      bool warn(int m) => shortDistanceWarning(m, VehicleKindMsg.bus, p);
      expect(
        [warn(500), warn(1000), warn(1333), warn(1334)],
        [true, true, true, false],
      );
    });

    test('buildTripConfig: vehicle hint bus, engine params unchanged', () {
      final draft = TripDraft(
        destination: TripDestination.fromStation(stop),
        source: DestinationSource.station,
      );
      const prefs = AlarmPreferences(
        soundId: 'default',
        volumePct: 80,
        rampUp: false,
        vibration: VibrationMsg.medium,
        flash: true,
      );
      final c = buildTripConfig(
        tripId: 'trip-1',
        draft: draft,
        settings: TripSettings.defaults,
        prefs: prefs,
        engineParamsJson: '{"v":1}',
      );
      expect(c.vehicleHint, VehicleKindMsg.bus);
      expect(c.engineParamsJson, '{"v":1}');
    });
  });
}
