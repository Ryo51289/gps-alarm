/// Station kinds and the kind prefixes shared by the tool and the app
/// (spec T24 §4.3). Keep in sync with
/// `app/lib/features/destination/domain/station_query.dart`.
library;

import 'package:stationgen/src/fold.dart';

/// Station kind; declaration order is the sort / tie-break order.
enum StationKind {
  train,
  coach,
  bus;

  /// Parses `train` / `coach` / `bus`; null for anything else.
  static StationKind? tryParse(String? s) {
    for (final k in values) {
      if (k.name == s) {
        return k;
      }
    }
    return null;
  }
}

/// Folded kind prefixes, tried in this order (longer first).
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

/// True when [tokens] starts with [prefix].
bool startsWithTokens(List<String> tokens, List<String> prefix) {
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

/// Core tokens of a station name or alias: [foldTokens] without the first
/// matching kind prefix, provided at least one token remains.
List<String> coreTokens(String nameOrAlias) {
  final t = foldTokens(nameOrAlias);
  for (final (prefix, _) in kKindPrefixes) {
    if (t.length > prefix.length && startsWithTokens(t, prefix)) {
      return t.sublist(prefix.length);
    }
  }
  return t;
}

/// True when [needle] occurs as a contiguous run of tokens in [haystack].
bool containsTokenRun(List<String> haystack, List<String> needle) {
  if (needle.isEmpty) {
    return true;
  }
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return true;
    }
  }
  return false;
}
