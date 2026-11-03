/// State machine of screen 2 "Chọn điểm đến" (T23 §8, §10). Lives only in
/// memory while the screen is shown (autoDispose).
///
/// PRIVACY: never log the query, a name or coordinates; `toString` of every
/// type here prints none of them.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;
import 'package:meta/meta.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/places/places_models.dart';
import 'package:napstop/features/destination/data/places/session_token.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// What the address (Places) list shows.
sealed class PlacesUiState {
  const new();
}

/// The build has no API key.
final class PlacesUiNotConfigured extends PlacesUiState {
  const new();

  @override
  String toString() => 'PlacesUiNotConfigured';
}

/// Fewer than [kMinPlacesQueryChars] letters typed.
final class PlacesUiTypeMore extends PlacesUiState {
  const new();

  @override
  String toString() => 'PlacesUiTypeMore';
}

final class PlacesUiLoading extends PlacesUiState {
  const new();

  @override
  String toString() => 'PlacesUiLoading';
}

/// Suggestions; [resolvingId] is the one whose location is being read.
final class PlacesUiResults extends PlacesUiState {
  const new(this.predictions, {this.resolvingId});

  final List<PlacePrediction> predictions;
  final String? resolvingId;

  @override
  String toString() =>
      'PlacesUiResults(${predictions.length}, '
      'resolving: ${resolvingId != null})';
}

final class PlacesUiEmpty extends PlacesUiState {
  const new();

  @override
  String toString() => 'PlacesUiEmpty';
}

/// No connection.
final class PlacesUiOffline extends PlacesUiState {
  const new();

  @override
  String toString() => 'PlacesUiOffline';
}

/// Denied, quota, server error or bad response.
final class PlacesUiUnavailable extends PlacesUiState {
  const new();

  @override
  String toString() => 'PlacesUiUnavailable';
}

/// The selection before the latest pin drop or move ([previous] null: there
/// was none).
@immutable
final class PinUndo {
  const new(this.previous);

  final Selection? previous;

  @override
  String toString() => 'PinUndo(${previous != null})';
}

/// Everything screen 2 shows.
@immutable
final class DestinationState {
  const new({
    required this.catalog,
    this.query = '',
    this.filter = DestinationFilter.all,
    this.offline = const [],
    this.distanceByStationId = const {},
    this.places = const PlacesUiTypeMore(),
    this.selection,
    this.cameraRequestId = 0,
    this.undo,
  });

  final String query;
  final DestinationFilter filter;
  final AsyncValue<StationCatalog> catalog;

  /// Station rows of the current query and filter.
  final List<StationMatch> offline;

  /// "cách X km" per station id, already rounded by the native side (10 m
  /// under 1 km, 100 m above). PRIVACY: location data — several distances
  /// to public stations locate the user. Kept in this screen's memory only:
  /// never logged, persisted, printed by toString or sent to telemetry.
  final Map<String, double> distanceByStationId;
  final PlacesUiState places;
  final Selection? selection;

  /// Grows when the map should frame a newly chosen destination.
  final int cameraRequestId;
  final PinUndo? undo;

  DestinationState copyWith({
    String? query,
    DestinationFilter? filter,
    AsyncValue<StationCatalog>? catalog,
    List<StationMatch>? offline,
    Map<String, double>? distanceByStationId,
    PlacesUiState? places,
    Selection? Function()? selection,
    int? cameraRequestId,
    PinUndo? Function()? undo,
  }) => DestinationState(
    query: query ?? this.query,
    filter: filter ?? this.filter,
    catalog: catalog ?? this.catalog,
    offline: offline ?? this.offline,
    distanceByStationId: distanceByStationId ?? this.distanceByStationId,
    places: places ?? this.places,
    selection: selection == null ? this.selection : selection(),
    cameraRequestId: cameraRequestId ?? this.cameraRequestId,
    undo: undo == null ? this.undo : undo(),
  );

  /// PRIVACY: no query, no name, no coordinates.
  @override
  String toString() =>
      'DestinationState(${filter.name}, rows: ${offline.length}, $places, '
      '$selection)';
}

/// Screen 2 state, one controller per screen instance (review T23 #12): a
/// screen 2 opened while the previous one still plays its exit animation
/// gets its own, empty controller; the old one stays suspended and is
/// disposed with the old screen. Each screen keys it with its own
/// `Object()`.
final NotifierProviderFamily<DestinationController, DestinationState, Object>
destinationControllerFamily = NotifierProvider.autoDispose
    .family<DestinationController, DestinationState, Object>(
      (_) => DestinationController(),
    );

