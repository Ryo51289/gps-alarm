/// Merging the two sides of a road into one bus stop, and removal of stops
/// that repeat a bus/coach station (spec T24.3 §4, D5).
library;

import 'package:stationgen/src/classify_bus.dart';
import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/geo.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/model_bus.dart';
import 'package:stationgen/src/prefixes.dart';

/// Two candidates with the same folded name within this distance of the
/// cluster seed are one stop, metres (D5).
const double kBusMergeRadiusM = 150;

/// Same-name stops kept apart but closer than this are reported, metres.
const double kBusNearSameNameM = 300;

/// A stop within this distance of a bus/coach station with the same core
/// name is a duplicate of the station, metres (spec §4 `coversStation`).
const double kDupOfStationM = 100;

/// Merge key: the folded name (no prefix removal).
String busMergeKey(String name) => foldVi(name);

/// The bus or coach station of [stations] that [c] duplicates (same core
/// key, at most [kDupOfStationM] away), or null. Train stations never count.
Candidate? coveringStation(BusCandidate c, List<Candidate> stations) {
  final key = coreTokens(c.name).join(' ');
  for (final s in stations) {
    if (s.kind == StationKind.train || s.coreKey != key) {
      continue;
    }
    if (distanceM(c.lat, c.lng, s.lat, s.lng) <= kDupOfStationM) {
      return s;
    }
  }
  return null;
}

int _compareCandidates(BusCandidate a, BusCandidate b) {
  final p = a.province.compareTo(b.province);
  if (p != 0) {
    return p;
  }
  final k = busMergeKey(a.name).compareTo(busMergeKey(b.name));
  if (k != 0) {
    return k;
  }
  final t = a.typeRank.compareTo(b.typeRank);
  if (t != 0) {
    return t;
  }
  final o = a.osmId.compareTo(b.osmId);
  return o != 0 ? o : a.id.compareTo(b.id);
}

/// Rounds to 5 decimals (the output precision).
double round5(double v) => double.parse(v.toStringAsFixed(5));

/// Merges candidates with the same province and folded name within
/// [kBusMergeRadiusM] of the cluster seed (not chained). The stop takes the
/// seed's id and name, the mean coordinates of its members (rounded to 5
/// decimals) and the union of their routes. Input order does not matter.
List<BusStop> mergeSides(List<BusCandidate> candidates) {
  final sorted = [...candidates]..sort(_compareCandidates);
  // Clusters by (province, key); each is a list of members, seed first.
  final groups = <String, List<List<BusCandidate>>>{};
  final clusters = <List<BusCandidate>>[];
  for (final c in sorted) {
    final group = groups.putIfAbsent(
      '${c.province}|${busMergeKey(c.name)}',
      () => [],
    );
    List<BusCandidate>? into;
    for (final k in group) {
      final seed = k.first;
      if (distanceM(seed.lat, seed.lng, c.lat, c.lng) <= kBusMergeRadiusM) {
        into = k;
        break;
      }
    }
    if (into == null) {
      final k = [c];
      group.add(k);
      clusters.add(k);
    } else {
      into.add(c);
    }
  }
  return [for (final k in clusters) _stopOf(k)];
}

BusStop _stopOf(List<BusCandidate> members) {
  final seed = members.first;
  var lat = 0.0;
  var lng = 0.0;
  var routes = const <String>[];
  for (final m in members) {
    lat += m.lat;
    lng += m.lng;
    routes = unionRoutes(routes, m.routes);
  }
  return BusStop(
    id: seed.id,
    name: seed.name,
    province: seed.province,
    lat: round5(lat / members.length),
    lng: round5(lng / members.length),
    routes: routes,
    members: List.unmodifiable(members),
  );
}

/// Two kept stops with the same province and folded name.
final class NearSameName {
  const new(this.a, this.b, this.distanceM);

  final BusStop a;
  final BusStop b;
  final double distanceM;
}

/// Same-name pairs more than [kBusMergeRadiusM] but at most
/// [kBusNearSameNameM] apart, sorted by the ids of the pair.
List<NearSameName> findNearSameName(List<BusStop> stops) {
  final groups = <String, List<BusStop>>{};
  for (final s in stops) {
    (groups['${s.province}|${busMergeKey(s.name)}'] ??= []).add(s);
  }
  final out = <NearSameName>[];
  for (final g in groups.values) {
    for (var i = 0; i < g.length; i++) {
      for (var j = i + 1; j < g.length; j++) {
        final d = distanceM(g[i].lat, g[i].lng, g[j].lat, g[j].lng);
        if (d > kBusMergeRadiusM && d <= kBusNearSameNameM) {
          final (x, y) = g[i].id.compareTo(g[j].id) <= 0
              ? (g[i], g[j])
              : (g[j], g[i]);
          out.add(NearSameName(x, y, d));
        }
      }
    }
  }
  out.sort((p, q) {
    final c = p.a.id.compareTo(q.a.id);
    return c != 0 ? c : p.b.id.compareTo(q.b.id);
  });
  return out;
}
