// U11: enum <-> wire converters; the wire names are a storage format.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/db/converters.dart';

void _check<T extends Enum>(
  WireEnumConverter<T> converter,
  Map<T, String> expected,
) {
  expect(expected.keys.toSet(), converter.values.toSet(), reason: '$T');
  for (final MapEntry(key: value, value: wire) in expected.entries) {
    expect(converter.toSql(value), wire);
    expect(converter.fromSql(wire), value);
  }
  expect(
    () => converter.fromSql('bogus_wire'),
    throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        isNot(contains('bogus_wire')),
      ),
    ),
  );
}

void main() {
  test('U11 DestinationKind', () {
    const c = DestinationKindConverter();
    _check(c, {for (final v in c.values) v: v.name});
    expect(c.values.map(c.toSql), ['train', 'coach', 'bus', 'address', 'pin']);
  });

  test('U11 DestinationSource', () {
    const c = DestinationSourceConverter();
    expect(c.values.map(c.toSql), [
      'station',
      'places',
      'map_pin',
      'saved_place',
      'recent_trip',
    ]);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });

  test('U11 SavedPlaceSlot', () {
    const c = SavedPlaceSlotConverter();
    expect(c.values.map(c.toSql), ['home', 'hometown', 'work']);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });

  test('U11 AlarmMode', () {
    const c = AlarmModeConverter();
    expect(c.values.map(c.toSql), ['distance', 'time', 'smart']);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });

  test('U11 VehicleKind', () {
    const c = VehicleKindConverter();
    expect(c.values.map(c.toSql), ['train', 'coach', 'bus', 'unknown']);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });

  test('U11 TripOutcome', () {
    const c = TripOutcomeConverter();
    expect(c.values.map(c.toSql), [
      'on_time',
      'snoozed',
      'missed',
      'cancelled',
    ]);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });

  test('U11 EndReason', () {
    const c = EndReasonConverter();
    expect(c.values.map(c.toSql), [
      'dismissed',
      'user_stop',
      'alarm_unanswered',
    ]);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });

  test('U11 AlarmReason', () {
    const c = AlarmReasonConverter();
    expect(c.values.map(c.toSql), [
      'distance',
      'time',
      'smart_time',
      'smart_distance',
      'smart_slow_distance',
      'gps_lost',
      'low_battery',
      'passed_closest',
      'overshoot',
      'snooze_end',
      'timeout',
      'fallback',
      'fallback_missed',
    ]);
    _check(c, {for (final v in c.values) v: c.toSql(v)});
  });
}
