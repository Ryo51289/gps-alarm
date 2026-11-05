/// The running trip as screen 4 shows it (T26 §3.1): config, simulation and
/// the latest view, plus a few events of this session.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';

/// PRIVACY: [toString] never prints the destination name or any distance.
@immutable
final class TrackedTrip {
  const new({
    required this.config,
    required this.simulation,
    required this.state,
    required this.receivedAtMs,
    this.acquiringSinceMs,
    this.neverAcquired = false,
    this.lowBattery,
  });

  /// No coordinates (T14 D5).
  final TripConfigMsg config;
  final SimulationMsg? simulation;

  /// The latest view.
  final TripStateMsg state;

  /// Real time (clock) when Dart received [state].
  final int receivedAtMs;

  /// Real time this session first saw the ACQUIRING phase of this trip;
  /// null in any other phase.
  final int? acquiringSinceMs;

  /// A `GpsLostMsg(neverAcquired)` was seen this session; cleared by
  /// `GpsRecoveredMsg` or a view whose GPS is no longer `noFixYet`.
  final bool neverAcquired;

  /// The latest `LowBatteryRiskMsg` of this session.
  final LowBatteryRiskMsg? lowBattery;

  String get tripId => config.tripId;

  bool get simulated => simulation != null;

  TrackedTrip copyWith({
    TripStateMsg? state,
    int? receivedAtMs,
    int? Function()? acquiringSinceMs,
    bool? neverAcquired,
    LowBatteryRiskMsg? lowBattery,
  }) => TrackedTrip(
    config: config,
    simulation: simulation,
    state: state ?? this.state,
    receivedAtMs: receivedAtMs ?? this.receivedAtMs,
    acquiringSinceMs: acquiringSinceMs == null
        ? this.acquiringSinceMs
        : acquiringSinceMs(),
    neverAcquired: neverAcquired ?? this.neverAcquired,
    lowBattery: lowBattery ?? this.lowBattery,
  );

  @override
  String toString() => 'TrackedTrip(${state.phase.name})';
}

/// What [trackedTripProvider] knows about the trip.
@immutable
sealed class TrackingStatus {
  const new();
}

final class TrackingActive extends TrackingStatus {
  const new(this.trip);

  final TrackedTrip trip;

  @override
  String toString() => 'TrackingActive($trip)';
}

/// The trip just ended (seen running, or the snapshot is ENDED).
final class TrackingEnded extends TrackingStatus {
  const new({required this.tripId, this.outcome, this.endReason});

  final String tripId;
  final TripOutcomeMsg? outcome;
  final EndReasonMsg? endReason;

  @override
  bool operator ==(Object other) =>
      other is TrackingEnded &&
      other.tripId == tripId &&
      other.outcome == outcome &&
      other.endReason == endReason;

  @override
  int get hashCode => Object.hash(tripId, outcome, endReason);

  @override
  String toString() => 'TrackingEnded(${outcome?.name}, ${endReason?.name})';
}

/// No trip.
final class TrackingNone extends TrackingStatus {
  const new();

  @override
  bool operator ==(Object other) => other is TrackingNone;

  @override
  int get hashCode => 0;
}

/// `currentTrip()` failed.
final class TrackingError extends TrackingStatus {
  const new();

  @override
  bool operator ==(Object other) => other is TrackingError;

  @override
  int get hashCode => 1;
}

final StreamProvider<TrackingStatus> trackedTripProvider =
    StreamProvider.autoDispose<TrackingStatus>(
      (ref) => trackedTripStream(
        ref.watch(coreBridgeProvider),
        nowMs: () => ref.read(clockProvider)().millisecondsSinceEpoch,
      ),
    );

