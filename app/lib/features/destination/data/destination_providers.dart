/// Providers of screen 2's data (T23 §2, T23.2, T23.5, T24.3): the offline
/// catalogs of stations and bus stops. Search runs on these catalogs only
/// (ADR-002 §4).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/features/destination/data/address_search_client.dart';
import 'package:napstop/features/destination/data/bus_stop_repository.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';

final stationRepositoryProvider = Provider<StationRepository>(
  (ref) => StationRepository(),
);

/// The offline dataset and its index, loaded the first time screen 2 opens
/// and kept for the session (1–2 MB). A failure stays until
/// `ref.invalidate` (the "Thử lại" button; no automatic retry, T22 D3).
final stationCatalogProvider = FutureProvider<StationCatalog>(
  (ref) => ref.watch(stationRepositoryProvider).load(),
);

final busStopRepositoryProvider = Provider<BusStopRepository>(
  (ref) => BusStopRepository(),
);

/// The bus stops of Hà Nội and TP. Hồ Chí Minh with their bucketed index
/// (T24.3). Only read when D10 holds (second letter typed or chip "Trạm
/// buýt"); kept for the session. A failure stays until `ref.invalidate`
/// (chip tapped again or "Thử lại").
final busStopCatalogProvider = FutureProvider<StationCatalog>(
  (ref) => ref.watch(busStopRepositoryProvider).load(),
);

/// Apple Maps address search (T23.5): iOS only; Android has no MapKit
/// (null). Widget tests override it with a fake.
final addressSearchClientProvider = Provider<AddressSearchClient?>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? const MethodChannelAddressSearchClient()
      : null,
);

/// D10: address suggestions are shown only with a client and a map on the
/// same screen (DPLA Attachment 6 §2.4: an address result is shown with its
/// map).
final addressSearchEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(addressSearchClientProvider) != null &&
      ref.watch(destinationMapBuilderProvider) != null,
);
