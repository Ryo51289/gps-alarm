/// Lazy loading of the offline station dataset (spec T24 §7.1, §7.4).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// Asset key of the dataset (declared in pubspec.yaml).
const String kStationsAssetKey = 'assets/stations.json';

/// Dataset plus its search index.
final class StationCatalog {
  const new({required this.dataset, required this.index});

  final StationDataset dataset;
  final StationSearchIndex index;
}

/// Loads the dataset once, on first use (not at app start).
final class StationRepository {
  new({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<StationCatalog>? _catalog;

  /// The catalog. Concurrent calls share one load; after a failure the next
  /// call tries again. Fails with [StationDataException], also when the
  /// asset is missing or unreadable (spec §7.4).
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
      text = await _bundle.loadString(kStationsAssetKey, cache: false);
    } on Object catch (e) {
      // Bundles fail with FlutterError or other types; callers only need
      // to catch StationDataException (screen 2 shows the error banner).
      throw StationDataException(
        'asset $kStationsAssetKey not loadable (${e.runtimeType})',
      );
    }
    return await compute(buildStationCatalog, text);
  }
}

/// Decodes [source] and builds the index. Runs in a background isolate.
StationCatalog buildStationCatalog(String source) {
  final dataset = decodeStationsJson(source);
  return StationCatalog(
    dataset: dataset,
    index: StationSearchIndex(dataset.stations),
  );
}
