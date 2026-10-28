// -0.0 must stay a double literal here.
// ignore_for_file: prefer_int_literals

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

void main() {
  group('fmt (TC16)', () {
    test('normalises negative zero', () {
      expect(fmt(-0.0, 2), '0.00');
      expect(fmt(-1e-10, 7), '0.0000000');
      expect(fmt(-0.0, 0), '0');
    });

    test('equals toStringAsFixed otherwise', () {
      expect(fmt(21.02421445, 7), 21.02421445.toStringAsFixed(7));
      expect(fmt(0.05, 1), 0.05.toStringAsFixed(1));
      expect(fmt(-1.25, 1), (-1.25).toStringAsFixed(1));
    });

    test('rejects non-finite numbers', () {
      expect(() => fmt(double.nan, 1), throwsArgumentError);
      expect(() => fmt(double.infinity, 1), throwsArgumentError);
    });
  });

  group('ISO UTC timestamps (TC16)', () {
    final start = parseIsoUtc('2026-03-14T12:30:00Z');

    test('adds seconds', () {
      expect(isoUtc(start, 0), '2026-03-14T12:30:00Z');
      expect(isoUtc(start, 3661), '2026-03-14T13:31:01Z');
    });

    test('crosses midnight, month, year and leap day', () {
      expect(isoUtc(start, 11 * 3600 + 30 * 60), '2026-03-15T00:00:00Z');
      expect(
        isoUtc(parseIsoUtc('2026-03-31T23:59:59Z'), 1),
        '2026-04-01T00:00:00Z',
      );
      expect(
        isoUtc(parseIsoUtc('2026-12-31T23:59:59Z'), 1),
        '2027-01-01T00:00:00Z',
      );
      expect(
        isoUtc(parseIsoUtc('2028-02-28T23:00:00Z'), 3600),
        '2028-02-29T00:00:00Z',
      );
    });

    test('matches DateTime.utc', () {
      final epoch =
          DateTime.utc(2026, 3, 14, 12, 30).millisecondsSinceEpoch ~/ 1000;
      expect(start, epoch);
      for (final offset in [0, 1, 86399, 86400, 40000000]) {
        final dt = DateTime.fromMillisecondsSinceEpoch(
          (epoch + offset) * 1000,
          isUtc: true,
        );
        expect(
          isoUtc(start, offset),
          '${dt.toIso8601String().substring(0, 19)}Z',
        );
      }
    });

    test('rejects malformed timestamps', () {
      for (final bad in [
        '2026-03-14T12:30:00',
        '2026-03-14T12:30:00.000Z',
        '2026-03-14 12:30:00Z',
        '2026-02-30T00:00:00Z',
        '2026-13-01T00:00:00Z',
        '2026-03-14T24:00:00Z',
      ]) {
        expect(() => parseIsoUtc(bad), throwsFormatException, reason: bad);
      }
    });
  });
}