/// Reacts to the user on screen 2. Navigation, snack bars and sheets stay in
/// the widget; this class only changes [DestinationState].
class DestinationController extends Notifier<DestinationState> {
  Timer? _distanceTimer;
  Timer? _placesTimer;
  int _placesSeq = 0;
  String? _sessionToken;
  DateTime? _distanceBlockedUntil;
  String _languageCode = 'vi';

  /// Set by [cancelPending] (the user left screen 2), cleared by [resume].
  /// While set, state still follows the user's input (a keystroke can reach
  /// the field after Back), but no Places request and no distance call is
  /// scheduled (test report T23 B2).
  bool _suspended = false;

  @override
  DestinationState build() {
    ref
      ..onDispose(() {
        _distanceTimer?.cancel();
        _placesTimer?.cancel();
        // An unfinished session is simply dropped (T23 §8).
        _sessionToken = null;
        _placesSeq++;
      })
      ..listen(stationCatalogProvider, (_, next) => _onCatalog(next));
    return DestinationState(catalog: ref.read(stationCatalogProvider));
  }

  /// App language for Places (`vi` or `en`).
  // A method, not a setter: the screen calls it from didChangeDependencies.
  // ignore: use_setters_to_change_properties
  void setLanguage(String languageCode) => _languageCode = languageCode;

  void setQuery(String query) {
    if (query == state.query) {
      return;
    }
    state = state.copyWith(query: query);
    if (state.filter == DestinationFilter.places) {
      _onPlacesQuery();
    } else {
      _refreshOffline();
    }
  }

  void setFilter(DestinationFilter filter) {
    final previous = state.filter;
    if (filter == previous) {
      return;
    }
    state = state.copyWith(filter: filter);
    if (previous == DestinationFilter.places) {
      _leavePlaces();
    }
    if (filter == DestinationFilter.places) {
      _distanceTimer?.cancel();
      unawaited(_enterPlaces());
    } else {
      _refreshOffline();
    }
  }

  /// A station row was tapped.
  void selectStation(Station s) {
    state = state.copyWith(
      selection: () => Selection(
        destination: TripDestination.fromStation(s),
        source: DestinationSource.station,
        anchor: MapPoint(s.lat, s.lng),
        anchorName: s.name,
      ),
      cameraRequestId: state.cameraRequestId + 1,
      undo: () => null,
    );
  }

  /// Whether [s] is the current selection (same name and original point).
  bool isSelectedStation(Station s) {
    final sel = state.selection;
    return sel != null &&
        sel.source == DestinationSource.station &&
        sel.anchorName == s.name &&
        sel.anchor == MapPoint(s.lat, s.lng);
  }

  /// A Places suggestion was tapped: reads its location and ends the
  /// session. True: chosen. False: the location could not be read (the list
  /// stays; the screen says so). Null: the tap was ignored (screen left,
  /// another suggestion resolving, no list) — nothing to tell the user
  /// (review T23 #13).
  Future<bool?> selectPrediction(PlacePrediction p) async {
    final current = state.places;
    if (_suspended ||
        current is! PlacesUiResults ||
        current.resolvingId != null) {
      return null;
    }
    // The tap ends the session: a pending debounce or an answer still in
    // flight must not start or show another Autocomplete (review T23 #1:
    // an extra request would belong to a session that never ends).
    _placesTimer?.cancel();
    _placesSeq++;
    final predictions = current.predictions;
    state = state.copyWith(
      places: PlacesUiResults(predictions, resolvingId: p.placeId),
    );
    final token =
        _sessionToken ?? newSessionToken(ref.read(placesRandomProvider));
    // The session ends with this Place Details call, success or not.
    _sessionToken = null;
    MapPoint? point;
    try {
      final client = await ref.read(placesClientProvider(_languageCode).future);
      point = await client.location(p.placeId, sessionToken: token);
    } on PlacesException {
      // T29: NonFatalReason.placesRequestFailed (no telemetry before T29).
    } on BridgeException {
      // mapsConfig() failed: same as a failed request.
    } on Object catch (error, stack) {
      reportNonFatal('destination.placeLocation', error, stack);
    }
    if (!ref.mounted) {
      return null;
    }
    final still = state.places;
    if (still is PlacesUiResults && still.resolvingId == p.placeId) {
      state = state.copyWith(places: PlacesUiResults(still.predictions));
    }
    final at = point;
    if (at == null) {
      // The user left meanwhile: no snack bar on a screen being closed.
      return _suspended ? null : false;
    }
    final selection = Selection(
      destination: TripDestination(
        name: p.mainText,
        lat: at.lat,
        lng: at.lng,
        kind: DestinationKind.address,
        detail: p.secondaryText,
      ),
      source: DestinationSource.places,
      anchor: at,
      anchorName: p.mainText,
    );
    state = state.copyWith(
      selection: () => selection,
      cameraRequestId: state.cameraRequestId + 1,
      undo: () => null,
    );
    return true;
  }

