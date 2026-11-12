/// Ranked offline station search (spec T24 §7.3, T23 §4). Pure Dart, no
/// Flutter.
///
/// Never log queries or results: a destination is location data of the
/// user (spec §8).
library;

import 'dart:typed_data';

import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';

/// Default maximum number of results.
const int kDefaultSearchLimit = 20;

/// Match tiers, best first.
///
/// The tier is the kind of string match. The order of results only depends
/// on the sort group and the score, and a score can be higher than the next
/// tier up in the T24 table: with a kind hint (T23 §4.2) a qualified match
/// ("Bến xe Bắc Vinh" for "bến xe vinh") scores 950 under [orderedTokens],
/// and a query equal to the province name scores 800 under
/// [provinceAssisted].
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

/// Fuzzy matches with more edits are dropped (T23 §4.2, review T24 #10: the
/// score would reach 0 or below).
const int _maxFuzzyErrors = 3;

/// Base score of a station of the hinted kind whose whole province name is
/// the query (T23 §4.2).
const int _provinceNameScore = 800;

final class _Key {
  const new(
    this.tokens,
    this.text,
    this.compact,
    this.qualifiedText,
    this.qualifiedCompact, {
    required this.alias,
  });

  final List<String> tokens;
  final String text;

  /// [tokens] joined without spaces ("hanoi").
  final String compact;

  /// [tokens] after [stripLeadingQualifiers], joined with / without spaces;
  /// null when no qualifier was removed.
  final String? qualifiedText;
  final String? qualifiedCompact;
  final bool alias;
}

final class _Entry {
  const new(
    this.station,
    this.keys,
    this.provinceTokens, {
    required this.nameKeyLength,
    required this.provinceText,
    required this.provinceCompact,
    required this.provinceCoreText,
    required this.provinceCoreCompact,
    required this.charMask,
  });

  final Station station;
  final List<_Key> keys;
  final List<String> provinceTokens;

  /// Length of the display name key (0 when the name has no tokens).
  final int nameKeyLength;

  /// Province tokens joined with / without spaces: full, and without a
  /// leading "tp" / "thanh pho" / "tinh".
  final String provinceText;
  final String provinceCompact;
  final String provinceCoreText;
  final String provinceCoreCompact;

  /// [_charBit] of the first letter of every key and province token.
  final int charMask;
}

/// Bit of a folded first letter: a–z → 0–25, 0–9 → 26–35.
int _charBit(int codeUnit) =>
    codeUnit >= 0x61 ? 1 << (codeUnit - 0x61) : 1 << (26 + codeUnit - 0x30);

/// Whether a words-typed-together tier (T23 §4.2 steps 2, 3, 5 and the
/// compact province name) could match [e] for the compact query [qc].
bool _compactPossible(_Entry e, String qc) {
  if (qc.length < 4) {
    return false;
  }
  if (qc == e.provinceCompact || qc == e.provinceCoreCompact) {
    return true;
  }
  for (final k in e.keys) {
    if (k.compact.startsWith(qc) || k.qualifiedCompact == qc) {
      return true;
    }
  }
  return false;
}

/// A candidate while searching: the match, the length of its key and its
/// sort group (0 = strong match of the hinted kind, 1 = everything else).
typedef _Found = (StationMatch match, int keyLength, int group);

