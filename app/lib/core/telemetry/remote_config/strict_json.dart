/// JSON reader with exactly the grammar of the native `MiniJson`
/// (`app/android/core-trip/.../MiniJson.kt`, T12 §7.1, C12, C15), so the
/// Dart side accepts and rejects the same Remote Config strings as the
/// engine. `dart:convert` differs: it accepts nesting deeper than 64 and
/// unpaired surrogates (escaped or raw).
///
/// PRIVACY: error messages carry the rule and the offset, never input text.
library;

import 'package:meta/meta.dart';

/// A number with its original lexeme (validated RFC 8259 grammar). The
/// native side reads it with `String.toDouble()`; [asDouble] uses
/// `double.parse`, which also rounds correctly.
@immutable
final class JsonNumberLexeme {
  const new(this.lexeme);

  final String lexeme;

  double asDouble() => double.parse(lexeme);

  @override
  bool operator ==(Object other) =>
      other is JsonNumberLexeme && other.lexeme == lexeme;

  @override
  int get hashCode => lexeme.hashCode;

  @override
  String toString() => 'JsonNumberLexeme(<redacted>)';
}

/// Nesting deeper than this (arrays + objects) is a syntax error (C15).
const int kStrictJsonMaxDepth = 64;

/// Parses [text]. Objects become `Map<String, Object?>` (a duplicate key keeps
/// the last value, C12), arrays `List<Object?>`, numbers [JsonNumberLexeme],
/// plus `String`, `bool` and `null`. Throws [FormatException] on any
/// syntax error; only RFC 8259 whitespace may surround the value.
Object? parseStrictJson(String text) {
  final p = _Parser(text)..skipWs();
  final value = p.value(0);
  p.skipWs();
  if (p.pos != text.length) {
    p.fail('trailing content');
  }
  return value;
}

final class _Parser {
  new(this.s);

  final String s;
  int pos = 0;

  Never fail(String rule) => throw FormatException('json: $rule at $pos');

  int get _c => s.codeUnitAt(pos);

