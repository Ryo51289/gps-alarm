/// Canonical JSON writer (spec T02 §7.4).
///
/// Layout matches `JsonEncoder.withIndent('  ')`, keys keep insertion order,
/// decimals must be wrapped in [Fixed] so every number has a pinned format.
library;

import 'package:tracegen/src/fmt.dart';

/// A decimal number printed with exactly [decimals] fraction digits.
final class Fixed {
  const new(this.value, this.decimals);

  final double value;
  final int decimals;
}

/// Encodes [value] (maps with string keys, lists, strings, ints, bools,
/// null and [Fixed]) with 2-space indentation and a trailing newline.
///
/// Plain doubles are rejected: use [Fixed].
String canonicalJson(Object? value) {
  final sb = StringBuffer();
  _write(sb, value, '');
  sb.write('\n');
  return sb.toString();
}

void _write(StringBuffer sb, Object? value, String indent) {
  switch (value) {
    case null:
      sb.write('null');
    case bool():
      sb.write(value ? 'true' : 'false');
    case int():
      sb.write(value.toString());
    case Fixed():
      sb.write(fmt(value.value, value.decimals));
    case String():
      _writeString(sb, value);
    case List<Object?>():
      if (value.isEmpty) {
        sb.write('[]');
        return;
      }
      final inner = '$indent  ';
      sb.write('[\n');
      for (var i = 0; i < value.length; i++) {
        sb.write(inner);
        _write(sb, value[i], inner);
        sb.write(i + 1 < value.length ? ',\n' : '\n');
      }
      sb
        ..write(indent)
        ..write(']');
    case Map<String, Object?>():
      if (value.isEmpty) {
        sb.write('{}');
        return;
      }
      final inner = '$indent  ';
      sb.write('{\n');
      var i = 0;
      for (final entry in value.entries) {
        sb.write(inner);
        _writeString(sb, entry.key);
        sb.write(': ');
        _write(sb, entry.value, inner);
        i++;
        sb.write(i < value.length ? ',\n' : '\n');
      }
      sb
        ..write(indent)
        ..write('}');
    default:
      throw ArgumentError.value(
        value,
        'value',
        'unsupported JSON value of type ${value.runtimeType}',
      );
  }
}

void _writeString(StringBuffer sb, String s) {
  sb.write('"');
  for (final unit in s.codeUnits) {
    switch (unit) {
      case 0x22:
        sb.write(r'\"');
      case 0x5C:
        sb.write(r'\\');
      case 0x08:
        sb.write(r'\b');
      case 0x0C:
        sb.write(r'\f');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (unit < 0x20) {
          sb
            ..write(r'\u00')
            ..write(unit.toRadixString(16).padLeft(2, '0'));
        } else {
          sb.writeCharCode(unit);
        }
    }
  }
  sb.write('"');
}
