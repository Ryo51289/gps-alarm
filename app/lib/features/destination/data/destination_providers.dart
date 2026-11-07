/// Providers of screen 2's data (T23 §2, T23.2): the offline catalog of
/// stations. Search runs on this catalog only (ADR-002 §4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/features/destination/data/station_repository.dart';

final stationRepositoryProvider = Provider<StationRepository>(
  (ref) => StationRepository(),
);

/// The offline dataset and its index, loaded the first time screen 2 opens
/// and kept for the session (1–2 MB). A failure stays until
/// `ref.invalidate` (the "Thử lại" button; no automatic retry, T22 D3).
final stationCatalogProvider = FutureProvider<StationCatalog>(
  (ref) => ref.watch(stationRepositoryProvider).load(),
);
