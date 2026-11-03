// T29 tester: adversarial Analytics payloads. Whatever a future caller puts
// in a parameter (a double, a coordinate in any notation, a plus code, an
// OSM/Places id, a Vietnamese place name), the guard rejects it and
// AppAnalytics never forwards it; the violation report carries names only.
// Deterministic: fixed seeds, no clock, no network.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/analytics/analytics_catalog.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/telemetry/analytics/app_analytics.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';

import '../telemetry_fakes.dart';

/// Location-bearing values in the notations a bug could produce.
const List<Object> _locationValues = [
  // Doubles (any double, even "harmless" ones).
  21.0285, 105.8542, -6.2, 0.0, -0.0, 1.0, 3.0, double.nan,
  double.infinity, 21.028511, 1e-7,
  // Decimal degrees as text.
  '21.0285,105.8542', '21.0285, 105.8542', '21.0285;105.8542',
  '21,0285', '105,8542123', '-6.2088', '16.4637', '(21.0285 105.8542)',
  'POINT(105.8542 21.0285)', '21.0285N 105.8542E', 'geo:21.0285,105.8542',
  'https://maps.google.com/?q=21.0285,105.8542',
  '[21.0285,105.8542]', '{"lat":21.0285,"lng":105.8542}',
  // Degrees-minutes-seconds and degrees-decimal-minutes.
  "21°01'N", "21°01'43\"N 105°51'15\"E", '21°01′42″N 105°51′15″E',
  'N21 01.711 E105 51.252', '21 1 42 N', '21d01m43s',
  // Coordinate keys.
  'lat=21', 'lng:105', 'latitude -6', 'lon 105', 'destLat=21',
  // Integers as text, micro-degrees, E7.
  '210285', '1058542', '210285000', '21', '105',
  // Plus codes / geohashes.
  '7PH7+3R', '7PH73RV2+XX', '7PH7+3R Hà Nội', 'w7er8u0', 'w7er8u0nfx',
  // Station / place identifiers.
  'osm:n7153190734', 'osm:w123456', 'osm:r1', 'station-osm:n7153190734',
  'ChIJ0T2NLikpdTERKxE8d61aX_E', 'place-ChIJ0T2NLikpdTERKxE8d61aX_E',
  'places/ChIJ0T2NLikpdTERKxE8d61aX_E',
  // Vietnamese names, addresses, search text.
  'Ga Đồng Hới', 'Bến xe Mỹ Đình', 'Hà Nội', 'Ga Huế', 'Đà Nẵng',
  'Sài Gòn', '1 Tràng Tiền, Hoàn Kiếm', 'nhà bà ngoại', 'ga dong hoi',
  'Dong Hoi', 'đồng hới', 'Ga', 'ga_hue', 'dong_hoi',
  // Look-alikes of allowed values with data glued on.
  'station:osm:n1', 'train Ga Huế', 'd1000 21.0285', 'lt2h 16.4637',
  'smart ', ' smart', 'SMART', 'Smart', 'default\n', 'DEFAULT',
  '811c9dc5 ', '811C9DC5', '811c9dc', '811c9dc5a', '-811c9dc',
  // Out-of-range integers and other types.
  -1, 4, 21, 105, 210285, 1 << 40, -(1 << 40), true, false,
  <Object>[21.0285], <String, Object>{'lat': 21},
];

/// Whether the catalog allows [v] for [spec].
bool _allowed(ParamSpec spec, Object v) => spec.accepts(v);

