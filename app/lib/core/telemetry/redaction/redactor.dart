/// Safety net for every text that may leave the device or reach a log (T29
/// §4.2): coordinate-like numbers and `lat=`-style pairs are masked. It does
/// not recognise place names; those must never be written in the first
/// place (T29 §4.3, TC23).
///
/// This is the only telemetry file allowed to spell the coordinate key
/// names (TC24).
library;

/// `lat=21`, `destLng: 105.85`… (case-insensitive).
final RegExp _keyValue = RegExp(
  r'\b(lat|lng|lon|latitude|longitude|destlat|destlng)\b\s*[:=]\s*-?\d+(?:[.,]\d+)?',
  caseSensitive: false,
);

/// A decimal number with at least 3 fractional digits: `21.0285`, `105,854`.
final RegExp kCoordinateNumberPattern = RegExp(r'-?\d{1,3}[.,]\d{3,}');

/// A coordinate key name followed by a number (`lat=21`, `lng 105`,
/// `latitude:-6`). Used by the Analytics guard.
final RegExp kCoordinateKeyPattern = RegExp(
  r'(lat|lng|lon)[a-z_]*\s*[:=]?\s*-?\d',
  caseSensitive: false,
);

/// Longest redacted text, before the ellipsis.
const int kRedactMaxLength = 1024;

/// Applied in order, idempotent (`redact(redact(x)) == redact(x)`):
/// 1. `lat=…`-style pairs → `lat=<redacted>` (key spelling kept);
/// 2. coordinate-like numbers → `<num>`;
/// 3. cut to [maxLength] UTF-16 units plus `…` (never inside a surrogate
///    pair).
String redact(String input, {int maxLength = kRedactMaxLength}) {
  var out = input
      .replaceAllMapped(_keyValue, (m) => '${m[1]}=<redacted>')
      .replaceAll(kCoordinateNumberPattern, '<num>');
  if (out.length > maxLength) {
    var cut = maxLength;
    final last = out.codeUnitAt(cut - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      cut--;
    }
    out = '${out.substring(0, cut)}…';
  }
  return out;
}
