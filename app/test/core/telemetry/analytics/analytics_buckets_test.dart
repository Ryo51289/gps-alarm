// T29 TC07: bucket boundaries.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/analytics/analytics_buckets.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';

void main() {
  test('batteryBucket', () {
    const expected = {
      0: BatteryBucket.le5,
      5: BatteryBucket.le5,
      6: BatteryBucket.le15,
      15: BatteryBucket.le15,
      16: BatteryBucket.le50,
      50: BatteryBucket.le50,
      51: BatteryBucket.gt50,
      100: BatteryBucket.gt50,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(batteryBucket(key), value, reason: '$key');
    }
  });

  test('durationBucket', () {
    const expected = {
      -1: DurationBucket.lt30m,
      0: DurationBucket.lt30m,
      1799999: DurationBucket.lt30m,
      1800000: DurationBucket.lt2h,
      7199999: DurationBucket.lt2h,
      7200000: DurationBucket.lt6h,
      21600000: DurationBucket.lt12h,
      43199999: DurationBucket.lt12h,
      43200000: DurationBucket.ge12h,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(durationBucket(key), value, reason: '$key');
    }
  });

  test('distanceBucket', () {
    final expected = <num, DistanceBucket>{
      0: DistanceBucket.lt10km,
      9999: DistanceBucket.lt10km,
      9999.9: DistanceBucket.lt10km,
      10000: DistanceBucket.lt50km,
      50000: DistanceBucket.lt200km,
      199999: DistanceBucket.lt200km,
      200000: DistanceBucket.lt500km,
      499999: DistanceBucket.lt500km,
      500000: DistanceBucket.ge500km,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(distanceBucket(key), value, reason: '$key');
    }
  });

  test('thresholdKey', () {
    expect(
      thresholdKey(AlarmModeTag.distance, distanceM: 1000),
      ThresholdTag.d1000,
    );
    expect(
      thresholdKey(AlarmModeTag.distance, distanceM: 500),
      ThresholdTag.d500,
    );
    expect(
      thresholdKey(AlarmModeTag.distance, distanceM: 2000),
      ThresholdTag.d2000,
    );
    expect(
      thresholdKey(AlarmModeTag.distance, distanceM: 5000),
      ThresholdTag.d5000,
    );
    expect(
      thresholdKey(AlarmModeTag.distance, distanceM: 1500),
      ThresholdTag.dOther,
    );
    expect(thresholdKey(AlarmModeTag.distance), ThresholdTag.dOther);
    expect(thresholdKey(AlarmModeTag.time, timeMin: 15), ThresholdTag.t15);
    for (final m in [5, 10, 20, 30]) {
      expect(thresholdKey(AlarmModeTag.time, timeMin: m).wire, 't$m');
    }
    expect(thresholdKey(AlarmModeTag.time, timeMin: 45), ThresholdTag.tOther);
    // The other mode's threshold is ignored.
    expect(
      thresholdKey(AlarmModeTag.time, distanceM: 1000),
      ThresholdTag.tOther,
    );
    expect(
      thresholdKey(AlarmModeTag.smart, distanceM: 1000, timeMin: 15),
      ThresholdTag.smart,
    );
  });

  test('shouldLogDaily', () {
    const last = 1700000000000;
    expect(shouldLogDaily(null, last), isTrue);
    expect(shouldLogDaily(last, last), isFalse);
    expect(shouldLogDaily(last, last + 86399999), isFalse);
    expect(shouldLogDaily(last, last + 86400000), isTrue);
    expect(shouldLogDaily(last, last - 1), isTrue, reason: 'clock moved back');
  });
}
