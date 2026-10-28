/// Deterministic number and time formatting (spec T02 §2 D6, D7 and §7.4).
library;

final RegExp _negativeZero = RegExp(r'^-0(\.0+)?$');

/// Formats [x] with exactly [decimals] fraction digits.
///
/// `-0.00` style results are normalised to `0.00`.
String fmt(double x, int decimals) {
  if (!x.isFinite) {
    throw ArgumentError.value(x, 'x', 'must be finite');
  }
  final s = x.toStringAsFixed(decimals);
  return _negativeZero.hasMatch(s) ? s.substring(1) : s;
}

final RegExp _isoUtc = RegExp(r'^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$');

/// Pattern of a timestamp accepted by [parseIsoUtc].
RegExp get isoUtcPattern => _isoUtc;

/// Parses `YYYY-MM-DDTHH:MM:SSZ` into seconds since 1970-01-01T00:00:00Z.
///
/// Throws [FormatException] for any other shape or an invalid calendar date.
int parseIsoUtc(String text) {
  final m = _isoUtc.firstMatch(text);
  if (m == null) {
    throw FormatException('expected YYYY-MM-DDTHH:MM:SSZ', text);
  }
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  final second = int.parse(m.group(6)!);
  if (month < 1 || month > 12) {
    throw FormatException('month out of range', text);
  }
  if (day < 1 || day > _daysInMonth(year, month)) {
    throw FormatException('day out of range', text);
  }
  if (hour > 23 || minute > 59 || second > 59) {
    throw FormatException('time of day out of range', text);
  }
  return _daysFromCivil(year, month, day) * 86400 +
      hour * 3600 +
      minute * 60 +
      second;
}

/// Formats seconds since the Unix epoch as `YYYY-MM-DDTHH:MM:SSZ`.
String formatIsoUtc(int epochSeconds) {
  final days = _floorDiv(epochSeconds, 86400);
  final secOfDay = epochSeconds - days * 86400;
  final (year, month, day) = _civilFromDays(days);
  final hour = secOfDay ~/ 3600;
  final minute = (secOfDay % 3600) ~/ 60;
  final second = secOfDay % 60;
  return '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}'
      'T${_pad(hour, 2)}:${_pad(minute, 2)}:${_pad(second, 2)}Z';
}

/// Timestamp of the tick [offsetS] seconds after [startEpochS].
String isoUtc(int startEpochS, int offsetS) =>
    formatIsoUtc(startEpochS + offsetS);

String _pad(int v, int width) => v.toString().padLeft(width, '0');

int _floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

int _daysInMonth(int year, int month) => switch (month) {
  2 => _isLeap(year) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

// Howard Hinnant's days_from_civil / civil_from_days (proleptic Gregorian).
int _daysFromCivil(int year, int month, int day) {
  final y = month <= 2 ? year - 1 : year;
  final era = _floorDiv(y, 400);
  final yoe = y - era * 400;
  final mp = (month + 9) % 12;
  final doy = (153 * mp + 2) ~/ 5 + day - 1;
  final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
  return era * 146097 + doe - 719468;
}

(int, int, int) _civilFromDays(int days) {
  final z = days + 719468;
  final era = _floorDiv(z, 146097);
  final doe = z - era * 146097;
  final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
  final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
  final mp = (5 * doy + 2) ~/ 153;
  final day = doy - (153 * mp + 2) ~/ 5 + 1;
  final month = mp < 10 ? mp + 3 : mp - 9;
  final year = yoe + era * 400 + (month <= 2 ? 1 : 0);
  return (year, month, day);
}
