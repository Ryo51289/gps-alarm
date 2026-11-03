/// Grouping functions of T29 §2: exact values never leave the device, only
/// their bucket. Pure Dart.
library;

import 'package:napstop/core/telemetry/analytics/analytics_event.dart';

BatteryBucket batteryBucket(int pct) {
  if (pct <= 5) {
    return BatteryBucket.le5;
  }
  if (pct <= 15) {
    return BatteryBucket.le15;
  }
  if (pct <= 50) {
    return BatteryBucket.le50;
  }
  return BatteryBucket.gt50;
}

const int _minuteMs = 60 * 1000;
const int _hourMs = 60 * _minuteMs;

/// Negative durations (clock moved back) count as [DurationBucket.lt30m].
DurationBucket durationBucket(int ms) {
  if (ms < 30 * _minuteMs) {
    return DurationBucket.lt30m;
  }
  if (ms < 2 * _hourMs) {
    return DurationBucket.lt2h;
  }
  if (ms < 6 * _hourMs) {
    return DurationBucket.lt6h;
  }
  if (ms < 12 * _hourMs) {
    return DurationBucket.lt12h;
  }
  return DurationBucket.ge12h;
}

DistanceBucket distanceBucket(num meters) {
  if (meters < 10000) {
    return DistanceBucket.lt10km;
  }
  if (meters < 50000) {
    return DistanceBucket.lt50km;
  }
  if (meters < 200000) {
    return DistanceBucket.lt200km;
  }
  if (meters < 500000) {
    return DistanceBucket.lt500km;
  }
  return DistanceBucket.ge500km;
}

/// The preset of [mode] (`d1000`, `t15`, `smart`), or `d_other`/`t_other`
/// for a custom or missing threshold.
ThresholdTag thresholdKey(AlarmModeTag mode, {int? distanceM, int? timeMin}) =>
    switch (mode) {
      AlarmModeTag.smart => ThresholdTag.smart,
      AlarmModeTag.distance => switch (distanceM) {
        500 => ThresholdTag.d500,
        1000 => ThresholdTag.d1000,
        2000 => ThresholdTag.d2000,
        5000 => ThresholdTag.d5000,
        _ => ThresholdTag.dOther,
      },
      AlarmModeTag.time => switch (timeMin) {
        5 => ThresholdTag.t5,
        10 => ThresholdTag.t10,
        15 => ThresholdTag.t15,
        20 => ThresholdTag.t20,
        30 => ThresholdTag.t30,
        _ => ThresholdTag.tOther,
      },
    };

const int kDailyMs = 24 * _hourMs;

/// Whether a once-a-day event is due: never logged, at least 24 h since
/// [lastMs], or the clock moved back.
bool shouldLogDaily(int? lastMs, int nowMs) =>
    lastMs == null || nowMs - lastMs >= kDailyMs || nowMs < lastMs;
