// U20, U21 (result): verdict of the screen 9 background check (T21 §6.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/background_check.dart';

const int _scheduled = 1700000000000;
const int _due = _scheduled + 30000;

BackgroundCheckMsg _check({int? firedAtMs, bool? screenOn}) =>
    BackgroundCheckMsg(
      scheduledAtMs: _scheduled,
      dueAtMs: _due,
      firedAtMs: firedAtMs,
      screenOnAtFire: screenOn,
      exact: true,
    );

void main() {
  test('U20 every case of the table', () {
    expect(evaluateBackgroundCheck(null, _due), isNull);
    expect(
      evaluateBackgroundCheck(_check(), _due - 10000),
      const BackgroundCheckResult(
        BackgroundCheckVerdict.running,
        remaining: Duration(seconds: 10),
      ),
    );
    expect(
      evaluateBackgroundCheck(_check(), _due + 59000),
      const BackgroundCheckResult(
        BackgroundCheckVerdict.running,
        remaining: Duration.zero,
      ),
    );
    expect(
      evaluateBackgroundCheck(_check(), _due + 60000),
      const BackgroundCheckResult(BackgroundCheckVerdict.missed),
    );
    expect(
      evaluateBackgroundCheck(
        _check(firedAtMs: _due + 2000, screenOn: false),
        _due + 3000,
      ),
      const BackgroundCheckResult(BackgroundCheckVerdict.passed),
    );
    expect(
      evaluateBackgroundCheck(
        _check(firedAtMs: _due + 2000, screenOn: true),
        _due + 3000,
      ),
      const BackgroundCheckResult(BackgroundCheckVerdict.passedScreenOn),
    );
    expect(
      evaluateBackgroundCheck(
        _check(firedAtMs: _due + 16000, screenOn: false),
        _due + 20000,
      ),
      const BackgroundCheckResult(
        BackgroundCheckVerdict.late,
        lateBy: Duration(seconds: 16),
      ),
    );
    // Fired early (clock change): still passed.
    expect(
      evaluateBackgroundCheck(
        _check(firedAtMs: _due - 5000, screenOn: false),
        _due,
      ),
      const BackgroundCheckResult(BackgroundCheckVerdict.passed),
    );
    // Scheduled 11 minutes ago: ignored.
    expect(
      evaluateBackgroundCheck(
        _check(firedAtMs: _due + 1000, screenOn: false),
        _scheduled + const Duration(minutes: 11).inMilliseconds,
      ),
      isNull,
    );
  });

  test('U20 borders: 15 s late still passes, screen unknown passes', () {
    expect(
      evaluateBackgroundCheck(
        _check(firedAtMs: _due + 15000),
        _due + 20000,
      )?.verdict,
      BackgroundCheckVerdict.passed,
    );
    expect(
      evaluateBackgroundCheck(
        _check(),
        _scheduled + const Duration(minutes: 10).inMilliseconds,
      )?.verdict,
      BackgroundCheckVerdict.missed,
    );
  });

  test('U21 telemetry result', () {
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
}
