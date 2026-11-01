/// Search query parsing and station core names (spec T24 §4.3, §7.2).
library;

import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/domain/station.dart';

/// Longer input is cut to this many runes before folding.
const int kMaxQueryLength = 64;

/// Folded kind prefixes, tried in this order (longer first). Same table as
/// `tools/stationgen/lib/src/prefixes.dart`.
const List<(List<String>, StationKind)> kKindPrefixes = [
  (['ben', 'xe', 'khach'], StationKind.coach),
  (['ben', 'xe', 'buyt'], StationKind.bus),
  (['tram', 'xe', 'buyt'], StationKind.bus),
  (['diem', 'trung', 'chuyen'], StationKind.bus),
  (['ga', 'tau'], StationKind.train),
  (['nha', 'ga'], StationKind.train),
  (['ben', 'xe'], StationKind.coach),
  (['xe', 'buyt'], StationKind.bus),
  (['ga'], StationKind.train),
];

/// A parsed search query.
final class StationQuery {
  const new({required this.tokens, this.kindHint});

  /// Folded tokens without the leading kind prefix.
  final List<String> tokens;

  /// Kind implied by a prefix such as "ga" or "bến xe".
  final StationKind? kindHint;
}

bool _startsWith(List<String> tokens, List<String> prefix) {
  if (tokens.length < prefix.length) {
    return false;
  }
  for (var i = 0; i < prefix.length; i++) {
    if (tokens[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// Parses raw user input. A kind prefix is removed only when tokens remain
/// after it ("ga" alone stays `[ga]` without a hint).
StationQuery parseStationQuery(String raw) {
  final runes = raw.runes;
  final cut = runes.length > kMaxQueryLength
      ? String.fromCharCodes(runes.take(kMaxQueryLength))
      : raw;
  final t = foldTokens(cut);
  for (final (prefix, kind) in kKindPrefixes) {
    if (t.length > prefix.length && _startsWith(t, prefix)) {
      return StationQuery(tokens: t.sublist(prefix.length), kindHint: kind);
    }
  }
  return StationQuery(tokens: t);
}

/// Core tokens of a station name or alias: folded tokens without the first
/// matching kind prefix, provided at least one token remains.
List<String> stationCoreTokens(String nameOrAlias) {
  final t = foldTokens(nameOrAlias);
  for (final (prefix, _) in kKindPrefixes) {
    if (t.length > prefix.length && _startsWith(t, prefix)) {
      return t.sublist(prefix.length);
    }
  }
  return t;
}
