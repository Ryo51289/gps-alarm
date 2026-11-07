// T23.3 MW04-MW08: camera geometry and the screen 2 layout.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart'
    as logic;

import '../../helpers/test_station_catalog.dart';

MapBounds _box((MapPoint, MapPoint) b) =>
    MapBounds(south: b.$1.lat, west: b.$1.lng, north: b.$2.lat, east: b.$2.lng);

void main() {
  test('MW04 frameBounds is circleBounds of T23, 1 km without a radius', () {
    const p = MapPoint(17.4688, 106.6223);
    expect(frameBounds(p, 1000), _box(logic.circleBounds(p, 1000)));
    expect(frameBounds(p, null), _box(logic.circleBounds(p, 1000)));
    expect(frameBounds(p, 2500), _box(logic.circleBounds(p, 2500)));
    final b = frameBounds(p, 1000);
    expect(b.contains(p), isTrue);
    expect(b.north - b.south, closeTo(2000 / 111320, 1e-9));
  });

  test('MW05 every station is inside Vietnam and reachable by the camera', () {
    final stations = kTestStationCatalog.dataset.stations;
    expect(stations.length, greaterThan(500));
    final outside = <String>[];
    final hidden = <String>[];
    for (final s in stations) {
      final p = MapPoint(s.lat, s.lng);
      if (!kVietnamBounds.contains(p)) {
        outside.add(s.id);
      }
      if (!kCameraCenterBounds.contains(p) &&
          !frameBounds(p, null).intersects(kCameraCenterBounds)) {
        hidden.add(s.id);
      }
    }
    expect(outside, isEmpty);
    expect(hidden, isEmpty);
  });

  test('MW06 D11 constants: stations reachable, islands hidden', () {
    final stations = kTestStationCatalog.dataset.stations;
    final eastmost = stations.map((s) => s.lng).reduce(math.max);
    expect(kCameraCenterBounds.east, greaterThanOrEqualTo(eastmost));
    expect(kVisibleEastLimitLng, lessThan(kIslandsWestLng));
    // At the widest span a valid center still exists (106.5 >= 102).
    const widestCenter = kVisibleEastLimitLng - kMaxVisibleLngSpan / 2;
    expect(widestCenter, closeTo(106.5, 1e-9));
    expect(widestCenter, greaterThanOrEqualTo(kCameraCenterBounds.west));
    expect(centerEastLimit(kMaxVisibleLngSpan), closeTo(widestCenter, 1e-9));
    // 102.1-109.5 fits in a view of the widest span whose east edge is 110.9.
    expect(
      kVisibleEastLimitLng - kMaxVisibleLngSpan,
      lessThanOrEqualTo(102.1 + 1e-9),
    );
    expect(kVisibleEastLimitLng, greaterThanOrEqualTo(109.5));
    expect(kVietnamBounds.east, lessThan(kIslandsWestLng));
    for (final island in const [
      MapPoint(10.22, 103.96), // Phú Quốc
      MapPoint(8.68, 106.61), // Côn Đảo
      MapPoint(15.38, 109.12), // Lý Sơn
      MapPoint(20.13, 107.72), // Bạch Long Vĩ
    ]) {
      expect(kVietnamBounds.contains(island), isTrue);
    }
    expect(kMaxCameraDistanceM, greaterThan(0));
    expect(kMaxCardCameraDistanceM, greaterThan(0));
  });

  group('MW06b centerEastLimit, table shared with Swift', () {
    final table =
        (jsonDecode(File('../fixtures/map_wire/cases.json').readAsStringSync())
                as Map<String, Object?>)['centerEastLimit']!
            as Map<String, Object?>;

    test('fixture matches the Dart constants', () {
      expect(table['capEast'], kCameraCenterBounds.east);
      expect(table['eastLimit'], kVisibleEastLimitLng);
    });

    for (final c in (table['cases']! as List).cast<Map<String, Object?>>()) {
      test('span ${c['span']}', () {
        final raw = c['span'];
        final span = raw == 'NaN' ? double.nan : (raw! as num).toDouble();
        expect(
          centerEastLimit(span),
          closeTo((c['expect']! as num).toDouble(), 1e-9),
        );
      });
    }

    test('infinity and the spec values', () {
      expect(centerEastLimit(double.infinity), kCameraCenterBounds.east);
      expect(centerEastLimit(3.2), closeTo(109.3, 1e-9));
      // Never east of the cap, never makes the visible east edge pass 110.9.
      for (var span = 0.1; span <= kMaxVisibleLngSpan; span += 0.1) {
        final c = centerEastLimit(span);
        expect(c, lessThanOrEqualTo(kCameraCenterBounds.east));
        expect(c + span / 2, lessThanOrEqualTo(kVisibleEastLimitLng + 1e-9));
      }
    });
  });

  test('MW07 map height ends at the resting panel', () {
    expect(
      destinationMapHeight(
        topInset: 47,
        topBarHeight: 64,
        sheetAreaHeight: 600,
        sheetMin: 0.30,
      ),
      closeTo(47 + 64 + 600 * 0.70, 1e-9),
    );
    expect(
      destinationMapHeight(
        topInset: 0,
        topBarHeight: 64,
        sheetAreaHeight: -5,
        sheetMin: 0.30,
      ),
      64,
    );
  });

  test('MW08 frame padding follows the panel', () {
    const topInset = 47.0;
    const topBar = 64.0;
    const area = 600.0;
    final mapHeight = destinationMapHeight(
      topInset: topInset,
      topBarHeight: topBar,
      sheetAreaHeight: area,
      sheetMin: 0.30,
    );
    MapPadding at(double extent) => destinationFramePadding(
      topInset: topInset,
      topBarHeight: topBar,
      badgeHeight: 32,
      mapHeight: mapHeight,
      sheetTopY: topInset + topBar + area * (1 - extent),
    );
    final low = at(0.30);
    final mid = at(0.55);
    final high = at(0.92);
    // Resting panel: nothing covered, only the margin.
    expect(low.bottom, closeTo(kCameraPaddingPt, 1e-9));
    // 0.55: the covered part (600 * 0.25) plus the margin.
    expect(mid.bottom, closeTo(600 * 0.25 + kCameraPaddingPt, 1e-9));
    expect(low.top, closeTo(47 + 64 + 32 + kCameraPaddingPt, 1e-9));
    expect(low.left, kCameraPaddingPt);
    expect(low.right, kCameraPaddingPt);
    // 0.92 covers almost all: capped so a span stays between the paddings.
    expect(high.bottom, greaterThanOrEqualTo(mid.bottom));
    expect(
      mapHeight - high.top - high.bottom,
      greaterThanOrEqualTo(kMinFrameSpanPt - 1e-9),
    );
    for (final p in [low, mid, high]) {
      expect(p.bottom, greaterThanOrEqualTo(0));
      expect(p.top, lessThanOrEqualTo(kMaxWirePaddingPt));
    }
    // Panel above the map bottom by more than the map height: never negative.
    final tiny = destinationFramePadding(
      topInset: 0,
      topBarHeight: 64,
      badgeHeight: 32,
      mapHeight: 100,
      sheetTopY: 0,
    );
    expect(tiny.bottom, 0);
  });
}
