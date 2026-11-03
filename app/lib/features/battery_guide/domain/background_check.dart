/// Verdict of the screen 9 background check (T21 §6.4, D15). Pure Dart.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';

/// How long the check waits before the alarm.
const Duration kBackgroundCheckDelay = Duration(seconds: 30);

/// Fired later than due + this: late.
const Duration kBackgroundCheckLate = Duration(seconds: 15);

/// Not fired by due + this: missed.
const Duration kBackgroundCheckGiveUp = Duration(seconds: 60);

/// Older records are ignored when screen 9 opens.
const Duration kBackgroundCheckStale = Duration(minutes: 10);

enum BackgroundCheckVerdict { running, passed, passedScreenOn, late, missed }

@immutable
final class BackgroundCheckResult {
  const new(this.verdict, {this.remaining, this.lateBy});

  final BackgroundCheckVerdict verdict;

  /// [BackgroundCheckVerdict.running] only, never negative.
  final Duration? remaining;

  /// [BackgroundCheckVerdict.late] only.
  final Duration? lateBy;

  @override
  bool operator ==(Object other) =>
      other is BackgroundCheckResult &&
      other.verdict == verdict &&
      other.remaining == remaining &&
      other.lateBy == lateBy;

  @override
  int get hashCode => Object.hash(verdict, remaining, lateBy);

  @override
  String toString() =>
      'BackgroundCheckResult(${verdict.name}, remaining: $remaining, '
      'lateBy: $lateBy)';
}

/// Null: no check, or one scheduled more than [kBackgroundCheckStale] before
/// [nowMs]. A check that fired before its due time (clock change) passes.
BackgroundCheckResult? evaluateBackgroundCheck(
  BackgroundCheckMsg? m,
  int nowMs,
) {
  if (m == null ||
      nowMs - m.scheduledAtMs > kBackgroundCheckStale.inMilliseconds) {
    return null;
  }
  final fired = m.firedAtMs;
  if (fired != null) {
    final lateBy = fired - m.dueAtMs;
    if (lateBy > kBackgroundCheckLate.inMilliseconds) {
      return BackgroundCheckResult(
        BackgroundCheckVerdict.late,
        lateBy: Duration(milliseconds: lateBy),
      );
    }
    return BackgroundCheckResult(
      m.screenOnAtFire == true
          ? BackgroundCheckVerdict.passedScreenOn
          : BackgroundCheckVerdict.passed,
    );
  }
  if (nowMs < m.dueAtMs + kBackgroundCheckGiveUp.inMilliseconds) {
    return BackgroundCheckResult(
      BackgroundCheckVerdict.running,
      remaining: Duration(milliseconds: math.max(0, m.dueAtMs - nowMs)),
    );
  }
  return const BackgroundCheckResult(BackgroundCheckVerdict.missed);
}

/// T29 `battery_guide_test.result`: passed → pass; late, missed → fail;
/// passedScreenOn and running → null (not logged).
String? backgroundCheckTelemetryResult(BackgroundCheckVerdict v) => switch (v) {
  BackgroundCheckVerdict.passed => 'pass',
  BackgroundCheckVerdict.late || BackgroundCheckVerdict.missed => 'fail',
  BackgroundCheckVerdict.passedScreenOn ||
  BackgroundCheckVerdict.running => null,
};
