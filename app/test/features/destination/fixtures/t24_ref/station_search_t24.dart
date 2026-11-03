/// FROZEN COPY (tester T23) of
/// `lib/features/destination/domain/station_search.dart` as committed in HEAD
/// (last change: T24), before T23. Reference for the ranking differential
/// test `station_search_t24_differential_tester_test.dart`; never edit.
/// Original header:
///
/// Ranked offline station search (spec T24 §7.3). Pure Dart, no Flutter.
///
/// Never log queries or results: a destination is location data of the
/// user (spec §8).
library;

import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';

/// Default maximum number of results.
const int kDefaultSearchLimit = 20;

/// Match tiers, best first.
enum StationMatchTier {
  exact,
  prefix,
  orderedTokens,
  anyOrderTokens,
  provinceAssisted,
  substring,
  fuzzy,
}

/// One search result.
final class StationMatch {
  const new({
    required this.station,
    required this.score,
    required this.tier,
    required this.viaAlias,
  });

  final Station station;
  final int score;
  final StationMatchTier tier;

  /// The best key was an alias, not the display name.
  final bool viaAlias;

  @override
  String toString() =>
      'StationMatch(${station.id}, $score, ${tier.name}, alias: $viaAlias)';
}

const int _aliasPenalty = 25;
const int _kindHintBonus = 150;

final class _Key {
  const new(this.tokens, this.text, {required this.alias});

  final List<String> tokens;
  final String text;
  final bool alias;
}

final class _Entry {
  const new(this.station, this.keys, this.provinceTokens);

  final Station station;
  final List<_Key> keys;
  final List<String> provinceTokens;
}

/// In-memory index over the dataset; linear scan with precomputed keys.
final class StationSearchIndex {
  /// Precomputes the core tokens of names and aliases and the province
  /// tokens.
  factory(List<Station> stations) {
    final entries = <_Entry>[];
    for (final s in stations) {
      final keys = <_Key>[];
      for (final (i, text) in [s.name, ...s.aliases].indexed) {
        final tokens = stationCoreTokens(text);
        if (tokens.isNotEmpty) {
          keys.add(
            _Key(List.unmodifiable(tokens), tokens.join(' '), alias: i > 0),
          );
        }
      }
      entries.add(_Entry(s, List.unmodifiable(keys), foldTokens(s.province)));
    }
    return StationSearchIndex._(List.unmodifiable(entries));
  }

  new _(this._entries);

  final List<_Entry> _entries;

  /// Number of indexed stations.
  int get length => _entries.length;

  /// Ranked matches for [query], at most [limit]. Empty query → `[]`.
  List<StationMatch> search(String query, {int limit = kDefaultSearchLimit}) {
    final q = parseStationQuery(query);
    if (q.tokens.isEmpty || limit <= 0) {
      return const [];
    }
    final qs = q.tokens.join(' ');
    final found = <(StationMatch, int)>[];
    for (final e in _entries) {
      StationMatch? best;
      var bestLen = 0;
      for (final k in e.keys) {
        final m = _matchKey(k, q.tokens, qs, e.provinceTokens);
        if (m == null) {
          continue;
        }
        final (tier, base) = m;
        final score =
            base -
            (k.alias ? _aliasPenalty : 0) +
            (q.kindHint == e.station.kind ? _kindHintBonus : 0);
        // Keys are in order name, alias 1, alias 2 …: on a tie the earlier
        // (non-alias) key wins.
        if (best == null || score > best.score) {
          best = StationMatch(
            station: e.station,
            score: score,
            tier: tier,
            viaAlias: k.alias,
          );
          bestLen = k.text.length;
        }
      }
      if (best != null) {
        found.add((best, bestLen));
      }
    }
    found.sort(_compareFound);
    return [for (final (m, _) in found.take(limit)) m];
  }
}

int _compareFound((StationMatch, int) a, (StationMatch, int) b) {
  final (ma, la) = a;
  final (mb, lb) = b;
  var c = mb.score.compareTo(ma.score);
  if (c != 0) {
    return c;
  }
  c = ma.station.kind.index.compareTo(mb.station.kind.index);
  if (c != 0) {
    return c;
  }
  c = la.compareTo(lb);
  if (c != 0) {
    return c;
  }
  c = ma.station.nameAscii.compareTo(mb.station.nameAscii);
  if (c != 0) {
    return c;
  }
  return ma.station.id.compareTo(mb.station.id);
}

