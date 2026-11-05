/// The state machine of `AlarmUiCoordinator` (T27 §4.3, D1): when the app is
/// visible and a ring goes on, wait [kRingUiGrace]; still visible → ask the
/// native side to show its alarm screen; it says no, or it said yes but the
/// app is still visible after one more grace → push the Flutter fallback
/// screen. Pure; time comes in as [GraceElapsed].
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm/domain/ring_ui_rules.dart';

sealed class RingUiInput {
  const new();
}

/// The app became `resumed` ([resumed]) or left it.
final class LifecycleChanged extends RingUiInput {
  const new({required this.resumed});

  final bool resumed;
}

/// Latest engine view; null = no trip / the trip ended.
final class StateSeen extends RingUiInput {
  const new(this.state);

  final TripStateMsg? state;
}

/// The grace timer of [StartGrace] fired.
final class GraceElapsed extends RingUiInput {
  const new(this.tripId, this.generation);

  final String tripId;
  final int generation;
}

/// Answer of `showAlarmScreen` for [AskNative].
final class NativeAnswered extends RingUiInput {
  const new(this.tripId, this.generation, {required this.shown});

  final String tripId;
  final int generation;
  final bool shown;
}

/// The fallback screen (`/alarm`) was popped.
final class FallbackClosed extends RingUiInput {
  const new();
}

@immutable
sealed class RingUiEffect {
  const new();
}

/// (Re)starts the grace timer: after [kRingUiGrace] → [GraceElapsed].
final class StartGrace extends RingUiEffect {
  const new(this.tripId, this.generation);

  final String tripId;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is StartGrace &&
      other.tripId == tripId &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(StartGrace, tripId, generation);

  @override
  String toString() => 'StartGrace($generation)';
}

/// Cancels the grace timer.
final class CancelGrace extends RingUiEffect {
  const new();

  @override
  bool operator ==(Object other) => other is CancelGrace;

  @override
  int get hashCode => (CancelGrace).hashCode;

  @override
  String toString() => 'CancelGrace';
}

/// Calls `showAlarmScreen(tripId)` → [NativeAnswered].
final class AskNative extends RingUiEffect {
  const new(this.tripId, this.generation);

  final String tripId;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is AskNative &&
      other.tripId == tripId &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(AskNative, tripId, generation);

  @override
  String toString() => 'AskNative($generation)';
}

/// Pushes `/alarm?trip=<tripId>`.
final class PushFallback extends RingUiEffect {
  const new(this.tripId);

  final String tripId;

  @override
  bool operator ==(Object other) =>
      other is PushFallback && other.tripId == tripId;

  @override
  int get hashCode => Object.hash(PushFallback, tripId);

  @override
  String toString() => 'PushFallback';
}

enum RingUiStage { idle, grace, askingNative, waitingNative, fallbackShown }

@immutable
final class RingUiState {
  const new({
    this.resumed = false,
    this.ringingTripId,
    this.stage = RingUiStage.idle,
    this.generation = 0,
  });

  final bool resumed;

  /// Trip whose alarm sounds now, or null.
  final String? ringingTripId;
  final RingUiStage stage;

  /// Bumped whenever a pending timer or answer must be ignored.
  final int generation;

  RingUiState _copy({
    bool? resumed,
    bool clearTrip = false,
    String? ringingTripId,
    RingUiStage? stage,
    int? generation,
  }) => RingUiState(
    resumed: resumed ?? this.resumed,
    ringingTripId: clearTrip ? null : ringingTripId ?? this.ringingTripId,
    stage: stage ?? this.stage,
    generation: generation ?? this.generation,
  );

  @override
  bool operator ==(Object other) =>
      other is RingUiState &&
      other.resumed == resumed &&
      other.ringingTripId == ringingTripId &&
      other.stage == stage &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(resumed, ringingTripId, stage, generation);

  /// PRIVACY: no trip id.
  @override
  String toString() => 'RingUiState($resumed, ${stage.name}, $generation)';
}

typedef RingUiStep = (RingUiState, List<RingUiEffect>);

/// One step of the machine. Invariants: never [PushFallback] while not
/// resumed; at most one [PushFallback] each time the stage leaves `idle`.
RingUiStep reduceRingUi(RingUiState s, RingUiInput input) => switch (input) {
  LifecycleChanged(resumed: false) => (
    s._copy(
      resumed: false,
      stage: s.stage == RingUiStage.fallbackShown ? s.stage : RingUiStage.idle,
      generation: s.generation + 1,
    ),
    const [CancelGrace()],
  ),
  LifecycleChanged(resumed: true) => _onResumed(s),
  StateSeen(:final state) => _onState(s, state),
  GraceElapsed(:final tripId, :final generation) =>
    !_current(s, tripId, generation)
        ? (s, const [])
        : switch (s.stage) {
            RingUiStage.grace => (
              s._copy(stage: RingUiStage.askingNative),
              [AskNative(tripId, generation)],
            ),
            RingUiStage.waitingNative => (
              s._copy(stage: RingUiStage.fallbackShown),
              [PushFallback(tripId)],
            ),
            _ => (s, const []),
          },
  NativeAnswered(:final tripId, :final generation, :final shown) =>
    !_current(s, tripId, generation) || s.stage != RingUiStage.askingNative
        ? (s, const [])
        : shown
        // Started, but still visible after one more grace → fallback.
        ? (
            s._copy(stage: RingUiStage.waitingNative),
            [StartGrace(tripId, generation)],
          )
        : (s._copy(stage: RingUiStage.fallbackShown), [PushFallback(tripId)]),
  FallbackClosed() => _onFallbackClosed(s),
};

RingUiStep _onResumed(RingUiState s) {
  if (s.resumed) {
    return (s, const []);
  }
  final resumed = s._copy(resumed: true);
  final id = s.ringingTripId;
  return id != null && s.stage == RingUiStage.idle
      ? _grace(resumed, id)
      : (resumed, const []);
}

RingUiStep _onState(RingUiState s, TripStateMsg? state) {
  final id = ringingNow(state) ? state!.tripId : null;
  if (id == null) {
    if (s.ringingTripId == null && s.stage == RingUiStage.idle) {
      return (s, const []);
    }
    if (s.stage == RingUiStage.fallbackShown) {
      // The fallback screen pops itself; FallbackClosed follows.
      return (s._copy(clearTrip: true), const []);
    }
    return (
      s._copy(
        clearTrip: true,
        stage: RingUiStage.idle,
        generation: s.generation + 1,
      ),
      const [CancelGrace()],
    );
  }
  if (id == s.ringingTripId) {
    return (s, const []);
  }
  final next = s._copy(ringingTripId: id);
  return s.resumed && s.stage != RingUiStage.fallbackShown
      ? _grace(next, id)
      : (next, const []);
}

RingUiStep _onFallbackClosed(RingUiState s) {
  if (s.stage != RingUiStage.fallbackShown) {
    return (s, const []);
  }
  final idle = s._copy(stage: RingUiStage.idle);
  final id = s.ringingTripId;
  return id != null && s.resumed ? _grace(idle, id) : (idle, const []);
}

/// A timer or answer of the current generation, for the ringing trip, while
/// the app is visible.
bool _current(RingUiState s, String tripId, int generation) =>
    s.resumed && generation == s.generation && tripId == s.ringingTripId;

RingUiStep _grace(RingUiState s, String id) {
  final generation = s.generation + 1;
  return (
    s._copy(stage: RingUiStage.grace, generation: generation),
    [StartGrace(id, generation)],
  );
}
