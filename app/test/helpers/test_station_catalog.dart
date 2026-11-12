// The real assets/stations.json as a ready catalog, built once per test
// isolate (T23). pumpAppHarness uses it so screen 2 never waits for the
// asset bundle or an isolate inside fake async. Not a test file.
import 'dart:io';

import 'package:napstop/features/destination/data/bus_stop_repository.dart';
import 'package:napstop/features/destination/data/station_repository.dart';

/// Catalog of the real dataset (664 stations, built synchronously).
final StationCatalog kTestStationCatalog = buildStationCatalog(
  File('assets/stations.json').readAsStringSync(),
);

/// Catalog of the real `assets/bus_stops.json` (T24.3), built on first use.
final StationCatalog kTestBusStopCatalog = buildBusStopCatalog(
  File('assets/bus_stops.json').readAsStringSync(),
);

/// A bus stop catalog without stops: the default of the screen 2 harness,
/// so tests written before T24.3 see no bus stop rows.
final StationCatalog kEmptyBusStopCatalog = buildBusStopCatalog(
  '{"schemaVersion": 1, "source": {"osmBase": "", "attribution": '
  '"© OpenStreetMap contributors", "licenseUrl": ""}, "provinces": [], '
  '"stops": []}',
);