  /// Long press on the map: a new pin named [pinnedName] at [p]. The camera
  /// does not move.
  void dropPin(MapPoint p, {required String pinnedName}) {
    final previous = state.selection;
    state = state.copyWith(
      selection: () => Selection(
        destination: TripDestination(
          name: pinnedName,
          lat: p.lat,
          lng: p.lng,
          kind: DestinationKind.pin,
        ),
        source: DestinationSource.mapPin,
        anchor: p,
        anchorName: pinnedName,
      ),
      undo: () => PinUndo(previous),
    );
  }

  /// The pin was dragged to [to]. Returns how far it moved (metres), or null
  /// without a selection.
  double? movePin(
    MapPoint to, {
    required String pinnedName,
    required String Function(String place, double meters) pinnedDetail,
  }) {
    final current = state.selection;
    if (current == null) {
      return null;
    }
    final moved = distanceM(current.point, to);
    final next = afterPinMove(
      current: current.destination,
      currentSource: current.source,
      anchor: current.anchor,
      to: to,
      pinnedName: pinnedName,
      pinnedDetail: pinnedDetail,
    );
    // A pin is measured from where it is now; a kept station or address
    // from where it was chosen.
    final isPin = next.destination.kind == DestinationKind.pin;
    state = state.copyWith(
      selection: () => Selection(
        destination: next.destination,
        source: next.source,
        anchor: isPin ? to : current.anchor,
        anchorName: isPin ? pinnedName : current.anchorName,
      ),
      undo: () => PinUndo(current),
    );
    return moved;
  }

  /// Restores the selection before the latest pin drop or move.
  void undoPin() {
    final undo = state.undo;
    if (undo == null) {
      return;
    }
    state = state.copyWith(selection: () => undo.previous, undo: () => null);
  }

  // ------------------------------------------------------------ offline

  void _onCatalog(AsyncValue<StationCatalog> next) {
    state = state.copyWith(catalog: next);
    if (state.filter != DestinationFilter.places) {
      _refreshOffline();
    }
  }

  void _refreshOffline() {
    final index = state.catalog.value?.index;
    final rows = index == null
        ? const <StationMatch>[]
        : offlineResults(index, state.query, state.filter);
    state = state.copyWith(offline: rows);
    _scheduleDistances();
  }

  void _scheduleDistances() {
    _distanceTimer?.cancel();
    if (_suspended || state.offline.isEmpty) {
      return;
    }
    _distanceTimer = Timer(kDistanceDebounce, () => unawaited(_measure()));
  }

  Future<void> _measure() async {
    if (_suspended) {
      return;
    }
    final now = ref.read(clockProvider)();
    final blocked = _distanceBlockedUntil;
    if (blocked != null && now.isBefore(blocked)) {
      return;
    }
    final known = state.distanceByStationId;
    final stations = [
      for (final m in state.offline.take(kDisplayLimit))
        if (!known.containsKey(m.station.id)) m.station,
    ];
    if (stations.isEmpty) {
      return;
    }
    final pairs = [
      for (final s in stations) ...[s.lat, s.lng],
    ];
    List<double>? meters;
    try {
      meters = await ref
          .read(coreBridgeProvider)
          .distancesFromLastKnownM(pairs, kLastKnownMaxAgeMs);
    } on BridgeException {
      // T29: NonFatalReason.pigeonCallFailed (no telemetry before T29).
    } on Object catch (error, stack) {
      reportNonFatal('destination.distances', error, stack);
    }
    if (!ref.mounted) {
      return;
    }
    if (meters == null || meters.length != stations.length) {
      // No permission, location off or no recent fix: hide distances and
      // do not ask again for a while.
      _distanceBlockedUntil = now.add(kDistanceRetryAfter);
      return;
    }
    state = state.copyWith(
      distanceByStationId: {
        ...state.distanceByStationId,
        for (final (i, s) in stations.indexed)
          if (meters[i].isFinite && meters[i] >= 0) s.id: meters[i],
      },
    );
  }

