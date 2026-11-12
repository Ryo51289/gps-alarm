/// State machine of screen 2 "Chọn điểm đến" (T23 §8, §10). Lives only in
/// memory while the screen is shown (autoDispose).
///
/// PRIVACY: never log the query, a name or coordinates; `toString` of every
/// type here prints none of them.
library;

import 'dart:async';

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;
import 'package:meta/meta.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/address_search_client.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// The selection before the latest pin drop or move ([previous] null: there
/// was none).
@immutable
final class PinUndo {
  const new(this.previous);

  final Selection? previous;

  @override
  String toString() => 'PinUndo(${previous != null})';
}

/// What the address section of screen 2 shows (T23.5 §4.3).
///
/// PRIVACY: `toString` prints the class name and a row count only.
@immutable
sealed class AddressUiState {
  const new();
}

/// Off: address search disabled on this platform, a chip other than "Tất
/// cả", or a query too short.
final class AddressHidden extends AddressUiState {
  const new();

  @override
  String toString() => 'AddressHidden';
}

/// A request is waiting or running; [previous] rows stay visible.
final class AddressLoading extends AddressUiState {
  const new(this.previous);

  final List<AddressRow> previous;

  @override
  String toString() => 'AddressLoading(${previous.length})';
}

/// Suggestions; [resolvingIndex] is the native index being located.
final class AddressResults extends AddressUiState {
  const new(this.rows, {this.resolvingIndex});

  final List<AddressRow> rows;
  final int? resolvingIndex;

  @override
  String toString() => 'AddressResults(${rows.length})';
}

final class AddressEmpty extends AddressUiState {
  const new();

  @override
  String toString() => 'AddressEmpty';
}

final class AddressOffline extends AddressUiState {
  const new();

  @override
  String toString() => 'AddressOffline';
}

final class AddressThrottled extends AddressUiState {
  const new();

  @override
  String toString() => 'AddressThrottled';
}

final class AddressUnavailable extends AddressUiState {
  const new();

  @override
  String toString() => 'AddressUnavailable';
}

/// Most rows (stations, then bus stops) measured per "cách X km" request
/// (T24.3 §6.4; the native side accepts up to 50 points, T14).
const int kMaxDistanceRows = 25;

/// Outcome of [DestinationController.selectAddress].
enum AddressPick { picked, outsideArea, failed, offline, ignored }

/// Everything screen 2 shows.
@immutable
final class DestinationState {
  const new({
    required this.catalog,
    this.query = '',
    this.filter = DestinationFilter.all,
    this.offline = const [],
    this.busCatalog,
    this.busStops = const [],
    this.distanceByStationId = const {},
    this.selection,
    this.cameraRequestId = 0,
    this.undo,
    this.address = const AddressHidden(),
  });

  final String query;
  final DestinationFilter filter;
  final AsyncValue<StationCatalog> catalog;

  /// Station rows of the current query and filter.
  final List<StationMatch> offline;

  /// The bus stop catalog (T24.3 D10); null until it was first needed.
  final AsyncValue<StationCatalog>? busCatalog;

  /// Bus stop rows of the current query and filter (T24.3 §6.4).
  final List<StationMatch> busStops;

  /// "cách X km" per station id, already rounded by the native side (10 m
  /// under 1 km, 100 m above). PRIVACY: location data — several distances
  /// to public stations locate the user. Kept in this screen's memory only:
  /// never logged, persisted, printed by toString or sent to telemetry.
  final Map<String, double> distanceByStationId;
  final Selection? selection;

  /// Grows when the map should frame a newly chosen destination.
  final int cameraRequestId;
  final PinUndo? undo;

  /// The address section (T23.5).
  final AddressUiState address;

  DestinationState copyWith({
    String? query,
    DestinationFilter? filter,
    AsyncValue<StationCatalog>? catalog,
    List<StationMatch>? offline,
    AsyncValue<StationCatalog>? Function()? busCatalog,
    List<StationMatch>? busStops,
    Map<String, double>? distanceByStationId,
    Selection? Function()? selection,
    int? cameraRequestId,
    PinUndo? Function()? undo,
    AddressUiState? address,
  }) => DestinationState(
    query: query ?? this.query,
    filter: filter ?? this.filter,
    catalog: catalog ?? this.catalog,
    offline: offline ?? this.offline,
    busCatalog: busCatalog == null ? this.busCatalog : busCatalog(),
    busStops: busStops ?? this.busStops,
    distanceByStationId: distanceByStationId ?? this.distanceByStationId,
    selection: selection == null ? this.selection : selection(),
    cameraRequestId: cameraRequestId ?? this.cameraRequestId,
    undo: undo == null ? this.undo : undo(),
    address: address ?? this.address,
  );

