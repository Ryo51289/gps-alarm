/// Lazy loading of the offline bus stop dataset (spec T24.3 §6.1, D10).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:napstop/features/destination/data/bus_stops_codec.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// Asset key of the bus stop dataset (declared in pubspec.yaml).
const String kBusStopsAssetKey = 'assets/bus_stops.json';

/// Loads the bus stops once, on first use: when the user types a second
/// character or opens the "Trạm buýt" chip (D10), never at app start.
final class BusStopRepository {
  new({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<StationCatalog>? _catalog;

  /// The catalog. Concurrent calls share one load; after a failure the next
  /// call tries again. Fails with [StationDataException], also when the
  /// asset is missing or unreadable.
  Future<StationCatalog> load() {
    final existing = _catalog;
    if (existing != null) {
      return existing;
    }
    final future = _load();
    _catalog = future;
    // Error callbacks always run asynchronously, so this cannot run before
    // the assignment above.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_catalog, future)) {
            _catalog = null;
          }
        },
      ),
    );
    return future;
  }

  Future<StationCatalog> _load() async {
    final String text;
    try {
      // cache: false so the large string does not stay in the bundle cache.
      text = await _bundle.loadString(kBusStopsAssetKey, cache: false);
    } on Object catch (e) {
      throw StationDataException(
        'asset $kBusStopsAssetKey not loadable (${e.runtimeType})',
      );
    }
    return await compute(buildBusStopCatalog, text);
  }
}

/// Decodes [source] and builds the bucketed index without the substring
/// tier (D8). Runs in a background isolate.
StationCatalog buildBusStopCatalog(String source) {
  final dataset = decodeBusStopsJson(source);
  return StationCatalog(
    dataset: dataset,
    index: StationSearchIndex(
      dataset.stations,
      bucketByFirstChar: true,
      substringTier: false,
    ),
  );
}
