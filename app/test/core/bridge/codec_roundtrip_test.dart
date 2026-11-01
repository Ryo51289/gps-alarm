// D01 (spec T14): every message, every sealed subclass and every enum value
// survives the generated codec unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';

import 'bridge_samples.dart';

Object? _roundTrip(Object? value) {
  const codec = TripHostApi.pigeonChannelCodec;
  return codec.decodeMessage(codec.encodeMessage(value));
}

void main() {
  group('D01 messages', () {
    for (final nulls in [false, true]) {
      final label = nulls ? 'nullable fields null' : 'all fields set';
      final messages = <Object>[
        sampleAlarm(),
        sampleConfig(nulls: nulls),
        sampleSimulation(),
        sampleState(nulls: nulls),
        sampleActive(nulls: nulls),
        sampleFinished(nulls: nulls),
        samplePermissions(),
        sampleDevice(nulls: nulls),
        ...sampleUpdates(nulls: nulls),
      ];
      for (final m in messages) {
        test('${m.runtimeType} ($label)', () {
          final back = _roundTrip(m);
          expect(back.runtimeType, m.runtimeType);
          expect(back, m);
          expect(back.hashCode, m.hashCode);
        });
      }
    }

    test('sealed subclasses decode as TripUpdateMsg', () {
      final all = sampleUpdates(nulls: false);
      expect(all.map((u) => u.runtimeType).toSet().length, 10);
      for (final u in all) {
        expect(_roundTrip(u), isA<TripUpdateMsg>());
      }
    });

    test('lists of messages (pendingFinishedTrips)', () {
      final list = [
        sampleFinished(),
        sampleFinished(nulls: true, tripId: 't2'),
      ];
      expect(_roundTrip(list), list);
    });
  });

  group('D01 enums', () {
    final enums = <String, List<Enum>>{
      'AlarmModeMsg': AlarmModeMsg.values,
      'VehicleKindMsg': VehicleKindMsg.values,
      'VibrationMsg': VibrationMsg.values,
      'DismissMethodMsg': DismissMethodMsg.values,
      'TripPhaseMsg': TripPhaseMsg.values,
      'GpsStatusMsg': GpsStatusMsg.values,
      'AvailabilityCauseMsg': AvailabilityCauseMsg.values,
      'FallbackStatusMsg': FallbackStatusMsg.values,
      'SamplingTierMsg': SamplingTierMsg.values,
      'AlarmReasonMsg': AlarmReasonMsg.values,
      'GpsLostCauseMsg': GpsLostCauseMsg.values,
      'TripOutcomeMsg': TripOutcomeMsg.values,
      'EndReasonMsg': EndReasonMsg.values,
      'BatteryChoiceMsg': BatteryChoiceMsg.values,
      'LocationAccessMsg': LocationAccessMsg.values,
      'PermissionStateMsg': PermissionStateMsg.values,
      'PermissionKindMsg': PermissionKindMsg.values,
      'SettingsTargetMsg': SettingsTargetMsg.values,
      'PlatformMsg': PlatformMsg.values,
    };
    for (final MapEntry(key: name, value: values) in enums.entries) {
      test(name, () {
        for (final v in values) {
          expect(_roundTrip(v), v);
        }
      });
    }

    // T10 §3.3 mapping, locked here so renames are visible in review.
    test('names match the T10 mapping', () {
      expect(TripPhaseMsg.values.map((e) => e.name), [
        'acquiring',
        'tracking',
        'alarming',
        'snoozed',
        'overshot',
        'ended',
      ]);
      expect(AlarmReasonMsg.values.length, 13);
      expect(FallbackStatusMsg.values.first, FallbackStatusMsg.notSet);
      expect(BatteryChoiceMsg.values.map((e) => e.name), [
        'maxSaving',
        'alarmAt5',
        'alarmEarlier',
      ]);
      expect(LocationAccessMsg.values.map((e) => e.name), [
        'notDetermined',
        'denied',
        'whileInUse',
        'always',
      ]);
    });
  });
}