void main() {
  group('fuzz: every catalog parameter × location-bearing values', () {
    for (final MapEntry(key: event, value: specs)
        in kAnalyticsCatalog.entries) {
      test(event, () {
        for (final MapEntry(key: param, value: spec) in specs.entries) {
          for (final v in _locationValues) {
            final violation = checkAnalyticsEvent(event, {param: v});
            expect(violation, isNotNull, reason: '$event.$param accepted <$v>');
            // Names only, never the value.
            final text = violation.toString();
            if (v is String && v.trim().length >= 3) {
              expect(text, isNot(contains(v.trim())), reason: v);
            }
            expect(text, isNot(contains('21.0285')));
            expect(text, isNot(contains('osm:')));
            expect(text, isNot(contains('ChIJ')));
            expect(text, isNot(contains('Đồng Hới')));
            expect(_allowed(spec, v), isFalse);
          }
        }
      });
    }
  });

  test('every double is coordinateLike, whatever its value', () {
    final rnd = Random(29);
    for (var i = 0; i < 5000; i++) {
      final d = (rnd.nextDouble() - 0.5) * 400;
      expect(looksLikeCoordinate(d), isTrue);
      final v = checkAnalyticsEvent('trip_end', {'snooze_count': d});
      expect(v?.kind, ViolationKind.coordinateLike);
    }
    // Whole-number doubles too: 1.0 must not slip into an IntParam.
    for (final d in [0.0, 1.0, 2.0, 3.0]) {
      expect(
        checkAnalyticsEvent('trip_end', {'snooze_count': d})?.kind,
        ViolationKind.coordinateLike,
      );
    }
  });

  test(
    'decimal coordinate text with ≥ 3 fractional digits is coordinateLike',
    () {
      final rnd = Random(2029);
      for (var i = 0; i < 5000; i++) {
        final lat = (rnd.nextDouble() * 180 - 90).toStringAsFixed(
          3 + rnd.nextInt(5),
        );
        final lng = (rnd.nextDouble() * 360 - 180).toStringAsFixed(
          3 + rnd.nextInt(5),
        );
        for (final s in [
          '$lat,$lng',
          '$lat, $lng',
          lat,
          lng.replaceAll('.', ','),
          'geo:$lat,$lng',
          'fix $lat $lng',
        ]) {
          expect(looksLikeCoordinate(s), isTrue, reason: s);
        }
      }
    },
  );

  test('random strings: accepted only when exactly an allowed value', () {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyz_0123456789.,:;+-°\'" '
        'ĐđồớệưảạếHNGBXMĐình';
    final rnd = Random(7);
    final params = [
      for (final MapEntry(key: e, value: specs) in kAnalyticsCatalog.entries)
        for (final MapEntry(key: p, value: s) in specs.entries) (e, p, s),
    ];
    var accepted = 0;
    for (var i = 0; i < 30000; i++) {
      final (event, param, spec) = params[rnd.nextInt(params.length)];
      final len = rnd.nextInt(24);
      final s = String.fromCharCodes([
        for (var j = 0; j < len; j++)
          alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
      ]);
      final ok = checkAnalyticsEvent(event, {param: s}) == null;
      final expected = switch (spec) {
        EnumParam(:final values) => values.contains(s),
        PatternParam(:final pattern) => pattern.hasMatch(s),
        _ => false,
      };
      expect(ok, expected && !looksLikeCoordinate(s), reason: '$param <$s>');
      if (ok) {
        accepted++;
      }
    }
    // Random text practically never equals an enum wire name.
    expect(accepted, lessThan(10));
  });

  test('coordinate/location parameter NAMES are unknown everywhere', () {
    const names = [
      'lat',
      'lng',
      'lon',
      'latitude',
      'longitude',
      'dest_lat',
      'dest_lng',
      'location_lat',
      'station_id',
      'station',
      'station_name',
      'place_id',
      'place',
      'query',
      'search',
      'destination',
      'destination_name',
      'saved_place',
      'trip_id',
      'distance_m',
      'eta_s',
      'accuracy',
      'speed',
      'bearing',
      'address',
      'city',
      'province',
    ];
    for (final event in kAnalyticsCatalog.keys) {
      for (final n in names) {
        final v = checkAnalyticsEvent(event, {n: 'x'});
        expect(v?.kind, ViolationKind.unknownParam, reason: '$event.$n');
      }
    }
  });

  test('a valid event plus one smuggled extra parameter is rejected', () {
    for (final e in sampleEvents()) {
      for (final extra in <String, Object>{
        'lat': 21.0285,
        'station_id': 'osm:n7153190734',
        'place_id': 'ChIJ0T2NLikpdTERKxE8d61aX_E',
        'destination': 'Ga Đồng Hới',
      }.entries) {
        final params = {...e.toParameters(), extra.key: extra.value};
        expect(
          checkAnalyticsEvent(e.name, params),
          isNotNull,
          reason: '${e.name} + ${extra.key}',
        );
      }
    }
  });

  test('event names: look-alikes and reserved prefixes are rejected', () {
    const names = [
      'trip_start ',
      ' trip_start',
      'Trip_Start',
      'TRIP_START',
      'trip-start',
      'trip_start\n',
      'trip_start_ga_hue',
      'firebase_trip',
      'google_trip',
      'ga_trip',
      'screen_view',
      'first_open',
      'trip_start_21_0285',
      '',
      '1trip',
      'tripstart',
    ];
    for (final n in names) {
      expect(checkAnalyticsEvent(n, const {}), isNotNull, reason: '<$n>');
    }
  });

  group('AppAnalytics never forwards the only free-text field (params_id)', () {
    TripStartEvent start(String paramsId) => TripStartEvent(
      mode: AlarmModeTag.smart,
      threshold: ThresholdTag.smart,
      vehicleHint: VehicleTag.coach,
      destSource: DestSourceTag.places,
      preAlert: false,
      shortDistanceWarning: false,
      battery: BatteryBucket.gt50,
      charging: true,
      simulated: false,
      paramsId: paramsId,
    );

    test(
      'release mode: dropped + one names-only non-fatal per event',
      () async {
        final sink = RecordingAnalyticsSink();
        final (crash, crashSink) = recordingCrash();
        final analytics = AppAnalytics(
          sink: sink,
          crash: crash,
          isEnabled: () => true,
          strict: false,
        );
        final bad = _locationValues.whereType<String>().toList();
        for (final v in bad) {
          analytics.log(start(v));
        }
        await pumpEventQueue();
        expect(sink.events, isEmpty);
        expect(crashSink.errors, hasLength(bad.length));
        for (final e in crashSink.errors) {
          expect(e.fatal, isFalse);
          expect(e.reason, NonFatalReason.analyticsGuardViolation.name);
          expect(
            e.error.toString(),
            anyOf(
              'GuardViolation: GuardViolation(trip_start, params_id, '
                  'rejectedValue)',
              'GuardViolation: GuardViolation(trip_start, params_id, '
                  'coordinateLike)',
            ),
          );
        }
        for (final text in crashSink.allText) {
          for (final v in bad) {
            if (v.trim().length >= 3) {
              expect(text, isNot(contains(v.trim())));
            }
          }
        }
      },
    );

    test('debug/strict: throws, message without the value', () {
      final (crash, _) = recordingCrash();
      final analytics = AppAnalytics(
        sink: RecordingAnalyticsSink(),
        crash: crash,
        isEnabled: () => true,
      );
      expect(
        () => analytics.log(start('Ga Đồng Hới 17.4783')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(isNot(contains('Đồng Hới')), isNot(contains('17.478'))),
          ),
        ),
      );
    });

    test('collection off: still never forwarded, still reported', () async {
      final sink = RecordingAnalyticsSink();
      final (crash, crashSink) = recordingCrash();
      AppAnalytics(
        sink: sink,
        crash: crash,
        isEnabled: () => false,
        strict: false,
      ).log(start('osm:n7153190734'));
      await pumpEventQueue();
      expect(sink.calls, isEmpty);
      expect(crashSink.errors, hasLength(1));
    });

    test('isEnabled throwing → nothing sent, no exception', () async {
      final sink = RecordingAnalyticsSink();
      final (crash, _) = recordingCrash();
      AppAnalytics(
        sink: sink,
        crash: crash,
        isEnabled: () => throw StateError('x'),
        strict: false,
      ).log(start('default'));
      await pumpEventQueue();
      expect(sink.calls, isEmpty);
    });
  });

  test('TripEndEvent clamps any int: never a raw count', () {
    for (final n in [-1 << 40, -5, -1, 0, 1, 2, 3, 4, 99, 1 << 40]) {
      final e = TripEndEvent(
        outcome: TripOutcomeTag.onTime,
        endReason: EndReasonTag.dismissed,
        alarmReason: AlarmReasonTag.distance,
        snoozeCount: n,
        mode: AlarmModeTag.distance,
        vehicleGuess: VehicleTag.train,
        duration: DurationBucket.lt2h,
        distance: DistanceBucket.lt200km,
        simulated: false,
      );
      expect(checkAnalyticsEvent(e.name, e.toParameters()), isNull);
      expect(e.toParameters()['snooze_count'], inInclusiveRange(0, 3));
    }
  });

  test('every value any sample event sends is a wire name or 0..3', () {
    final wires = {
      for (final values in kAllTagEnums)
        for (final t in values) t.wire,
    };
    for (final e in sampleEvents()) {
      for (final MapEntry(key: k, value: v) in e.toParameters().entries) {
        if (k == 'params_id') {
          expect(kParamsIdPattern.hasMatch(v as String), isTrue);
          continue;
        }
        expect(
          (v is String && wires.contains(v)) || (v is int && v >= 0 && v <= 3),
          isTrue,
          reason: '${e.name}.$k = $v',
        );
      }
    }
  });
}