  /// PRIVACY: no query, no name, no coordinates.
  @override
  String toString() =>
      'DestinationState(${filter.name}, rows: ${offline.length}, '
      'bus stops: ${busStops.length}, '
      '${address.runtimeType}, $selection)';
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
  DateTime? _distanceBlockedUntil;

  // T24.3 bus stops: listened to from the first time D10 holds.
  ProviderSubscription<AsyncValue<StationCatalog>>? _busSub;
  bool _busReported = false;

  // T23.5 address search.
  AddressSearchClient? _client;
  bool _addressEnabled = false;
  Timer? _addressTimer;
  int _addressGen = 0;
  DateTime? _throttledUntil;
  bool _addressReported = false;

  /// A request may have reached the native side (dispose cancels it).
  bool _addressUsed = false;

  /// Set by [cancelPending] (the user left screen 2), cleared by [resume].
  /// While set, state still follows the user's input (a keystroke can reach
  /// the field after Back), but no distance call is scheduled (test report
  /// T23 B2).
  bool _suspended = false;

  @override
  DestinationState build() {
    _client = ref.read(addressSearchClientProvider);
    _addressEnabled = ref.read(addressSearchEnabledProvider);
    ref
      ..onDispose(() {
        _distanceTimer?.cancel();
        _addressTimer?.cancel();
        _addressGen++;
        if (_addressUsed) {
          unawaited(_cancelNative());
        }
      })
      ..listen(stationCatalogProvider, (_, next) => _onCatalog(next));
    return DestinationState(catalog: ref.read(stationCatalogProvider));
  }

  void setQuery(String query) {
    if (query == state.query) {
      return;
    }
    state = state.copyWith(query: query);
    _refreshOffline();
    _scheduleAddress();
  }

  void setFilter(DestinationFilter filter) {
    // D10: tapping "Trạm buýt" again after a failed load tries again.
    if (filter == DestinationFilter.busStop &&
        state.busCatalog?.hasError == true) {
      retryBusStops();
    }
    if (filter == state.filter) {
      return;
    }
    state = state.copyWith(filter: filter);
    _refreshOffline();
    _scheduleAddress();
  }

  /// Loads the bus stops again after a failure ("Thử lại", chip tapped).
  void retryBusStops() {
    final bus = state.busCatalog;
    if (bus == null || !bus.hasError || bus.isLoading) {
      return;
    }
    ref.invalidate(busStopCatalogProvider);
  }

