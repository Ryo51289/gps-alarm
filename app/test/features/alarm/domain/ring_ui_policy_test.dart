// T27 U07–U09: the coordinator state machine (§4.3) driven by a fake clock
// (one grace timer, like AlarmUiCoordinator).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm/domain/ring_ui_policy.dart';
import 'package:napstop/features/alarm/domain/ring_ui_rules.dart';

import '../../../helpers/fake_core_bridge.dart';

TripStateMsg _ringing(
  String id, {
  TripPhaseMsg phase = TripPhaseMsg.alarming,
}) => tripState(tripId: id, phase: phase)..alarmRinging = true;

/// Runs the machine with a fake clock and records the effects.
class _Driver {
  RingUiState state = const RingUiState();
  final List<RingUiEffect> effects = [];
  int nowMs = 0;
  ({int atMs, String tripId, int generation})? timer;

  void input(RingUiInput i) {
    final (next, fx) = reduceRingUi(state, i);
    state = next;
    for (final f in fx) {
      effects.add(f);
      switch (f) {
        case StartGrace(:final tripId, :final generation):
          timer = (
            atMs: nowMs + kRingUiGrace.inMilliseconds,
            tripId: tripId,
            generation: generation,
          );
        case CancelGrace():
          timer = null;
        default:
          break;
      }
    }
  }

  void advance(Duration d) {
    final end = nowMs + d.inMilliseconds;
    while (true) {
      final t = timer;
      if (t == null || t.atMs > end) {
        break;
      }
      nowMs = t.atMs;
      timer = null;
      input(GraceElapsed(t.tripId, t.generation));
    }
    nowMs = end;
  }

  Iterable<T> of<T>() => effects.whereType<T>();
}

