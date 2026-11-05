import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';

/// The bundled traces (T18 `assets/sim/catalog.json`), read once. Tests
/// override it (an asset error shows `simCatalogError`).
final simTraceCatalogProvider = FutureProvider<SimTraceCatalog>(
  (ref) => loadSimTraceCatalog(rootBundle),
);