  /// A station or bus stop row was tapped.
  void selectStation(Station s) {
    state = state.copyWith(
      selection: () => Selection(
        destination: TripDestination.fromStation(s),
        source: DestinationSource.station,
        anchor: MapPoint(s.lat, s.lng),
        anchorName: s.name,
        busStop: s.kind == StationKind.busStop,
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
        busStop: !isPin && current.busStop,
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
    _refreshOffline();
  }

  void _refreshOffline() {
    _ensureBusStops();
    final index = state.catalog.value?.index;
    final rows = index == null
        ? const <StationMatch>[]
        : offlineResults(index, state.query, state.filter);
    final busIndex = state.busCatalog?.value?.index;
    final bus = busIndex == null
        ? const <StationMatch>[]
        : busStopResults(busIndex, state.query, state.filter);
    state = state.copyWith(offline: rows, busStops: bus);
    _scheduleDistances();
  }

  /// D10: starts loading the bus stops the first time they are needed.
  void _ensureBusStops() {
    if (_busSub != null || !shouldLoadBusStops(state.query, state.filter)) {
      return;
    }
    final sub = ref.listen(
      busStopCatalogProvider,
      (_, next) => _onBusCatalog(next),
    );
    _busSub = sub;
    final now = sub.read();
    state = state.copyWith(busCatalog: () => now);
    _reportBusFailure(now);
  }

  void _onBusCatalog(AsyncValue<StationCatalog> next) {
    state = state.copyWith(busCatalog: () => next);
    _reportBusFailure(next);
    _refreshOffline();
  }

  /// D10: a failed load is reported once per screen, error type only (the
  /// station search keeps working).
  void _reportBusFailure(AsyncValue<StationCatalog> value) {
    final error = value.error;
    if (_busReported || error == null || value.isLoading) {
      return;
    }
    _busReported = true;
    try {
      ref
          .read(telemetryProvider)
          .crash
          .recordNonFatal(
            error,
            value.stackTrace ?? StackTrace.empty,
            NonFatalReason.stationCatalogLoadFailed,
          );
    } on Object {
      // Telemetry never breaks the search.
    }
  }

  void _scheduleDistances() {
    _distanceTimer?.cancel();
    if (_suspended || (state.offline.isEmpty && state.busStops.isEmpty)) {
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
      for (final m in [
        ...state.offline.take(kDisplayLimit),
        ...state.busStops,
      ].take(kMaxDistanceRows))
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

  // ------------------------------------------------------------ address

  /// Whether an error of the address channel is one the channel can raise
  /// (D13); anything else is a bug and propagates.
  static bool _isChannelError(Object e) =>
      e is PlatformException ||
      e is MissingPluginException ||
      e is AddressSearchProtocolException;

  /// D13: once per controller, error type only.
  void _reportAddressFailure(Object error, StackTrace stack) {
    if (_addressReported) {
      return;
    }
    _addressReported = true;
    try {
      ref
          .read(telemetryProvider)
          .crash
          .recordNonFatal(error, stack, NonFatalReason.addressSearchFailed);
    } on Object {
      // Telemetry never breaks the search.
    }
  }

  Future<void> _cancelNative() async {
    try {
      await _client?.cancel();
    } on Object {
      // Nothing to cancel, or no native side (tests): either way done.
    }
  }

  List<AddressRow> get _currentRows => switch (state.address) {
    AddressResults(:final rows) => rows,
    AddressLoading(:final previous) => previous,
    _ => const [],
  };

  /// D5, D10: (re)starts the debounce for the current query and chip, or
  /// hides the section.
  void _scheduleAddress() {
    _addressTimer?.cancel();
    if (!_addressEnabled ||
        !shouldSearchAddresses(query: state.query, filter: state.filter)) {
      if (state.address is! AddressHidden) {
        unawaited(_cancelNative());
        _addressGen++;
        state = state.copyWith(address: const AddressHidden());
      }
      return;
    }
    if (_suspended) {
      return;
    }
    final until = _throttledUntil;
    if (until != null && ref.read(clockProvider)().isBefore(until)) {
      state = state.copyWith(address: const AddressThrottled());
      return;
    }
    _addressUsed = true;
    state = state.copyWith(address: AddressLoading(_currentRows));
    _addressTimer = Timer(kAddressDebounce, () => unawaited(_complete()));
  }

  Future<void> _complete() async {
    final client = _client;
    if (client == null || _suspended || !ref.mounted) {
      return;
    }
    final gen = ++_addressGen;
    final query = addressQueryOf(state.query);
    final CompleteReply reply;
    try {
      reply = await client.complete(gen: gen, query: query);
    } on Object catch (error, stack) {
      if (!_isChannelError(error)) {
        rethrow;
      }
      if (_isStale(gen)) {
        return;
      }
      _reportAddressFailure(error, stack);
      state = state.copyWith(address: const AddressUnavailable());
      return;
    }
    // A late answer, one of a superseded request, or one for a text the
    // user has since changed is dropped.
    if (_isStale(gen) ||
        reply.gen != gen ||
        addressQueryOf(state.query) != query) {
      return;
    }
    switch (reply.status) {
      case AddressStatus.ok:
        final rows = visibleSuggestions(reply.items);
        state = state.copyWith(
          address: rows.isEmpty ? const AddressEmpty() : AddressResults(rows),
        );
      case AddressStatus.network:
        state = state.copyWith(address: const AddressOffline());
      case AddressStatus.throttled:
        _throttledUntil = ref
            .read(clockProvider)()
            .add(kAddressThrottleCooldown);
        state = state.copyWith(address: const AddressThrottled());
      case AddressStatus.superseded:
        break;
      case AddressStatus.failed ||
          AddressStatus.timeout ||
          AddressStatus.stale ||
          AddressStatus.notFound:
        state = state.copyWith(address: const AddressUnavailable());
    }
  }

  bool _isStale(int gen) => !ref.mounted || _suspended || gen != _addressGen;

  /// An address row (native index [nativeIndex]) was tapped: asks Apple
  /// for its location. The widget decides what to show from the result.
  Future<AddressPick> selectAddress(int nativeIndex) async {
    final client = _client;
    final current = state.address;
    if (client == null ||
        current is! AddressResults ||
        current.resolvingIndex != null) {
      return AddressPick.ignored;
    }
    final suggestion = [
      for (final r in current.rows)
        if (r.nativeIndex == nativeIndex) r.suggestion,
    ].firstOrNull;
    if (suggestion == null) {
      return AddressPick.ignored;
    }
    final gen = _addressGen;
    final query0 = state.query;
    state = state.copyWith(
      address: AddressResults(current.rows, resolvingIndex: nativeIndex),
    );
    final ResolveReply reply;
    try {
      reply = await client.resolve(gen: gen, index: nativeIndex);
    } on Object catch (error, stack) {
      if (!_isChannelError(error)) {
        rethrow;
      }
      if (!ref.mounted || gen != _addressGen || state.query != query0) {
        return AddressPick.ignored;
      }
      _reportAddressFailure(error, stack);
      state = state.copyWith(address: const AddressUnavailable());
      return AddressPick.failed;
    }
    if (!ref.mounted || gen != _addressGen || state.query != query0) {
      return AddressPick.ignored;
    }
    state = state.copyWith(address: AddressResults(current.rows));
    switch (reply.status) {
      case AddressStatus.ok:
        final p = reply.point;
        if (p == null) {
          return AddressPick.failed;
        }
        if (!isSupportedDestination(p, country: reply.country)) {
          return AddressPick.outsideArea;
        }
        final destination = addressDestination(suggestion, p);
        state = state.copyWith(
          selection: () => Selection(
            destination: destination,
            source: DestinationSource.places,
            anchor: p,
            anchorName: destination.name,
          ),
          cameraRequestId: state.cameraRequestId + 1,
          undo: () => null,
        );
        return AddressPick.picked;
      case AddressStatus.network:
        return AddressPick.offline;
      case AddressStatus.throttled:
        _throttledUntil = ref
            .read(clockProvider)()
            .add(kAddressThrottleCooldown);
        return AddressPick.failed;
      case AddressStatus.stale:
        // Apple's list moved on under us: ask again.
        _scheduleAddress();
        return AddressPick.failed;
      case AddressStatus.superseded:
        return AddressPick.ignored;
      case AddressStatus.notFound ||
          AddressStatus.failed ||
          AddressStatus.timeout:
        return AddressPick.failed;
    }
  }

  /// Whether [s] is the current selection (same name and detail, chosen
  /// from Apple's suggestions).
  bool isSelectedAddress(AddressSuggestion s) {
    final sel = state.selection;
    if (sel == null || sel.source != DestinationSource.places) {
      return false;
    }
    final d = addressDestination(s, sel.anchor);
    return sel.anchorName == d.name && sel.destination.detail == d.detail;
  }

  /// [resume] after a [cancelPending] that dropped a waiting request or an
  /// answer: nothing may stay "loading" or "getting location" for good.
  void _settleAddress() {
    switch (state.address) {
      case AddressLoading(:final previous):
        state = state.copyWith(
          address: previous.isEmpty
              ? const AddressHidden()
              : AddressResults(previous),
        );
      case AddressResults(:final rows, :final resolvingIndex)
          when resolvingIndex != null:
        state = state.copyWith(address: AddressResults(rows));
      default:
        break;
    }
  }

  // ------------------------------------------------------------ leaving

  /// The user leaves screen 2 (Back, picker result, screen 3 on top): stops
  /// the distance debounce at once (test report T23 B1, T27 D11). The
  /// screen can stay mounted for an exit animation or under screen 3, so
  /// this cannot wait for dispose.
  void cancelPending() {
    _suspended = true;
    _distanceTimer?.cancel();
    _addressTimer?.cancel();
    _addressGen++;
    unawaited(_cancelNative());
  }

  /// Back on screen 2 from screen 3: redo what [cancelPending] stopped
  /// (distances not measured yet).
  void resume() {
    _suspended = false;
    _settleAddress();
    _scheduleDistances();
  }
}
