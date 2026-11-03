// T23 TL01–TL08: pure logic of screen 2.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';

const _gaX = TripDestination(
  name: 'Ga X',
  lat: 17.4689,
  lng: 106.5997,
  kind: DestinationKind.train,
  detail: 'Quảng Trị',
);

/// [from] moved [meters] to the north.
MapPoint north(MapPoint from, double meters) =>
    MapPoint(from.lat + meters / (6371008.8 * math.pi / 180), from.lng);

String detail(String place, double m) => '$place|${m.round()}';

void main() {
  test('TL01 queryChars', () {
    expect(queryChars('Đ'), 1);
    expect(queryChars('đồ'), 2);
    expect(queryChars('a b'), 2);
    expect(queryChars('ĐỒNG'), 4);
    expect(queryChars(' - '), 0);
  });

  group('afterPinMove', () {
    const anchor = MapPoint(17.4689, 106.5997);

    test('TL02 300 m keeps the station', () {
      final to = north(anchor, 300);
      final r = afterPinMove(
        current: _gaX,
        currentSource: DestinationSource.station,
        anchor: anchor,
        to: to,
        pinnedName: 'Điểm đã ghim',
        pinnedDetail: detail,
      );
      expect(r.source, DestinationSource.station);
      expect(r.destination.name, 'Ga X');
      expect(r.destination.kind, DestinationKind.train);
      expect(r.destination.detail, 'Quảng Trị');
      expect(r.destination.lat, to.lat);
      expect(r.destination.lng, to.lng);
    });

    test('TL03 800 m becomes a pin', () {
      final to = north(anchor, 800);
      final r = afterPinMove(
        current: _gaX,
        currentSource: DestinationSource.station,
        anchor: anchor,
        to: to,
        pinnedName: 'Điểm đã ghim',
        pinnedDetail: detail,
      );
      expect(r.source, DestinationSource.mapPin);
      expect(r.destination.kind, DestinationKind.pin);
      expect(r.destination.name, 'Điểm đã ghim');
      final parts = r.destination.detail!.split('|');
      expect(parts[0], 'Ga X');
      expect(int.parse(parts[1]), closeTo(800, 2));
      expect(r.destination.lat, to.lat);
    });

    test('TL04 address: 500 m kept, 501 m becomes a pin', () {
      const address = TripDestination(
        name: 'Bến xe Đức Long',
        lat: 17.4689,
        lng: 106.5997,
        kind: DestinationKind.address,
        detail: 'Gia Lai',
      );
      ({TripDestination destination, DestinationSource source}) move(
        double m,
      ) => afterPinMove(
        current: address,
        currentSource: DestinationSource.places,
        anchor: anchor,
        to: north(anchor, m),
        pinnedName: 'Điểm đã ghim',
        pinnedDetail: detail,
      );
      // Exactly at the boundary by construction.
      final at500 = move(499.999);
      expect(distanceM(anchor, north(anchor, 499.999)), lessThanOrEqualTo(500));
      expect(at500.source, DestinationSource.places);
      expect(at500.destination.kind, DestinationKind.address);
      final at501 = move(501);
      expect(at501.source, DestinationSource.mapPin);
      expect(at501.destination.kind, DestinationKind.pin);
    });

    test('TL05 a pin stays a pin without detail', () {
      const pin = TripDestination(
        name: 'Điểm đã ghim',
        lat: 17.4689,
        lng: 106.5997,
        kind: DestinationKind.pin,
        detail: 'Cách Ga X 900 m',
      );
      final to = north(anchor, 50);
      final r = afterPinMove(
        current: pin,
        currentSource: DestinationSource.mapPin,
        anchor: anchor,
        to: to,
        pinnedName: 'Điểm đã ghim',
        pinnedDetail: detail,
      );
      expect(r.source, DestinationSource.mapPin);
      expect(r.destination.kind, DestinationKind.pin);
      expect(r.destination.detail, isNull);
      expect(r.destination.lat, to.lat);
    });
  });

  test('TL06 circleBounds', () {
    final (sw, ne) = circleBounds(const MapPoint(21, 105.8), 1000);
    final dLat = (ne.lat - sw.lat) / 2;
    final dLng = (ne.lng - sw.lng) / 2;
    expect(dLat, closeTo(0.008983, 1e-6));
    expect(dLng, closeTo(dLat / 0.9335804264972017, 1e-6)); // cos 21°
    expect((ne.lat + sw.lat) / 2, closeTo(21, 1e-9));
    final (sw0, ne0) = circleBounds(const MapPoint(0, 0), 1000);
    expect((ne0.lng - sw0.lng) / 2, closeTo((ne0.lat - sw0.lat) / 2, 1e-12));
  });

  test('TL07 distanceM', () {
    final d = distanceM(
      const MapPoint(21.0285, 105.8542),
      const MapPoint(17.4689, 106.5997),
    );
    expect(d, inInclusiveRange(403000, 404000));
    expect(distanceM(const MapPoint(1, 2), const MapPoint(1, 2)), 0);
  });

  test('TL08 toString never prints names, queries or coordinates', () {
    const point = MapPoint(21.0285, 105.8542);
    const dest = TripDestination(
      name: 'Ga Đồng Hới',
      lat: 21.0285,
      lng: 105.8542,
      kind: DestinationKind.train,
      detail: 'Quảng Trị',
    );
    const selection = Selection(
      destination: dest,
      source: DestinationSource.station,
      anchor: point,
      anchorName: 'Ga Đồng Hới',
    );
    const state = DestinationState(
      catalog: AsyncLoading(),
      query: 'dong hoi',
      selection: selection,
      undo: PinUndo(selection),
    );
    for (final text in [
      point.toString(),
      selection.toString(),
      state.toString(),
      const PinUndo(selection).toString(),
    ]) {
      for (final secret in ['21.0', '105.8', 'Đồng Hới', 'dong hoi', 'Quảng']) {
        expect(text.contains(secret), isFalse, reason: '$secret in $text');
      }
    }
  });
}