void main() {
  test('U07 a ring shorter than the grace does nothing', () {
    final d = _Driver()
      ..input(const LifecycleChanged(resumed: true))
      ..input(StateSeen(_ringing('trip-1')))
      ..advance(const Duration(milliseconds: 3900))
      ..input(StateSeen(tripState()))
      ..advance(const Duration(seconds: 30));
    expect(d.of<AskNative>(), isEmpty);
    expect(d.of<PushFallback>(), isEmpty);
    expect(d.state.stage, RingUiStage.idle);
  });

  test('U08 after 4 s: ask native once; yes + 4 s → fallback once', () {
    final d = _Driver()
      ..input(const LifecycleChanged(resumed: true))
      ..input(StateSeen(_ringing('trip-1')))
      ..advance(kRingUiGrace);
    expect(d.of<AskNative>().toList(), [
      AskNative('trip-1', d.state.generation),
    ]);
    // The same ring again (1 update per second) changes nothing.
    d
      ..input(StateSeen(_ringing('trip-1')))
      ..input(NativeAnswered('trip-1', d.state.generation, shown: true))
      ..advance(const Duration(milliseconds: 3999));
    expect(d.of<PushFallback>(), isEmpty);
    d.advance(const Duration(milliseconds: 1));
    expect(d.of<PushFallback>().toList(), [const PushFallback('trip-1')]);
    expect(d.state.stage, RingUiStage.fallbackShown);
    d
      ..input(StateSeen(_ringing('trip-1')))
      ..advance(const Duration(minutes: 1));
    expect(d.of<PushFallback>(), hasLength(1));
    expect(d.of<AskNative>(), hasLength(1));

    // Native says no → fallback at once.
    final no = _Driver()
      ..input(const LifecycleChanged(resumed: true))
      ..input(StateSeen(_ringing('trip-1')))
      ..advance(kRingUiGrace);
    no.input(NativeAnswered('trip-1', no.state.generation, shown: false));
    expect(no.of<PushFallback>().toList(), [const PushFallback('trip-1')]);
  });

  test('U08 the fallback closed while still ringing → a new cycle', () {
    final d = _Driver()
      ..input(const LifecycleChanged(resumed: true))
      ..input(StateSeen(_ringing('trip-1')))
      ..advance(kRingUiGrace);
    d
      ..input(NativeAnswered('trip-1', d.state.generation, shown: false))
      ..input(const FallbackClosed());
    expect(d.state.stage, RingUiStage.grace);
    d.advance(kRingUiGrace);
    expect(d.of<AskNative>(), hasLength(2));
    // Ring over while the fallback is shown: it pops itself, then idle.
    d
      ..input(NativeAnswered('trip-1', d.state.generation, shown: false))
      ..input(StateSeen(tripState()));
    expect(d.state.stage, RingUiStage.fallbackShown);
    d.input(const FallbackClosed());
    expect(d.state.stage, RingUiStage.idle);
    d.advance(const Duration(minutes: 1));
    expect(d.of<PushFallback>(), hasLength(2));
  });

  test('U09 leaving resumed drops the pending answer', () {
    final d = _Driver()
      ..input(const LifecycleChanged(resumed: true))
      ..input(StateSeen(_ringing('trip-1')))
      ..advance(kRingUiGrace);
    final asked = d.state.generation;
    d
      ..input(const LifecycleChanged(resumed: false))
      ..input(NativeAnswered('trip-1', asked, shown: false))
      ..input(GraceElapsed('trip-1', asked))
      ..advance(const Duration(minutes: 1));
    expect(d.of<PushFallback>(), isEmpty);
    expect(d.state.stage, RingUiStage.idle);
    // Back to resumed while it still rings: a new grace.
    d.input(const LifecycleChanged(resumed: true));
    expect(d.state.stage, RingUiStage.grace);
    // Another trip id or generation is ignored.
    d.advance(kRingUiGrace);
    d
      ..input(NativeAnswered('trip-2', d.state.generation, shown: false))
      ..input(NativeAnswered('trip-1', d.state.generation - 1, shown: false));
    expect(d.of<PushFallback>(), isEmpty);
  });

  test('not resumed: a ring never starts a grace', () {
    final d = _Driver()
      ..input(StateSeen(_ringing('trip-1', phase: TripPhaseMsg.overshot)))
      ..advance(const Duration(minutes: 5));
    expect(d.effects.whereType<StartGrace>(), isEmpty);
    expect(d.state.ringingTripId, 'trip-1');
  });

  test('U09 invariants on 1 000 random input sequences', () {
    final random = Random(27);
    const trips = ['trip-1', 'trip-2'];
    for (var run = 0; run < 1000; run++) {
      var s = const RingUiState();
      var pushes = 0;
      for (var step = 0; step < 40; step++) {
        final gen = s.generation + random.nextInt(3) - 1;
        final trip = trips[random.nextInt(2)];
        final input = switch (random.nextInt(7)) {
          0 => LifecycleChanged(resumed: random.nextBool()),
          1 => StateSeen(_ringing(trip)),
          2 => StateSeen(random.nextBool() ? null : tripState(tripId: trip)),
          3 => GraceElapsed(trip, gen),
          4 => NativeAnswered(trip, gen, shown: random.nextBool()),
          5 => const FallbackClosed(),
          _ => StateSeen(_ringing(trip, phase: TripPhaseMsg.overshot)),
        };
        final before = s;
        final (next, fx) = reduceRingUi(s, input);
        s = next;
        // A new cycle starts from idle (or from a closed fallback).
        if (before.stage == RingUiStage.idle || input is FallbackClosed) {
          pushes = 0;
        }
        for (final f in fx.whereType<PushFallback>()) {
          expect(before.resumed && s.resumed, isTrue, reason: 'run $run');
          expect(f.tripId, before.ringingTripId, reason: 'run $run');
          pushes++;
          expect(pushes, lessThanOrEqualTo(1), reason: 'run $run');
        }
        if (fx.whereType<AskNative>().isNotEmpty) {
          expect(s.resumed, isTrue, reason: 'run $run');
        }
      }
    }
  });
}