/// The algorithm of [trackedTripProvider], exposed for unit tests (P01-P11).
///
/// Same frame as `activeTripStream` (T22): subscribes to the updates before
/// reading the snapshot, handles every step in order, pause cancels the
/// subscription and resume subscribes again and re-reads the snapshot.
Stream<TrackingStatus> trackedTripStream(
  CoreBridge bridge, {
  required int Function() nowMs,
}) {
  TrackingStatus? last;
  // Cancelled in unfollow() (pause and cancel); the lint does not see it
  // because the field is cleared before the await.
  // ignore: cancel_subscriptions
  StreamSubscription<TripUpdateMsg>? updates;
  var steps = Future<void>.value();
  late final StreamController<TrackingStatus> controller;

  void emit(TrackingStatus status) {
    last = status;
    if (!controller.isClosed) {
      controller.add(status);
    }
  }

  TrackingStatus fromSnapshot(ActiveTripMsg? snap) {
    if (snap == null) {
      return const TrackingNone();
    }
    if (snap.state.phase == TripPhaseMsg.ended) {
      return TrackingEnded(
        tripId: snap.config.tripId,
        outcome: snap.state.outcome,
      );
    }
    final now = nowMs();
    return TrackingActive(
      TrackedTrip(
        config: snap.config,
        simulation: snap.simulation,
        state: snap.state,
        receivedAtMs: now,
        acquiringSinceMs: snap.state.phase == TripPhaseMsg.acquiring
            ? now
            : null,
      ),
    );
  }

  Future<void> loadSnapshot() async {
    final ActiveTripMsg? snap;
    try {
      snap = await bridge.currentTrip();
    } on BridgeException {
      emit(const TrackingError());
      return;
    } on Object catch (error, stack) {
      reportNonFatal('trackedTripProvider.currentTrip', error, stack);
      emit(const TrackingError());
      return;
    }
    emit(fromSnapshot(snap));
  }

  Future<void> apply(TripUpdateMsg update) async {
    final status = last;
    final current = status is TrackingActive ? status.trip : null;
    final ended = status is TrackingEnded ? status.tripId : null;
    switch (update) {
      case TripStateUpdateMsg(:final state):
        if (state.tripId == ended) {
          return; // Nothing follows an end (T15 §5.11); just in case.
        }
        if (state.phase == TripPhaseMsg.ended) {
          emit(TrackingEnded(tripId: state.tripId, outcome: state.outcome));
        } else if (current == null || state.tripId != current.tripId) {
          await loadSnapshot(); // The config of the new trip.
        } else if (state.atMs < current.state.atMs) {
          // A replay older than the snapshot; the trip clock never goes back
          // (T10 §2.6).
        } else {
          final now = nowMs();
          emit(
            TrackingActive(
              current.copyWith(
                state: state,
                receivedAtMs: now,
                acquiringSinceMs: () => state.phase == TripPhaseMsg.acquiring
                    ? (current.acquiringSinceMs ?? now)
                    : null,
                neverAcquired:
                    state.gps == GpsStatusMsg.noFixYet && current.neverAcquired,
              ),
            ),
          );
        }
      case GpsLostMsg(:final tripId, :final cause)
          when current != null &&
              tripId == current.tripId &&
              cause == GpsLostCauseMsg.neverAcquired:
        emit(TrackingActive(current.copyWith(neverAcquired: true)));
      case GpsRecoveredMsg(:final tripId)
          when current != null && tripId == current.tripId:
        emit(TrackingActive(current.copyWith(neverAcquired: false)));
      case LowBatteryRiskMsg(:final tripId)
          when current != null && tripId == current.tripId:
        emit(TrackingActive(current.copyWith(lowBattery: update)));
      case TripEndedMsg(:final trip)
          when (current != null && trip.tripId == current.tripId) ||
              (status is TrackingEnded &&
                  status.tripId == trip.tripId &&
                  status.endReason == null):
        // Also completes an end first seen as an ENDED view: the engine sends
        // the view of the Step before its TripEnded event (T10 §2.3).
        emit(
          TrackingEnded(
            tripId: trip.tripId,
            outcome: trip.outcome,
            endReason: trip.endReason,
          ),
        );
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
        reportNonFatal('trackedTripProvider', error, stack);
      }
    });
  }

  void follow() {
    updates ??= bridge.updates.listen(
      (update) => enqueue(() => apply(update)),
      // A broken update channel must not break screen 4.
      onError: (Object _) {},
    );
    enqueue(loadSnapshot);
  }

  Future<void> unfollow() async {
    // Cleared first: a resume during the await must subscribe again.
    final subscription = updates;
    updates = null;
    await subscription?.cancel();
  }

  controller = StreamController<TrackingStatus>(
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
