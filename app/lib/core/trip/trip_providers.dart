import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/db/db_providers.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/trip/data/saved_places_repository.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';

final tripsRepositoryProvider = Provider<TripsRepository>(
  (ref) => DriftTripsRepository(ref.watch(appDatabaseProvider)),
);

final savedPlacesRepositoryProvider = Provider<SavedPlacesRepository>(
  (ref) => DriftSavedPlacesRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// What screen 1 shows about the running trip (T22 §7.4).
///
/// PRIVACY: [toString] never prints the destination name.
@immutable
final class ActiveTripSummary {
  const new({
    required this.tripId,
    required this.destinationName,
    required this.phase,
  });

  final String tripId;
  final String destinationName;
  final TripPhaseMsg phase;

  ActiveTripSummary copyWith({TripPhaseMsg? phase}) => ActiveTripSummary(
    tripId: tripId,
    destinationName: destinationName,
    phase: phase ?? this.phase,
  );

  @override
  bool operator ==(Object other) =>
      other is ActiveTripSummary &&
      other.tripId == tripId &&
      other.destinationName == destinationName &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(tripId, destinationName, phase);

  @override
  String toString() => 'ActiveTripSummary(${phase.name})';
}

/// The running trip, or null. Reads the native snapshot once, then follows
/// the update stream. Bridge errors count as "no trip": screen 1 must never
/// be blocked by them. T26 may replace it with a richer provider but keeps
/// this name and type.
final activeTripProvider = StreamProvider<ActiveTripSummary?>((ref) {
  final bridge = ref.watch(coreBridgeProvider);
  return activeTripStream(bridge);
});

/// The algorithm of [activeTripProvider], exposed for unit tests.
///
/// - Subscribes to the updates before reading the snapshot and handles every
///   step in order, so no update is lost or applied out of order.
/// - Pause (Riverpod pauses a provider that lost its listeners, e.g. while
///   screen 4 covers the shell) **cancels** the update subscription instead
///   of buffering every update for hours; resume subscribes again and
///   re-reads the snapshot.
/// - A failing step is reported (type only) and never stops later steps.
/// - Not an `async*` function: cancelling one that waits inside `await for`
///   only returns at its next `yield`, which may never come.
Stream<ActiveTripSummary?> activeTripStream(CoreBridge bridge) {
  ActiveTripSummary? last;
  // Cancelled in unfollow() (pause and cancel); the lint does not see it
  // because the field is cleared before the await.
  // ignore: cancel_subscriptions
  StreamSubscription<TripUpdateMsg>? updates;
  var steps = Future<void>.value();
  late final StreamController<ActiveTripSummary?> controller;

  void emit(ActiveTripSummary? summary) {
    last = summary;
    if (!controller.isClosed) {
      controller.add(summary);
    }
  }

  Future<void> apply(TripUpdateMsg update) async {
    final current = last;
    switch (update) {
      case TripStateUpdateMsg(:final state):
        if (state.phase == TripPhaseMsg.ended) {
          emit(null);
        } else if (current == null || state.tripId != current.tripId) {
          emit(_summaryOf(await _currentTrip(bridge)));
        } else {
          emit(current.copyWith(phase: state.phase));
        }
      case TripEndedMsg(:final trip) when trip.tripId == current?.tripId:
        emit(null);
      default:
        break;
    }
  }

  void enqueue(Future<void> Function() step) {
    steps = steps.then((_) async {
      if (controller.isClosed) {
        return;
      }
      try {
        await step();
      } on Object catch (error, stack) {
        reportNonFatal('activeTripProvider', error, stack);
      }
    });
  }

  /// Follow the updates, then read the snapshot (first listen and resume).
  void follow() {
    updates ??= bridge.updates.listen(
      (update) => enqueue(() => apply(update)),
      // A broken update channel must not break screen 1.
      onError: (Object _) {},
    );
    enqueue(() async => emit(_summaryOf(await _currentTrip(bridge))));
  }

  Future<void> unfollow() async {
    // Cleared first: a resume during the await must subscribe again.
    final subscription = updates;
    updates = null;
    await subscription?.cancel();
  }

  controller = StreamController<ActiveTripSummary?>(
    onListen: follow,
    onPause: unfollow,
    onResume: follow,
    onCancel: () async {
      await unfollow();
      await controller.close();
    },
  );
  return controller.stream;
}

/// The snapshot, or null when it cannot be read. Bridge errors are expected
/// (no native side, channel error); anything else is reported.
Future<ActiveTripMsg?> _currentTrip(CoreBridge bridge) async {
  try {
    return await bridge.currentTrip();
  } on BridgeException {
    return null;
  } on Object catch (error, stack) {
    reportNonFatal('activeTripProvider.currentTrip', error, stack);
    return null;
  }
}

ActiveTripSummary? _summaryOf(ActiveTripMsg? trip) {
  if (trip == null || trip.state.phase == TripPhaseMsg.ended) {
    return null;
  }
  return ActiveTripSummary(
    tripId: trip.config.tripId,
    destinationName: trip.config.destinationName,
    phase: trip.state.phase,
  );
}