  // ------------------------------------------------------------- places

  Future<void> _enterPlaces() async {
    _sessionToken = null;
    final MapsConfigMsg config;
    var cached = ref.read(mapsConfigProvider);
    if (cached.hasError) {
      // A failed read is not kept for the session: try again.
      ref.invalidate(mapsConfigProvider);
      cached = ref.read(mapsConfigProvider);
    }
    if (cached.hasValue) {
      config = cached.requireValue;
    } else {
      try {
        config = await ref.read(mapsConfigProvider.future);
      } on Object {
        if (ref.mounted && state.filter == DestinationFilter.places) {
          state = state.copyWith(places: const PlacesUiNotConfigured());
        }
        return;
      }
      if (!ref.mounted || state.filter != DestinationFilter.places) {
        return;
      }
    }
    final key = config.apiKey;
    if (key == null || key.trim().isEmpty) {
      state = state.copyWith(places: const PlacesUiNotConfigured());
      return;
    }
    state = state.copyWith(places: const PlacesUiTypeMore());
    _onPlacesQuery();
  }

  /// The user leaves screen 2 (Back, picker result, screen 3 on top): stops
  /// the debounces at once, drops answers still in flight and ends the
  /// Places session (test report T23 B1). The screen can stay mounted for
  /// an exit animation or under screen 3, so this cannot wait for dispose.
  void cancelPending() {
    _suspended = true;
    _distanceTimer?.cancel();
    _placesTimer?.cancel();
    _placesSeq++;
    _sessionToken = null;
  }

  /// Back on screen 2 from screen 3: redo what [cancelPending] stopped (a
  /// search that never got its answer, distances not measured yet). A new
  /// Places search opens a new session.
  void resume() {
    _suspended = false;
    if (state.filter == DestinationFilter.places) {
      if (state.places is PlacesUiLoading) {
        _onPlacesQuery();
      }
    } else {
      _scheduleDistances();
    }
  }

  void _leavePlaces() {
    _placesTimer?.cancel();
    _sessionToken = null;
    _placesSeq++;
  }

  void _onPlacesQuery() {
    _placesTimer?.cancel();
    if (state.places is PlacesUiNotConfigured) {
      return;
    }
    if (queryChars(state.query) < kMinPlacesQueryChars) {
      _placesSeq++;
      state = state.copyWith(places: const PlacesUiTypeMore());
      return;
    }
    if (_suspended) {
      // Left screen 2: remember that this query still needs a search
      // (resume() runs it), send nothing now (B2).
      _placesSeq++;
      state = state.copyWith(places: const PlacesUiLoading());
      return;
    }
    // Enough letters: say "searching" right away, not "type more" for the
    // whole debounce (review T23 #2). Suggestions already shown stay
    // tappable until the new answer arrives.
    if (state.places is! PlacesUiResults) {
      state = state.copyWith(places: const PlacesUiLoading());
    }
    final query = state.query;
    _placesTimer = Timer(
      kPlacesDebounce,
      () => unawaited(_autocomplete(query)),
    );
  }

  Future<void> _autocomplete(String query) async {
    if (_suspended) {
      return;
    }
    final seq = ++_placesSeq;
    final token = _sessionToken ??= newSessionToken(
      ref.read(placesRandomProvider),
    );
    if (state.places is! PlacesUiResults) {
      state = state.copyWith(places: const PlacesUiLoading());
    }
    PlacesUiState next;
    try {
      final client = await ref.read(placesClientProvider(_languageCode).future);
      final found = await client.autocomplete(query, sessionToken: token);
      next = found.isEmpty ? const PlacesUiEmpty() : PlacesUiResults(found);
    } on PlacesNotConfigured {
      next = const PlacesUiNotConfigured();
    } on PlacesNetworkError {
      next = const PlacesUiOffline();
    } on PlacesException {
      // T29: NonFatalReason.placesRequestFailed (no telemetry before T29).
      next = const PlacesUiUnavailable();
    } on BridgeException {
      next = const PlacesUiUnavailable();
    } on Object catch (error, stack) {
      reportNonFatal('destination.autocomplete', error, stack);
      next = const PlacesUiUnavailable();
    }
    if (!ref.mounted ||
        seq != _placesSeq ||
        state.filter != DestinationFilter.places) {
      return;
    }
    state = state.copyWith(places: next);
  }
}
