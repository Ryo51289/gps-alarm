/// Acceptance thresholds A1–A5 and the must-have list (spec T24 §4.7, §4.8).
library;

import 'dart:convert';

import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/prefixes.dart';
import 'package:stationgen/src/provinces.dart';

const int kMinTrainStations = 150;
const int kMaxStations = 5000;

/// 800 KB, counted as 800 000 bytes (the stricter reading).
const int kMaxFileBytes = 800000;

/// Entries that must never be waived (spec §4.8), as `kind:match`.
const Set<String> kNotWaivable = {'train:dong hoi', 'coach:my dinh'};

/// One `must_have.json` entry.
final class MustHave {
  const new({
    required this.kind,
    required this.match,
    required this.province,
    this.waived,
  });

  final StationKind kind;

  /// Folded tokens to find as a contiguous run in a core name.
  final String match;
  final String province;

  /// Why the entry is exempt from A3 (not on OSM and no allowed source,
  /// spec §4.8); null for a normal entry. Shown in the report.
  final String? waived;

  List<String> get matchTokens => foldTokens(match);

  @override
  String toString() => '${kind.name} "$match" ($province)';
}

/// Parses `must_have.json` (`[{kind, match, province}]`).
List<MustHave> parseMustHave(String source, ProvinceTable provinces) {
  Never bad(String m) => throw StationgenException(kErrMustHaveInvalid, m);
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException catch (e) {
    bad('must_have.json is not valid JSON: ${e.message}');
  }
  if (json is! List<Object?>) {
    bad('must_have.json must be an array');
  }
  final out = <MustHave>[];
  for (final (i, row) in json.indexed) {
    if (row is! Map<String, Object?>) {
      bad('must_have.json[$i] is not an object');
    }
    final kindRaw = row['kind'];
    final kind = kindRaw is String ? StationKind.tryParse(kindRaw) : null;
    final match = row['match'];
    final province = row['province'];
    final waived = row['waived'];
    if (kind == null ||
        match is! String ||
        foldTokens(match).isEmpty ||
        province is! String ||
        !provinces.isProvince(province)) {
      bad('must_have.json[$i] needs kind, match and one of the 34 provinces');
    }
    if (waived != null && (waived is! String || waived.trim().isEmpty)) {
      bad('must_have.json[$i]: "waived" must be a non-empty reason');
    }
    if (waived != null &&
        kNotWaivable.contains('${kind.name}:${foldVi(match)}')) {
      bad('must_have.json[$i]: ${kind.name} "$match" cannot be waived');
    }
    out.add(
      MustHave(
        kind: kind,
        match: match,
        province: province,
        waived: waived as String?,
      ),
    );
  }
  return out;
}

/// First station (in the given order) satisfying [m], or null.
Candidate? findMustHave(MustHave m, List<Candidate> stations) {
  final needle = m.matchTokens;
  for (final s in stations) {
    if (s.kind != m.kind || s.province != m.province) {
      continue;
    }
    if (containsTokenRun(s.core, needle) ||
        s.aliases.any((a) => containsTokenRun(coreTokens(a), needle))) {
      return s;
    }
  }
  return null;
}

/// One failed threshold.
final class AcceptanceFailure {
  const new(this.code, this.message, [this.items = const []]);

  /// `A1` … `A5`.
  final String code;
  final String message;
  final List<String> items;

  @override
  String toString() => items.isEmpty
      ? '$code: $message'
      : '$code: $message: ${items.join('; ')}';
}

/// Checks A1–A5 on the final, sorted [stations] and the encoded file size.
List<AcceptanceFailure> checkAcceptance({
  required List<Candidate> stations,
  required int fileBytes,
  required List<MustHave> mustHave,
  required ProvinceTable provinces,
}) {
  final failures = <AcceptanceFailure>[];
  final train = stations.where((s) => s.kind == StationKind.train).length;
  if (train < kMinTrainStations) {
    failures.add(
      AcceptanceFailure('A1', 'train stations $train < $kMinTrainStations'),
    );
  }
  final withCoach = {
    for (final s in stations)
      if (s.kind == StationKind.coach) s.province,
  };
  final noCoach = [
    for (final p in provinces.names)
      if (!withCoach.contains(p)) p,
  ];
  if (noCoach.isNotEmpty) {
    failures.add(
      AcceptanceFailure('A2', 'provinces without a coach station', noCoach),
    );
  }
  final missing = [
    for (final m in mustHave)
      if (m.waived == null && findMustHave(m, stations) == null) m.toString(),
  ];
  if (missing.isNotEmpty) {
    failures.add(AcceptanceFailure('A3', 'must-have entries missing', missing));
  }
  final a4 = <String>[];
  final ids = <String>{};
  for (final s in stations) {
    if (!ids.add(s.id)) {
      a4.add('duplicate id ${s.id}');
    }
    if (s.name.trim().isEmpty || foldVi(s.name).isEmpty) {
      a4.add('${s.id}: empty name');
    }
    if (!insideVnBbox(s.lat, s.lng)) {
      a4.add('${s.id}: coordinates outside Viet Nam');
    }
    if (!provinces.isProvince(s.province)) {
      a4.add('${s.id}: unknown province "${s.province}"');
    }
  }
  if (a4.isNotEmpty) {
    failures.add(AcceptanceFailure('A4', 'invalid stations', a4));
  }
  if (stations.length > kMaxStations) {
    failures.add(
      AcceptanceFailure('A5', 'stations ${stations.length} > $kMaxStations'),
    );
  }
  if (fileBytes > kMaxFileBytes) {
    failures.add(
      AcceptanceFailure('A5', 'stations.json $fileBytes B > $kMaxFileBytes B'),
    );
  }
  return failures;
}
