/// "Blank" exactly like Kotlin `CharSequence.isBlank()` on the JVM, which the
/// native side uses for Remote Config JSON (T12 §7.2) and for the destination
/// name (T14 V2). Dart's `String.trim()` uses another set: it also strips
/// U+0085 and U+FEFF and keeps U+001C..U+001F.
library;

/// True when every UTF-16 unit of [s] is `Character.isWhitespace` or
/// `Character.isSpaceChar` (Java 17, Unicode 13); true for ''.
///
/// The set, checked by the T12 tester ("Tập rỗng" in
/// docs/test-reports/T12.md): U+0009..U+000D, U+001C..U+0020, U+00A0,
/// U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F, U+3000. Not
/// blank: U+200B, U+FEFF, U+0085, U+180E, U+2060, U+0000.
bool isBlankLikeKotlin(String s) {
  for (final unit in s.codeUnits) {
    if (!_isKotlinWhitespace(unit)) {
      return false;
    }
  }
  return true;
}

bool _isKotlinWhitespace(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    (c >= 0x1C && c <= 0x20) ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;
