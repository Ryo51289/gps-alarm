// Tester T21 (§6.4, D15): grading of the 30 s check at the exact thresholds
// (late = due + 15 s, missed = due + 60 s, stale = 10 min) and over time.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/background_check.dart';

const int _s = 1700000000000;
const int _due = _s + 30000;

BackgroundCheckMsg _m({int? fired, bool? screenOn, bool exact = true}) =>
    BackgroundCheckMsg(
      scheduledAtMs: _s,
      dueAtMs: _due,
      firedAtMs: fired,
      screenOnAtFire: screenOn,
      exact: exact,
    );

BackgroundCheckVerdict? _v(BackgroundCheckMsg m, int now) =>
    evaluateBackgroundCheck(m, now)?.verdict;

void main() {
  test('the four outcomes a user can get', () {
    const now = _due + 61000;
    // On time, screen locked.
    expect(
      _v(_m(fired: _due + 30, screenOn: false), now),
      BackgroundCheckVerdict.passed,
    );
    // Late (OEM delays the alarm).
    expect(
      _v(_m(fired: _due + 20000, screenOn: false), now),
      BackgroundCheckVerdict.late,
    );
    // No vibration at all (app killed / force-stopped).
    expect(_v(_m(), now), BackgroundCheckVerdict.missed);
    // Vibrated, but the screen was not locked: not a valid pass.
    expect(
      _v(_m(fired: _due + 30, screenOn: true), now),
      BackgroundCheckVerdict.passedScreenOn,
    );
    expect(
      backgroundCheckTelemetryResult(BackgroundCheckVerdict.passed),
      'pass',
    );
    expect(backgroundCheckTelemetryResult(BackgroundCheckVerdict.late), 'fail');
    expect(
      backgroundCheckTelemetryResult(BackgroundCheckVerdict.missed),
      'fail',
    );
    expect(
      backgroundCheckTelemetryResult(BackgroundCheckVerdict.passedScreenOn),
      isNull,
    );
    expect(
      backgroundCheckTelemetryResult(BackgroundCheckVerdict.running),
      isNull,
    );
  });

  test('late threshold: 15 000 ms is on time, 15 001 ms is late', () {
    const now = _due + 61000;
    expect(
      _v(_m(fired: _due + 15000, screenOn: false), now),
      BackgroundCheckVerdict.passed,
    );
    final late = evaluateBackgroundCheck(
      _m(fired: _due + 15001, screenOn: false),
      now,
    )!;
    expect(late.verdict, BackgroundCheckVerdict.late);
    expect(late.lateBy, const Duration(milliseconds: 15001));
    // Late wins over "screen on".
    expect(
      _v(_m(fired: _due + 15001, screenOn: true), now),
      BackgroundCheckVerdict.late,
    );
    // Screen state unknown (null) on time: passed.
    expect(_v(_m(fired: _due + 1), now), BackgroundCheckVerdict.passed);
    // Inexact alarm on time still passes (exact only affects scheduling).
    expect(
      _v(_m(fired: _due + 1, screenOn: false, exact: false), now),
      BackgroundCheckVerdict.passed,
    );
  });

  test(
    'give-up threshold: due + 59 999 ms running, due + 60 000 ms missed',
    () {
      final running = evaluateBackgroundCheck(_m(), _due + 59999)!;
      expect(running.verdict, BackgroundCheckVerdict.running);
      expect(running.remaining, Duration.zero);
      expect(_v(_m(), _due + 60000), BackgroundCheckVerdict.missed);
      // A fire after the give-up time is still a result (late), not missed.
      expect(
        _v(_m(fired: _due + 61000, screenOn: false), _due + 62000),
        BackgroundCheckVerdict.late,
      );
    },
  );

  test(
    'stale threshold: exactly 10 min still graded, 10 min + 1 ms ignored',
    () {
      const tenMin = 600000;
      expect(_v(_m(), _s + tenMin), BackgroundCheckVerdict.missed);
      expect(evaluateBackgroundCheck(_m(), _s + tenMin + 1), isNull);
      expect(
        evaluateBackgroundCheck(
          _m(fired: _due, screenOn: false),
          _s + tenMin + 1,
        ),
        isNull,
      );
      expect(evaluateBackgroundCheck(null, _s), isNull);
    },
  );

  test('over time without a fire: running, then missed, then forgotten', () {
    var phase = 0; // 0 running, 1 missed, 2 null
    Duration? lastRemaining;
    for (var now = _s - 5000; now <= _s + 700000; now += 250) {
      final r = evaluateBackgroundCheck(_m(), now);
      final p = switch (r?.verdict) {
        BackgroundCheckVerdict.running => 0,
        BackgroundCheckVerdict.missed => 1,
        null => 2,
        _ => fail('unexpected ${r!.verdict} at $now'),
      };
      expect(p, greaterThanOrEqualTo(phase), reason: 'went back at $now');
      phase = p;
      if (r?.verdict == BackgroundCheckVerdict.running) {
        final rem = r!.remaining!;
        expect(rem.isNegative, isFalse);
        if (lastRemaining != null) {
          expect(
            rem <= lastRemaining,
            isTrue,
            reason: 'countdown rose at $now',
          );
        }
        lastRemaining = rem;
        expect(r.lateBy, isNull);
      }
    }
    expect(phase, 2);
  });

  test(
    'clock moved backwards after scheduling: still running, never negative',
    () {
      final r = evaluateBackgroundCheck(_m(), _s - 3600000)!;
      expect(r.verdict, BackgroundCheckVerdict.running);
      expect(r.remaining!.isNegative, isFalse);
      // Fired "before" due because the clock changed: passed (spec §6.4).
      expect(
        _v(_m(fired: _s + 1, screenOn: false), _due + 61000),
        BackgroundCheckVerdict.passed,
      );
    },
  );

  test('the default delay is the 30 s of the copy', () {
    expect(kBackgroundCheckDelay, const Duration(seconds: 30));
    expect(kBackgroundCheckLate, const Duration(seconds: 15));
    expect(kBackgroundCheckGiveUp, const Duration(seconds: 60));
    expect(kBackgroundCheckStale, const Duration(minutes: 10));
  });
}