(StationMatchTier, int)? _matchKey(
  _Key k,
  List<String> q,
  String qs,
  List<String> province,
) {
  if (k.text == qs) {
    return (StationMatchTier.exact, 1000);
  }
  if (k.text.startsWith(qs)) {
    return (StationMatchTier.prefix, 900);
  }
  if (_orderedTokens(k.tokens, q)) {
    return (StationMatchTier.orderedTokens, 700);
  }
  if (_anyOrderTokens(k.tokens, q, const [], requireKeyMatch: false)) {
    return (StationMatchTier.anyOrderTokens, 600);
  }
  if (province.isNotEmpty &&
      _anyOrderTokens(k.tokens, q, province, requireKeyMatch: true)) {
    return (StationMatchTier.provinceAssisted, 500);
  }
  if (qs.length >= 3 && k.text.contains(qs)) {
    return (StationMatchTier.substring, 300);
  }
  final errors = _fuzzyErrors(k.tokens, q);
  if (errors != null && errors >= 1) {
    return (StationMatchTier.fuzzy, 200 - 50 * errors);
  }
  return null;
}

/// Increasing j1 < j2 < … with `key[j_i].startsWith(q[i])`, chosen greedily.
bool _orderedTokens(List<String> key, List<String> q) {
  var j = 0;
  for (final t in q) {
    while (j < key.length && !key[j].startsWith(t)) {
      j++;
    }
    if (j == key.length) {
      return false;
    }
    j++;
  }
  return true;
}

/// Every `q[i]` prefixes a distinct key token, or (with [extra]) a distinct
/// token of [extra]; greedy in query order.
bool _anyOrderTokens(
  List<String> key,
  List<String> q,
  List<String> extra, {
  required bool requireKeyMatch,
}) {
  final usedKey = List<bool>.filled(key.length, false);
  final usedExtra = List<bool>.filled(extra.length, false);
  var keyMatches = 0;
  for (final t in q) {
    final j = _firstFree(key, usedKey, t);
    if (j >= 0) {
      usedKey[j] = true;
      keyMatches++;
      continue;
    }
    final x = _firstFree(extra, usedExtra, t);
    if (x < 0) {
      return false;
    }
    usedExtra[x] = true;
  }
  return !requireKeyMatch || keyMatches >= 1;
}

int _firstFree(List<String> tokens, List<bool> used, String prefix) {
  for (var j = 0; j < tokens.length; j++) {
    if (!used[j] && tokens[j].startsWith(prefix)) {
      return j;
    }
  }
  return -1;
}

/// Allowed edits for a query token of [length] runes.
int _maxEdits(int length) => length >= 8
    ? 2
    : length >= 4
    ? 1
    : 0;

/// Total edits when every query token matches a distinct key token (prefix
/// = 0 edits, otherwise OSA within [_maxEdits], same first letter); null
/// when some token does not match.
int? _fuzzyErrors(List<String> key, List<String> q) {
  final used = List<bool>.filled(key.length, false);
  var total = 0;
  for (final t in q) {
    final max = _maxEdits(t.length);
    var best = -1;
    var bestErr = max + 1;
    for (var j = 0; j < key.length; j++) {
      if (used[j]) {
        continue;
      }
      final k = key[j];
      if (k.startsWith(t)) {
        best = j;
        bestErr = 0;
        break;
      }
      if (max == 0 || k.codeUnitAt(0) != t.codeUnitAt(0)) {
        continue;
      }
      final whole = osaDistance(t, k, max: max);
      final head = k.length > t.length
          ? osaDistance(t, k.substring(0, t.length), max: max)
          : whole;
      final e = whole < head ? whole : head;
      if (e < bestErr) {
        best = j;
        bestErr = e;
      }
    }
    if (best < 0) {
      return null;
    }
    used[best] = true;
    total += bestErr;
  }
  return total;
}

/// Optimal string alignment distance (insert, delete, substitute, swap two
/// adjacent characters) between [a] and [b]; returns `max + 1` as soon as
/// the distance is known to exceed [max].
int osaDistance(String a, String b, {required int max}) {
  final n = a.length;
  final m = b.length;
  if ((n - m).abs() > max) {
    return max + 1;
  }
  if (n == 0 || m == 0) {
    final d = n + m;
    return d > max ? max + 1 : d;
  }
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      if (ins < v) {
        v = ins;
      }
      final sub = prev[j - 1] + cost;
      if (sub < v) {
        v = sub;
      }
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final swap = prev2[j - 2] + 1;
        if (swap < v) {
          v = swap;
        }
      }
      cur[j] = v;
      if (v < rowMin) {
        rowMin = v;
      }
    }
    if (rowMin > max) {
      return max + 1;
    }
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  final d = prev[m];
  return d > max ? max + 1 : d;
}
