// T27 U01 (Maps URL), U02 (/overshoot query), U10 (auto-open window).
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';

import '../../../helpers/trip_fixtures.dart';

void main() {
  group('U01 routeBackUri', () {
    test('Maps URLs directions, 6 decimals, encoded comma', () {
      expect(
        routeBackUri(17.4688, 106.6223).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=17.468800%2C106.622300',
      );
      expect(
        routeBackUri(-0.5, -179.9999999).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=-0.500000%2C-180.000000',
      );
      expect(
        routeBackUri(90, 180).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=90.000000%2C180.000000',
      );
      expect(
        routeBackUri(-90, -180).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=-90.000000%2C-180.000000',
      );
    });

    test('null when not finite or out of range', () {
      expect(routeBackUri(double.nan, 1), isNull);
      expect(routeBackUri(1, double.infinity), isNull);
      expect(routeBackUri(91, 0), isNull);
      expect(routeBackUri(0, 181), isNull);
      expect(routeBackUri(-90.0001, 0), isNull);
    });

    test("decimal separator is always '.' (Vietnamese locale)", () {
      final saved = Intl.defaultLocale;
      Intl.defaultLocale = 'vi';
      addTearDown(() => Intl.defaultLocale = saved);
      final uri = routeBackUri(16.4567, 107.5781)!;
      expect(uri.queryParameters['destination'], '16.456700,107.578100');
      expect(uri.toString(), isNot(contains('16,4')));
      expect(uri.queryParameters.keys, ['api', 'destination']);
    });
  });

  group('U02 OvershootArgs', () {
    OvershootArgs? parse(String s) => OvershootArgs.fromUri(Uri.parse(s));

    test('fromUri', () {
      expect(
        parse('/overshoot?trip=t-1&past=1234&open=1'),
        const OvershootArgs(tripId: 't-1', pastM: 1234, autoOpen: true),
      );
      expect(parse('/overshoot?trip=t-1&past=-1')!.pastM, isNull);
      expect(parse('/overshoot?trip=t-1&past=abc')!.pastM, isNull);
      expect(parse('/overshoot?trip=t-1&past=2000000')!.pastM, isNull);
      expect(parse('/overshoot?trip=t-1&past=1000000')!.pastM, 1000000);
      expect(parse('/overshoot?trip=t-1&past=0')!.pastM, 0);
      expect(parse('/overshoot?trip=t-1&past=1.5')!.pastM, isNull);
      expect(parse('/overshoot?trip=t-1')!.autoOpen, isFalse);
      expect(parse('/overshoot?trip=t-1&open=true')!.autoOpen, isFalse);
      expect(parse('/overshoot?trip='), isNull);
      expect(parse('/overshoot?trip=a%2Fb'), isNull);
      expect(parse('/overshoot?trip=a b'), isNull);
      expect(parse('/overshoot?trip=${'x' * 65}'), isNull);
      expect(parse('/overshoot'), isNull);
    });

    test('toLocation round trip', () {
      for (final args in const [
        OvershootArgs(tripId: 't-1', pastM: 1500, autoOpen: true),
        OvershootArgs(tripId: 'abc_DEF-9'),
        OvershootArgs(tripId: 't', pastM: 0),
      ]) {
        expect(OvershootArgs.fromUri(Uri.parse(args.toLocation())), args);
      }
      expect(
        const OvershootArgs(
          tripId: 't-1',
          pastM: 1500,
          autoOpen: true,
        ).toLocation(),
        '/overshoot?trip=t-1&past=1500&open=1',
      );
      expect(
        const OvershootArgs(tripId: 't-1').toLocation(),
        '/overshoot?trip=t-1',
      );
    });

    test('toString prints no value', () {
      final text = const OvershootArgs(
        tripId: 'trip777',
        pastM: 1234,
        autoOpen: true,
      ).toString();
      expect(text, isNot(contains('1234')));
      expect(text, isNot(contains('trip777')));
    });

    test('alarmFallbackLocation', () {
      expect(alarmFallbackLocation('trip-1'), '/alarm?trip=trip-1');
      expect(isValidTripId('trip-1'), isTrue);
      expect(isValidTripId('bad/id'), isFalse);
      expect(isValidTripId(null), isFalse);
    });
  });

  test('U10 mayAutoOpen: within 48 h of the start', () {
    final now = DateTime(2026, 11, 5, 3);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    expect(mayAutoOpen(null, now), isFalse);
    expect(
      mayAutoOpen(
        sampleRecord(
          id: 'a',
          startedAtMs: ago(const Duration(hours: 47, minutes: 59)),
        ),
        now,
      ),
      isTrue,
    );
    expect(
      mayAutoOpen(
        sampleRecord(id: 'b', startedAtMs: ago(const Duration(hours: 48))),
        now,
      ),
      isTrue,
    );
    expect(
      mayAutoOpen(
        sampleRecord(
          id: 'c',
          startedAtMs: ago(const Duration(hours: 48, minutes: 1)),
        ),
        now,
      ),
      isFalse,
    );
  });
}