/// In-memory index over the dataset; linear scan with precomputed keys.
///
/// T24.3 §6.2: with `bucketByFirstChar` the scan only visits the entries
/// with a key or province token starting with the first letter of the first
/// query token. That is an exact superset of every tier but
/// [StationMatchTier.substring]: the exact, prefix, token and province tiers
/// need every query token to prefix a key or province token, fuzzy needs
/// the same first letter (T24 §7.3), and a words-typed-together match
/// ("bachkhoa") starts with the first letter of a key token. It is tighter
/// than the union of the buckets of every query token (spec §6.2) with the
/// same results. Inside the bucket an entry is skipped when the first letter
/// of another query token is not among the first letters of its tokens and
/// no words-typed-together match is possible. Without [substringTier] that
/// tier is skipped (match inside a word); buckets are only used then.
/// Ranks, scores and order are otherwise unchanged.
final class StationSearchIndex {
  /// Precomputes the core tokens of names and aliases and the province
  /// tokens. The defaults (full scan, substring tier on) are the T24
  /// behaviour of the station dataset.
  factory(
    List<Station> stations, {
    bool bucketByFirstChar = false,
    bool substringTier = true,
  }) {
    final entries = <_Entry>[];
    for (final s in stations) {
      final keys = <_Key>[];
      var nameKeyLength = 0;
      for (final (i, text) in [s.name, ...s.aliases].indexed) {
        final tokens = stationCoreTokens(text);
        if (tokens.isEmpty) {
          continue;
        }
        final qualified = stripLeadingQualifiers(tokens);
        final key = _Key(
          List.unmodifiable(tokens),
          tokens.join(' '),
          tokens.join(),
          qualified?.join(' '),
          qualified?.join(),
          alias: i > 0,
        );
        if (i == 0) {
          nameKeyLength = key.text.length;
        }
        keys.add(key);
      }
      final province = foldTokens(s.province);
      final provinceCore = provinceCoreTokens(s.province);
      entries.add(
        _Entry(
          s,
          List.unmodifiable(keys),
          province,
          nameKeyLength: nameKeyLength,
          provinceText: province.join(' '),
          provinceCompact: province.join(),
          provinceCoreText: provinceCore.join(' '),
          provinceCoreCompact: provinceCore.join(),
          charMask: _maskOf([for (final k in keys) ...k.tokens, ...province]),
        ),
      );
    }
    return StationSearchIndex._(
      List.unmodifiable(entries),
      bucketByFirstChar && !substringTier ? _bucketsOf(entries) : null,
      substringTier: substringTier,
    );
  }

  new _(this._entries, this._buckets, {required this.substringTier});

  final List<_Entry> _entries;

  /// Entry indices (ascending) per first code unit of a key or province
  /// token; null for a full scan.
  final Map<int, Uint32List>? _buckets;

  /// Whether the substring tier (query inside a word) is searched.
  final bool substringTier;

  static int _maskOf(List<String> tokens) {
    var m = 0;
    for (final t in tokens) {
      m |= _charBit(t.codeUnitAt(0));
    }
    return m;
  }

  static Map<int, Uint32List> _bucketsOf(List<_Entry> entries) {
    final lists = <int, List<int>>{};
    for (final (i, e) in entries.indexed) {
      final chars = <int>{
        for (final k in e.keys)
          for (final t in k.tokens) t.codeUnitAt(0),
        for (final t in e.provinceTokens) t.codeUnitAt(0),
      };
      for (final c in chars) {
        (lists[c] ??= []).add(i);
      }
    }
    return {
      for (final MapEntry(:key, :value) in lists.entries)
        key: Uint32List.fromList(value),
    };
  }

  /// Entry indices to score for [tokens] (bucket of the first letter of
  /// the first token); null = every entry.
  Uint32List? _candidates(List<String> tokens) =>
      _buckets == null ? null : _buckets[tokens.first.codeUnitAt(0)] ?? _none;

  static final Uint32List _none = Uint32List(0);

  /// Number of indexed stations.
  int get length => _entries.length;

