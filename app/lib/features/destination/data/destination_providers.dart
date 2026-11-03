/// Providers of screen 2's data (T23 §2): offline catalog, Maps/Places
/// configuration, Places client.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:http/http.dart' as http;
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/features/destination/data/places/places_client.dart';
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

/// Maps/Places key and app identity of this build, read once per session.
/// A bridge error is not cached as "no key" for the session: the provider
/// stays in error (the screen treats it as no key) and screen 2 / the
/// address chip invalidate it to read again.
///
/// PRIVACY: never log the value (its toString prints the key).
final mapsConfigProvider = FutureProvider<MapsConfigMsg>(
  // T29: NonFatalReason.pigeonCallFailed on error (no telemetry before T29).
  (ref) => ref.watch(coreBridgeProvider).mapsConfig(),
);

/// HTTP client of the Places calls. Widget tests override it with a
/// `MockClient`; no test ever reaches Google.
final placesHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// A Places client for the app language (`vi` or `en`).
final FutureProviderFamily<PlacesClient, String> placesClientProvider =
    FutureProvider.family<PlacesClient, String>((ref, languageCode) async {
      final config = await ref.watch(mapsConfigProvider.future);
      return PlacesClient(
        client: ref.watch(placesHttpClientProvider),
        config: config,
        languageCode: languageCode,
      );
    });

/// Source of session tokens (T23 D6). Tests override it with a seeded one.
final placesRandomProvider = Provider<Random>((ref) => Random.secure());
