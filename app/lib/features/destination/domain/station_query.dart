/// Search query parsing and station core names (spec T24 §4.3, §7.2).
library;

import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/domain/station.dart';

/// Longer input is cut to this many runes before folding.
const int kMaxQueryLength = 64;

/// Folded kind prefixes, tried in this order (longer first). Same table as
/// `tools/stationgen/lib/src/prefixes.dart`, plus the app-only bus stop
/// rows of T24.3 §6.3 (the tool does not build bus stops from prefixes);
/// `tram xe buyt` is `busStop` here and `bus` in the tool.
const List<(List<String>, StationKind)> kKindPrefixes = [
  (['diem', 'dung', 'xe', 'buyt'], StationKind.busStop),
  (['ben', 'xe', 'khach'], StationKind.coach),
  (['ben', 'xe', 'buyt'], StationKind.bus),
  (['tram', 'xe', 'buyt'], StationKind.busStop),
  (['diem', 'trung', 'chuyen'], StationKind.bus),
  (['diem', 'dung'], StationKind.busStop),
  (['tram', 'dung'], StationKind.busStop),
  (['tram', 'buyt'], StationKind.busStop),
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

/// Folded qualifier phrases stripped from the front of a coach/bus core name
/// for the "bến xe `city`" rule (T23 §4.3). Longest first.
const List<List<String>> kQualifierPhrases = [
  ['lien', 'tinh'],
  ['trung', 'tam'],
  ['thanh', 'pho'],
  ['phia', 'bac'],
  ['phia', 'nam'],
  ['phia', 'dong'],
  ['phia', 'tay'],
  ['tp'],
  ['bac'],
  ['nam'],
  ['dong'],
  ['tay'],
];

/// Repeatedly removes a leading phrase of [kQualifierPhrases] while at least
/// one token remains. Returns null when nothing was removed.
///
/// "Bến xe liên tỉnh phía Nam Nha Trang" → `[nha, trang]`; "Bến xe phía
/// Nam" → null (removing would leave nothing).
List<String>? stripLeadingQualifiers(List<String> coreTokens) {
  var rest = coreTokens;
  var removed = false;
  var progress = true;
  while (progress) {
    progress = false;
    for (final phrase in kQualifierPhrases) {
      if (rest.length > phrase.length && _startsWith(rest, phrase)) {
        rest = rest.sublist(phrase.length);
        removed = true;
        progress = true;
        break;
      }
    }
  }
  return removed ? rest : null;
}

/// Folded leading words of a province name that are not part of the name.
const List<List<String>> _provinceLeads = [
  ['thanh', 'pho'],
  ['tp'],
  ['tinh'],
];

/// Province tokens without a leading "tp" / "thanh pho" / "tinh" (keeps at
/// least one token): "TP. Hồ Chí Minh" → `[ho, chi, minh]`.
List<String> provinceCoreTokens(String province) {
  final t = foldTokens(province);
  for (final lead in _provinceLeads) {
    if (t.length > lead.length && _startsWith(t, lead)) {
      return t.sublist(lead.length);
    }
  }
  return t;
}