  /// Ranked matches for [query], at most [limit]. Empty query → `[]`.
  ///
  /// [kindHint] applies when the query has no kind prefix of its own (the
  /// filter chips of screen 2); a prefix in the query wins. With a hint,
  /// strong matches of that kind come before every other result (T23 §4.2).
  List<StationMatch> search(
    String query, {
    int limit = kDefaultSearchLimit,
    StationKind? kindHint,
  }) {
    final q = parseStationQuery(query);
    if (q.tokens.isEmpty || limit <= 0) {
      return const [];
    }
    final hint = q.kindHint ?? kindHint;
    final qs = q.tokens.join(' ');
    final qc = q.tokens.join();
    final queryMask = _maskOf(q.tokens);
    final found = <_Found>[];
    final candidates = _candidates(q.tokens);
    final n = candidates?.length ?? _entries.length;
    for (var i = 0; i < n; i++) {
      final e = _entries[candidates == null ? i : candidates[i]];
      // Bucketed index: every tier left needs each query token's first
      // letter among the entry's, except the compact ones.
      if (candidates != null &&
          queryMask & ~e.charMask != 0 &&
          !_compactPossible(e, qc)) {
        continue;
      }
      final hinted = hint != null && hint == e.station.kind;
      final qualifiedAllowed = hinted && e.station.kind != StationKind.train;
      StationMatch? best;
      var bestLen = 0;
      for (final k in e.keys) {
        final m = _matchKey(
          k,
          q.tokens,
          qs,
          qc,
          e.provinceTokens,
          qualifiedAllowed: qualifiedAllowed,
          substringTier: substringTier,
        );
        if (m == null) {
          continue;
        }
        final (tier, base) = m;
        final score =
            base -
            (k.alias ? _aliasPenalty : 0) +
            (hinted ? _kindHintBonus : 0);
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
      if (hinted && _isProvinceName(e, qs, qc)) {
        const score = _provinceNameScore + _kindHintBonus;
        if (best == null || score > best.score) {
          best = StationMatch(
            station: e.station,
            score: score,
            tier: StationMatchTier.provinceAssisted,
            viaAlias: false,
          );
          bestLen = e.nameKeyLength;
        }
      }
      if (best != null) {
        final strong =
            best.tier != StationMatchTier.substring &&
            best.tier != StationMatchTier.fuzzy;
        found.add((best, bestLen, hinted && strong ? 0 : 1));
      }
    }
    return [for (final (m, _, _) in _best(found, limit)) m];
  }
}

/// The first [limit] of [found] in [_compareFound] order, the same as
/// sorting everything and taking [limit]. With thousands of matches (a
/// short query or a province name over the bus stops, T24.3) only the
/// best [limit] are kept in order.
List<_Found> _best(List<_Found> found, int limit) {
  if (found.length <= limit * 4) {
    found.sort(_compareFound);
    return found.length <= limit ? found : found.sublist(0, limit);
  }
  final best = <_Found>[];
  for (final f in found) {
    if (best.length == limit && _compareFound(f, best.last) >= 0) {
      continue;
    }
    // Binary search for the first element after f.
    var lo = 0;
    var hi = best.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_compareFound(best[mid], f) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    best.insert(lo, f);
    if (best.length > limit) {
      best.removeLast();
    }
  }
  return best;
}

/// The whole query is the province name ("bến xe huế"): full or without a
/// leading "tp"/"tỉnh", with or without spaces. No prefix match.
bool _isProvinceName(_Entry e, String qs, String qc) =>
    qs == e.provinceCoreText ||
    qs == e.provinceText ||
    (qc.length >= 4 &&
        (qc == e.provinceCoreCompact || qc == e.provinceCompact));

int _compareFound(_Found a, _Found b) {
  final (ma, la, ga) = a;
  final (mb, lb, gb) = b;
  var c = ga.compareTo(gb);
  if (c != 0) {
    return c;
  }
  c = mb.score.compareTo(ma.score);
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

/// First tier reached by key [k] (T23 §4.2, steps 1–10).
(StationMatchTier, int)? _matchKey(
  _Key k,
  List<String> q,
  String qs,
  String qc,
  List<String> province, {
  required bool qualifiedAllowed,
  required bool substringTier,
}) {
  if (k.text == qs) {
    return (StationMatchTier.exact, 1000);
  }
  // Words typed together: "hanoi", "sapa".
  if (qc.length >= 4 && k.compact == qc) {
    return (StationMatchTier.exact, 990);
  }
  // "bến xe vinh" → "Bến xe Bắc Vinh" (coach/bus with the hint only).
  if (qualifiedAllowed &&
      k.qualifiedText != null &&
      qc.length >= 3 &&
      (k.qualifiedText == qs || (qc.length >= 4 && k.qualifiedCompact == qc))) {
    return (StationMatchTier.orderedTokens, 950);
  }
  if (k.text.startsWith(qs)) {
    return (StationMatchTier.prefix, 900);
  }
  if (qc.length >= 4 && k.compact.startsWith(qc)) {
    return (StationMatchTier.prefix, 890);
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
  if (substringTier && qs.length >= 3 && k.text.contains(qs)) {
    return (StationMatchTier.substring, 300);
  }
  final errors = _fuzzyErrors(k.tokens, q);
  if (errors != null && errors >= 1 && errors <= _maxFuzzyErrors) {
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
