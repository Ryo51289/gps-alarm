/// Pure logic of the address search of screen 2 (T23.5 §4.1): when to
/// search, which suggestions to show, whether a resolved point is a
/// supported destination. No Flutter, no map SDK.
///
/// PRIVACY: nothing here logs, and no `toString` prints a typed text, a
/// suggestion or coordinates.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

/// Letters/digits needed before the address search runs (D5).
const int kMinAddressQueryChars = 3;

/// Wait after the last keystroke before asking Apple (D5).
const Duration kAddressDebounce = Duration(milliseconds: 400);

/// Most address rows shown.
const int kAddressDisplayLimit = 5;

/// Most suggestions accepted from the native side.
const int kMaxAddressItems = 15;

/// Pause after Apple rate-limited the search (D14).
const Duration kAddressThrottleCooldown = Duration(seconds: 30);

/// One suggestion of Apple Maps: text only, no coordinates yet.
@immutable
final class AddressSuggestion {
  const new({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  bool operator ==(Object other) =>
      other is AddressSuggestion &&
      other.title == title &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(title, subtitle);

  /// PRIVACY: no text.
  @override
  String toString() => 'AddressSuggestion';
}

/// One displayed row: `nativeIndex` is the index in the list the native side
/// returned (what `resolve` needs).
typedef AddressRow = ({int nativeIndex, AddressSuggestion suggestion});

/// D5: only on chip "Tất cả", with at least [kMinAddressQueryChars] letters
/// or digits.
bool shouldSearchAddresses({
  required String query,
  required DestinationFilter filter,
}) =>
    filter == DestinationFilter.all &&
    queryChars(query) >= kMinAddressQueryChars;

/// D9: token sequences (after `foldVi`) that mark a suggestion Apple may label
/// on the Chinese side; everything in China is outside the supported area
/// anyway. "Hoàng Sa" and "Trường Sa" are street names in Vietnam and are
/// not blocked.
const List<List<String>> kBlockedSuggestionTokens = [
  ['trung', 'quoc'],
  ['china'],
  ['hainan'],
  ['sansha'],
  ['xisha'],
  ['nansha'],
  ['paracel'],
  ['spratly'],
];

bool _hasCjk(String s) {
  for (final r in s.runes) {
    if (r >= 0x4E00 && r <= 0x9FFF) {
      return true;
    }
  }
  return false;
}

bool _containsSequence(List<String> tokens, List<String> seq) {
  for (var i = 0; i + seq.length <= tokens.length; i++) {
    var all = true;
    for (var j = 0; j < seq.length; j++) {
      if (tokens[i + j] != seq[j]) {
        all = false;
        break;
      }
    }
    if (all) {
      return true;
    }
  }
  return false;
}

/// D9.
bool isBlockedSuggestion(AddressSuggestion s) {
  if (_hasCjk(s.title) || _hasCjk(s.subtitle)) {
    return true;
  }
  final tokens = foldTokens('${s.title} ${s.subtitle}');
  return kBlockedSuggestionTokens.any((seq) => _containsSequence(tokens, seq));
}

/// Drops blank titles, blocked suggestions (D9) and duplicates (same folded
/// title and subtitle, the first is kept), keeps the original index of each
/// row and returns at most [kAddressDisplayLimit].
List<AddressRow> visibleSuggestions(List<AddressSuggestion> raw) {
  final seen = <String>{};
  final rows = <AddressRow>[];
  for (final (i, s) in raw.indexed) {
    if (rows.length >= kAddressDisplayLimit) {
      break;
    }
    if (s.title.trim().isEmpty || isBlockedSuggestion(s)) {
      continue;
    }
    if (!seen.add('${foldVi(s.title)}|${foldVi(s.subtitle)}')) {
      continue;
    }
    rows.add((nativeIndex: i, suggestion: s));
  }
  return List.unmodifiable(rows);
}

/// D8: [country] is null or "VN" and [p] lies inside [kVietnamBounds]. The two
/// archipelagos lie east of the box, so they are never accepted.
bool isSupportedDestination(MapPoint p, {String? country}) =>
    (country == null || country.toUpperCase() == 'VN') &&
    kVietnamBounds.contains(p);

/// Trimmed [s], at most [kMaxDestinationNameLength] UTF-16 units (what
/// `TripDestination.isValid` checks), never splitting a surrogate pair.
String _clip(String s) {
  final t = s.trim();
  if (t.length <= kMaxDestinationNameLength) {
    return t;
  }
  final last = t.codeUnitAt(kMaxDestinationNameLength - 1);
  final cut = last >= 0xD800 && last <= 0xDBFF
      ? kMaxDestinationNameLength - 1
      : kMaxDestinationNameLength;
  return t.substring(0, cut);
}

/// D7: the destination of a resolved suggestion; kind address. The subtitle
/// is the detail, null when blank.
TripDestination addressDestination(AddressSuggestion s, MapPoint p) {
  final subtitle = _clip(s.subtitle);
  return TripDestination(
    name: _clip(s.title),
    lat: p.lat,
    lng: p.lng,
    kind: DestinationKind.address,
    detail: subtitle.isEmpty ? null : subtitle,
  );
}