  bool get _atEnd => pos >= s.length;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  void skipWs() {
    while (!_atEnd) {
      final c = _c;
      // space, \t, \n, \r only.
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        pos++;
      } else {
        break;
      }
    }
  }

  Object? value(int depth) {
    if (_atEnd) {
      fail('unexpected end');
    }
    final c = _c;
    switch (c) {
      case 0x7B: // {
        return object(depth + 1);
      case 0x5B: // [
        return array(depth + 1);
      case 0x22: // "
        return string();
      case 0x74: // t
        return literal('true', true);
      case 0x66: // f
        return literal('false', false);
      case 0x6E: // n
        return literal('null', null);
    }
    if (c == 0x2D || _isDigit(c)) {
      return number();
    }
    fail('unexpected character');
  }

  Object? literal(String word, Object? v) {
    if (!s.startsWith(word, pos)) {
      fail('invalid literal');
    }
    pos += word.length;
    return v;
  }

  Map<String, Object?> object(int depth) {
    if (depth > kStrictJsonMaxDepth) {
      fail('too deep');
    }
    pos++; // {
    final fields = <String, Object?>{};
    skipWs();
    if (!_atEnd && _c == 0x7D) {
      pos++;
      return fields;
    }
    while (true) {
      skipWs();
      if (_atEnd || _c != 0x22) {
        fail('expected key');
      }
      final key = string();
      skipWs();
      if (_atEnd || _c != 0x3A) {
        fail('expected colon');
      }
      pos++;
      skipWs();
      fields[key] = value(depth);
      skipWs();
      if (_atEnd) {
        fail('unexpected end');
      }
      switch (_c) {
        case 0x2C: // ,
          pos++;
        case 0x7D: // }
          pos++;
          return fields;
        default:
          fail('expected comma or brace');
      }
    }
  }

  List<Object?> array(int depth) {
    if (depth > kStrictJsonMaxDepth) {
      fail('too deep');
    }
    pos++; // [
    final items = <Object?>[];
    skipWs();
    if (!_atEnd && _c == 0x5D) {
      pos++;
      return items;
    }
    while (true) {
      skipWs();
      items.add(value(depth));
      skipWs();
      if (_atEnd) {
        fail('unexpected end');
      }
      switch (_c) {
        case 0x2C: // ,
          pos++;
        case 0x5D: // ]
          pos++;
          return items;
        default:
          fail('expected comma or bracket');
      }
    }
  }

  static bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;

  static bool _isLow(int c) => c >= 0xDC00 && c <= 0xDFFF;

  String string() {
    pos++; // opening quote
    final sb = StringBuffer();
    while (true) {
      if (_atEnd) {
        fail('unterminated string');
      }
      final c = _c;
      if (c == 0x22) {
        pos++;
        return sb.toString();
      }
      if (c == 0x5C) {
        pos++;
        if (_atEnd) {
          fail('unterminated string');
        }
        switch (_c) {
          case 0x22:
            sb.writeCharCode(0x22);
          case 0x5C:
            sb.writeCharCode(0x5C);
          case 0x2F:
            sb.writeCharCode(0x2F);
          case 0x62: // b
            sb.writeCharCode(0x08);
          case 0x66: // f
            sb.writeCharCode(0x0C);
          case 0x6E: // n
            sb.writeCharCode(0x0A);
          case 0x72: // r
            sb.writeCharCode(0x0D);
          case 0x74: // t
            sb.writeCharCode(0x09);
          case 0x75: // u
            final hi = hex4(pos + 1);
            pos += 4;
            if (_isHigh(hi)) {
              if (pos + 2 < s.length &&
                  s.codeUnitAt(pos + 1) == 0x5C &&
                  s.codeUnitAt(pos + 2) == 0x75) {
                final lo = hex4(pos + 3);
                if (!_isLow(lo)) {
                  fail('lone surrogate');
                }
                sb
                  ..writeCharCode(hi)
                  ..writeCharCode(lo);
                pos += 6;
              } else {
                fail('lone surrogate');
              }
            } else if (_isLow(hi)) {
              fail('lone surrogate');
            } else {
              sb.writeCharCode(hi);
            }
          default:
            fail('invalid escape');
        }
        pos++;
        continue;
      }
      if (c < 0x20) {
        fail('control character in string');
      }
      if (_isHigh(c)) {
        if (pos + 1 >= s.length || !_isLow(s.codeUnitAt(pos + 1))) {
          fail('lone surrogate');
        }
        sb
          ..writeCharCode(c)
          ..writeCharCode(s.codeUnitAt(pos + 1));
        pos += 2;
        continue;
      }
      if (_isLow(c)) {
        fail('lone surrogate');
      }
      sb.writeCharCode(c);
      pos++;
    }
  }

  int hex4(int at) {
    if (at + 4 > s.length) {
      fail('invalid unicode escape');
    }
    var v = 0;
    for (var i = at; i < at + 4; i++) {
      final c = s.codeUnitAt(i);
      final int d;
      if (_isDigit(c)) {
        d = c - 0x30;
      } else if (c >= 0x61 && c <= 0x66) {
        d = c - 0x61 + 10;
      } else if (c >= 0x41 && c <= 0x46) {
        d = c - 0x41 + 10;
      } else {
        fail('invalid unicode escape');
      }
      v = v * 16 + d;
    }
    return v;
  }

  JsonNumberLexeme number() {
    final start = pos;
    if (_c == 0x2D) {
      pos++;
    }
    if (_atEnd) {
      fail('invalid number');
    }
    if (_c == 0x30) {
      pos++;
      if (!_atEnd && _isDigit(_c)) {
        fail('leading zero');
      }
    } else if (_c >= 0x31 && _c <= 0x39) {
      while (!_atEnd && _isDigit(_c)) {
        pos++;
      }
    } else {
      fail('invalid number');
    }
    if (!_atEnd && _c == 0x2E) {
      pos++;
      if (_atEnd || !_isDigit(_c)) {
        fail('invalid number');
      }
      while (!_atEnd && _isDigit(_c)) {
        pos++;
      }
    }
    if (!_atEnd && (_c == 0x65 || _c == 0x45)) {
      pos++;
      if (!_atEnd && (_c == 0x2B || _c == 0x2D)) {
        pos++;
      }
      if (_atEnd || !_isDigit(_c)) {
        fail('invalid number');
      }
      while (!_atEnd && _isDigit(_c)) {
        pos++;
      }
    }
    return JsonNumberLexeme(s.substring(start, pos));
  }
}
