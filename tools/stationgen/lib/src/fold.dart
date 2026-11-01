/// Vietnamese diacritic folding (spec T24 §5).
///
/// Must stay identical to `app/lib/core/text/vn_fold.dart`; both run the
/// shared vectors in `data/stations/fold_vectors.json`.
library;

// Lower case and upper case letters with Vietnamese diacritics, grouped by
// their base letter. Written out explicitly so folding never depends on
// `toLowerCase` (locale/ICU independent).
const List<(String, String, String)> _kViLetters = [
  ('a', 'àáảãạăằắẳẵặâầấẩẫậ', 'ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ'),
  ('e', 'èéẻẽẹêềếểễệ', 'ÈÉẺẼẸÊỀẾỂỄỆ'),
  ('i', 'ìíỉĩị', 'ÌÍỈĨỊ'),
  ('o', 'òóỏõọôồốổỗộơờớởỡợ', 'ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ'),
  ('u', 'ùúủũụưừứửữự', 'ÙÚỦŨỤƯỪỨỬỮỰ'),
  ('y', 'ỳýỷỹỵ', 'ỲÝỶỸỴ'),
  ('d', 'đ', 'Đ'),
];

/// Rune → folded ASCII rune for the 67 lower case + 67 upper case letters.
final Map<int, int> kViFold = _buildFoldTable();

Map<int, int> _buildFoldTable() {
  final table = <int, int>{};
  for (final (base, lower, upper) in _kViLetters) {
    final b = base.codeUnitAt(0);
    for (final r in lower.runes) {
      table[r] = b;
    }
    for (final r in upper.runes) {
      table[r] = b;
    }
  }
  return table;
}

const int _space = 0x20;

/// Folds [input] to lower case ASCII words separated by single spaces:
/// diacritics removed (NFC and NFD), `đ` → `d`, anything that is not a
/// letter or digit becomes a separator.
String foldVi(String input) {
  final out = StringBuffer();
  var pendingSpace = false;
  for (final r in input.runes) {
    if (r >= 0x0300 && r <= 0x036F) {
      continue;
    }
    var c = kViFold[r] ?? r;
    if (c >= 0x41 && c <= 0x5A) {
      c += 32;
    }
    final keep = (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39);
    if (!keep) {
      pendingSpace = true;
      continue;
    }
    if (pendingSpace && out.isNotEmpty) {
      out.writeCharCode(_space);
    }
    pendingSpace = false;
    out.writeCharCode(c);
  }
  return out.toString();
}

/// Tokens of [foldVi]; empty input gives an empty list.
List<String> foldTokens(String input) {
  final s = foldVi(input);
  return s.isEmpty ? const [] : s.split(' ');
}
