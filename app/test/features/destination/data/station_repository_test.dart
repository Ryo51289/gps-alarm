// TC31: lazy, shared and retryable loading; asset errors surface as
// StationDataException (spec §7.4).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';

const String _asset = '''
{
  "schemaVersion": 1,
  "generator": {"name": "stationgen", "version": "1.0.0"},
  "source": {"osmBase": "2026-11-01T00:00:00Z", "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/", "copyrightUrl": "https://www.openstreetmap.org/copyright"},
  "counts": {"train": 1, "coach": 0, "bus": 0},
  "stations": [
    {"id":"osm:w1","name":"Ga Đồng Hới","nameAscii":"ga dong hoi","kind":"train","province":"Quảng Trị","lat":17.46892,"lng":106.59973,"aliases":[]}
  ]
}
''';

final class MissingAsset implements Exception {
  const new();
}

final class FakeBundle extends CachingAssetBundle {
  new({this.failFirst = 0, this.syncThrow = false, this.text = _asset});

  int failFirst;
  final bool syncThrow;
  final String text;
  final List<(String, bool)> calls = [];

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    calls.add((key, cache));
    if (failFirst > 0) {
      failFirst--;
      if (syncThrow) {
        throw const MissingAsset();
      }
      return Future.error(const MissingAsset());
    }
    return Future.value(text);
  }

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(_asset));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent loads share one asset read with cache: false', () async {
    final bundle = FakeBundle();
    final repo = StationRepository(bundle: bundle);
    final results = await Future.wait([repo.load(), repo.load()]);
    expect(identical(results[0], results[1]), isTrue);
    expect(bundle.calls, [(kStationsAssetKey, false)]);
    expect(results[0].index.search('dong hoi').single.station.id, 'osm:w1');
    expect(results[0].dataset.osmBase, '2026-11-01T00:00:00Z');
    // Memoised.
    await repo.load();
    expect(bundle.calls, hasLength(1));
  });

  for (final syncThrow in [false, true]) {
    test('a failed load is retried (sync throw: $syncThrow)', () async {
      final bundle = FakeBundle(failFirst: 1, syncThrow: syncThrow);
      final repo = StationRepository(bundle: bundle);
      await expectLater(
        repo.load(),
        throwsA(
          isA<StationDataException>().having(
            (e) => e.message,
            'message',
            contains(kStationsAssetKey),
          ),
        ),
      );
      final catalog = await repo.load();
      expect(catalog.index.length, 1);
      expect(bundle.calls, hasLength(2));
    });
  }

  test(
    'a missing asset in the real bundle is a StationDataException',
    () async {
      final repo = StationRepository(bundle: _MissingRootBundle());
      await expectLater(repo.load(), throwsA(isA<StationDataException>()));
    },
  );

  test('a corrupt asset is a StationDataException', () async {
    final repo = StationRepository(
      bundle: FakeBundle(text: '{"schemaVersion": 1'),
    );
    await expectLater(repo.load(), throwsA(isA<StationDataException>()));
  });
}

/// Fails like a bundle without the asset (PlatformAssetBundle throws
/// FlutterError "Unable to load asset").
final class _MissingRootBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('Unable to load asset: "$key".'));
}
