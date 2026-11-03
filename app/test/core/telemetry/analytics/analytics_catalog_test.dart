// T29 TC01–TC04: catalog limits, every sample event passes the guard,
// malformed payloads are refused, coordinate detection.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/analytics/analytics_catalog.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';

import '../telemetry_fakes.dart';

final RegExp _eventName = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
final RegExp _enumValue = RegExp(r'^[a-z0-9_]{1,40}$');

void main() {
  group('TC01 catalog', () {
    test('names, prefixes, sizes, value sets', () {
      expect(kAnalyticsCatalog, hasLength(8));
      for (final MapEntry(key: event, value: params)
          in kAnalyticsCatalog.entries) {
        expect(_eventName.hasMatch(event), isTrue, reason: event);
        expect(
          event,
          isNot(matches(RegExp('^(firebase_|google_|ga_)'))),
          reason: event,
        );
        expect(params.length, lessThanOrEqualTo(kMaxEventParams));
        for (final MapEntry(key: name, value: spec) in params.entries) {
          expect(_eventName.hasMatch(name), isTrue, reason: '$event.$name');
          switch (spec) {
            case EnumParam(:final values):
              expect(values, isNotEmpty);
              for (final v in values) {
                expect(_enumValue.hasMatch(v), isTrue, reason: '$name=$v');
              }
            case IntParam(:final min, :final max):
              expect(min, greaterThanOrEqualTo(0), reason: name);
              expect(max, lessThanOrEqualTo(3), reason: name);
            case PatternParam():
              expect(name, 'params_id', reason: 'pattern only for params_id');
            case BoolParam():
              fail('Analytics takes no bool ($event.$name)');
          }
        }
      }
    });
  });

  group('TC02 every sample event passes', () {
    final samples = sampleEvents();

    test('guard accepts all samples', () {
      for (final e in samples) {
        expect(
          checkAnalyticsEvent(e.name, e.toParameters()),
          isNull,
          reason: e.toParameters().toString(),
        );
        expect(eventKind(e), e.name);
      }
    });

    test('the samples cover the catalog and every enum value', () {
      expect(
        samples.map((e) => e.name).toSet(),
        kAnalyticsCatalog.keys.toSet(),
      );
      final seen = <String>{
        for (final e in samples)
          for (final v in e.toParameters().values)
            if (v is String) v,
      };
      for (final tags in kAllTagEnums) {
        for (final t in tags) {
          expect(seen, contains(t.wire), reason: '$t');
        }
      }
      // Every parameter of the catalog appears in some sample.
      for (final MapEntry(key: event, value: params)
          in kAnalyticsCatalog.entries) {
        final used = {
          for (final e in samples.where((e) => e.name == event))
            ...e.toParameters().keys,
        };
        expect(used, params.keys.toSet(), reason: event);
      }
    });

    test('values are only String and int; snooze_count clamped', () {
      for (final e in samples) {
        for (final v in e.toParameters().values) {
          expect(v is String || v is int, isTrue, reason: '$v');
          expect(v, isNot(isA<double>()));
        }
      }
      final ends = samples.whereType<TripEndEvent>();
      expect(ends.map((e) => e.snoozeCount).toSet(), {0, 1, 2, 3});
    });

    test('no toString carries a value', () {
      for (final e in samples) {
        expect(e.toString(), 'AnalyticsEvent(${e.name})');
      }
    });
  });

  group('TC03 malformed payloads', () {
    final cases = <(String, String, Map<String, Object>, ViolationKind)>[
      ('unknown event', 'trip_teleport', {}, ViolationKind.unknownEvent),
      (
        'unknown param',
        'trip_start_blocked',
        {'reason': 'start_failed', 'dest_name': 'x'},
        ViolationKind.unknownParam,
      ),
      (
        'double',
        'trip_end',
        {'snooze_count': 1.0},
        ViolationKind.coordinateLike,
      ),
      (
        'value outside the enum',
        'trip_end',
        {'mode': 'walk'},
        ViolationKind.rejectedValue,
      ),
      (
        'int out of range',
        'trip_end',
        {'snooze_count': 4},
        ViolationKind.rejectedValue,
      ),
      (
        'coordinate in params_id',
        'trip_start',
        {'params_id': '21.0285'},
        ViolationKind.coordinateLike,
      ),
      (
        '101 characters',
        'trip_end',
        {'mode': 'a' * 101},
        ViolationKind.rejectedValue,
      ),
      (
        '26 parameters',
        'trip_end',
        {for (var i = 0; i < 26; i++) 'p$i': 0},
        ViolationKind.tooManyParams,
      ),
      (
        'invalid event name',
        'firebase_trip',
        {},
        ViolationKind.invalidEventName,
      ),
      (
        'invalid param name',
        'trip_end',
        {'1mode': 'time'},
        ViolationKind.invalidParamName,
      ),
      (
        'bool value',
        'trip_end',
        {'simulated': true},
        ViolationKind.rejectedValue,
      ),
      (
        'coordinate key in a string',
        'trip_end',
        {'mode': 'lat=21'},
        ViolationKind.coordinateLike,
      ),
    ];
    for (final (label, name, params, kind) in cases) {
      test(label, () {
        final v = checkAnalyticsEvent(name, params);
        expect(v?.kind, kind);
        // Names only, never a value.
        final text = v.toString();
        for (final value in params.values) {
          if (value is String && value.length > 1) {
            expect(text, isNot(contains(value)));
          }
        }
        expect(text, isNot(contains('21.0285')));
      });
    }

    test('a custom catalog cannot whitelist a reserved name', () {
      final v = checkAnalyticsEvent(
        'ga_x',
        const {},
        catalog: {'ga_x': const {}},
      );
      expect(v?.kind, ViolationKind.invalidEventName);
    });
  });

  group('TC04 looksLikeCoordinate', () {
    test('coordinates and doubles', () {
      for (final v in <Object>[
        21.0285123,
        '16.4637',
        '105,8542',
        'lat=21',
        -6.2,
      ]) {
        expect(looksLikeCoordinate(v), isTrue, reason: '$v');
      }
      for (final v in <Object>[
        'Lng: 105',
        'latitude -6',
        'geo 16.46370',
        'x 1.000',
      ]) {
        expect(looksLikeCoordinate(v), isTrue, reason: '$v');
      }
    });

    test('bucket names and small ints are not', () {
      for (final v in <Object>['d1000', 'lt2h', 'ge500km', 0, 3]) {
        expect(looksLikeCoordinate(v), isFalse, reason: '$v');
      }
    });

    test('no allowed catalog value looks like a coordinate', () {
      for (final params in kAnalyticsCatalog.values) {
        for (final spec in params.values) {
          if (spec is EnumParam) {
            for (final v in spec.values) {
              expect(looksLikeCoordinate(v), isFalse, reason: v);
            }
          }
        }
      }
      for (final v in ['default', 'invalid', '811c9dc5', '12345678']) {
        expect(looksLikeCoordinate(v), isFalse, reason: v);
      }
    });
  });
}
