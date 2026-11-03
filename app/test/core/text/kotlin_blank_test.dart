// T25: Kotlin isBlank set (T12 test report "Tập rỗng").
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/kotlin_blank.dart';

void main() {
  test('blank like Kotlin: empty, RFC whitespace, separators, NBSP', () {
    for (final s in [
      '',
      ' ',
      '\t',
      '\n',
      '\r\n',
      '\u000B',
      '\u000C',
      '\u001C',
      '\u001D',
      '\u001E',
      '\u001F',
      '\u00A0',
      '\u1680',
      '\u2000',
      '\u2007',
      '\u200A',
      '\u2028',
      '\u2029',
      '\u202F',
      '\u205F',
      '\u3000',
      ' \u00A0\t\u3000\n',
    ]) {
      expect(isBlankLikeKotlin(s), isTrue, reason: s.codeUnits.toString());
    }
  });

  test('not blank: ZWSP, BOM, NEL, U+180E, U+2060, NUL, text', () {
    for (final s in [
      '\u200B',
      '\uFEFF',
      '\u0085',
      '\u180E',
      '\u2060',
      '\u0000',
      ' \u200B ',
      ' a ',
      '{}',
    ]) {
      expect(isBlankLikeKotlin(s), isFalse, reason: s.codeUnits.toString());
    }
  });

  test('differs from String.trim on purpose', () {
    expect('\u0085'.trim(), isEmpty);
    expect(isBlankLikeKotlin('\u0085'), isFalse);
    expect('\u001C'.trim(), isNotEmpty);
    expect(isBlankLikeKotlin('\u001C'), isTrue);
  });
}
