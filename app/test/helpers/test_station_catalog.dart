// The real assets/stations.json as a ready catalog, built once per test
// isolate (T23). pumpAppHarness uses it so screen 2 never waits for the
// asset bundle or an isolate inside fake async. Not a test file.
import 'dart:io';

import 'package:napstop/features/destination/data/station_repository.dart';

/// Catalog of the real dataset (664 stations, built synchronously).
final StationCatalog kTestStationCatalog = buildStationCatalog(
  File('assets/stations.json').readAsStringSync(),
);
