/// De-duplication of candidates (spec T24 §4.5).
library;

import 'package:stationgen/src/geo.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/names.dart';
import 'package:stationgen/src/prefixes.dart';

/// Merge radius per kind, metres.
const Map<StationKind, double> kMergeRadiusM = {
  StationKind.train: 500,
  StationKind.coach: 300,
  StationKind.bus: 300,
};

/// Near-duplicate distance (reported, not merged), metres.
const double kNearDuplicateM = 150;

/// A pair of kept stations of the same kind close to each other with a
/// different core name.
final class NearDuplicate {
  const new(this.a, this.b, this.distanceM);

  final Candidate a;
  final Candidate b;
  final double distanceM;
}

/// Result of [dedupe].
final class DedupeResult {
  const new(this.kept, this.nearDuplicates);

  /// Kept candidates in (kind, coreKey, rank) order; merged ids recorded in
  /// [Candidate.mergedIds].
  final List<Candidate> kept;
  final List<NearDuplicate> nearDuplicates;
}

int _compareRank(Candidate a, Candidate b) {
  final p = (a.primary ? 0 : 1).compareTo(b.primary ? 0 : 1);
  if (p != 0) {
    return p;
  }
  final t = a.typeRank.compareTo(b.typeRank);
  if (t != 0) {
    return t;
  }
  final o = a.osmId.compareTo(b.osmId);
  if (o != 0) {
    return o;
  }
  return a.id.compareTo(b.id);
}

double _dist(Candidate a, Candidate b) => distanceM(a.lat, a.lng, b.lat, b.lng);

/// Merges same-kind candidates with the same core name within the kind's
/// radius into the best ranked one. Input order does not matter.
DedupeResult dedupe(List<Candidate> candidates) {
  final keys = {for (final c in candidates) c: c.coreKey};
  final sorted = [...candidates]
    ..sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) {
        return k;
      }
      final c = keys[a]!.compareTo(keys[b]!);
      if (c != 0) {
        return c;
      }
      return _compareRank(a, b);
    });
  final kept = <Candidate>[];
  // Kept candidates by (kind, coreKey).
  final groups = <String, List<Candidate>>{};
  for (final c in sorted) {
    final group = groups.putIfAbsent('${c.kind.name}|${keys[c]}', () => []);
    Candidate? into;
    for (final k in group) {
      if (_dist(k, c) <= kMergeRadiusM[c.kind]!) {
        into = k;
        break;
      }
    }
    if (into == null) {
      group.add(c);
      kept.add(c);
      continue;
    }
    into.aliases = mergeAliasValues(into.name, into.aliases, [
      c.name,
      ...c.aliases,
    ]);
    into.mergedIds
      ..add(c.id)
      ..addAll(c.mergedIds);
  }
  return DedupeResult(kept, findNearDuplicates(kept));
}

/// Same-kind pairs within [kNearDuplicateM] whose core names differ, sorted
/// by the ids of the pair.
List<NearDuplicate> findNearDuplicates(List<Candidate> stations) {
  final byLat = [...stations]..sort((a, b) => a.lat.compareTo(b.lat));
  // 150 m is < 0.0014 degrees of latitude; 0.002 leaves margin.
  const latWindow = 0.002;
  final out = <NearDuplicate>[];
  for (var i = 0; i < byLat.length; i++) {
    final a = byLat[i];
    for (var j = i + 1; j < byLat.length; j++) {
      final b = byLat[j];
      if (b.lat - a.lat > latWindow) {
        break;
      }
      if (a.kind != b.kind || a.coreKey == b.coreKey) {
        continue;
      }
      final d = _dist(a, b);
      if (d <= kNearDuplicateM) {
        final (x, y) = a.id.compareTo(b.id) <= 0 ? (a, b) : (b, a);
        out.add(NearDuplicate(x, y, d));
      }
    }
  }
  out.sort((p, q) {
    final c = p.a.id.compareTo(q.a.id);
    return c != 0 ? c : p.b.id.compareTo(q.b.id);
  });
  return out;
}
