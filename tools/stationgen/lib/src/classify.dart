/// Classification of an OSM element into a station kind (spec T24 §4.2).
library;

import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/prefixes.dart';

/// Result of [classify]: either a [kind] or a [drop] reason.
final class Classification {
  const new kind(StationKind this.kind, {this.guessed = false}) : drop = null;

  const new drop(DropReason this.drop) : kind = null, guessed = false;

  final StationKind? kind;
  final DropReason? drop;

  /// The road kind fell back to `bus` without evidence from the name.
  final bool guessed;

  @override
  String toString() => kind != null
      ? 'Classification(${kind!.name}${guessed ? ', guessed' : ''})'
      : 'Classification(${drop!.label})';
}

const Set<String> _metroStationValues = {
  'subway',
  'light_rail',
  'monorail',
  'funicular',
  'miniature',
  'tram',
};

const Set<String> _lifecycleRailway = {
  'construction',
  'proposed',
  'disused',
  'abandoned',
};

const List<String> _busTokens = ['buyt', 'bus', 'brt'];

const List<List<String>> _busNamePrefixes = [
  ['diem', 'trung', 'chuyen'],
  ['diem', 'dau', 'cuoi'],
  ['tram', 'trung', 'chuyen'],
];

const List<List<String>> _coachNameRuns = [
  ['ben', 'xe'],
  ['xe', 'khach'],
];

/// Display name source: trimmed `name:vi` ?? `name`. Null when empty or
/// when it has no Latin letter or digit (e.g. only Cyrillic), since such a
/// name cannot be searched.
String? rawNameOf(Map<String, String> tags) {
  final v = (tags['name:vi'] ?? tags['name'])?.trim();
  return v == null || foldVi(v).isEmpty ? null : v;
}

/// Classifies [tags] (values compared case sensitively, as in OSM).
Classification classify(Map<String, String> tags) {
  final railway = tags['railway'];
  final pts = tags['public_transport'] == 'station';
  final isTrain =
      railway == 'station' ||
      railway == 'halt' ||
      (pts && tags['train'] == 'yes');
  final isRoad =
      tags['amenity'] == 'bus_station' || (pts && tags['bus'] == 'yes');
  // Roadside stops are out of scope (spec "KHÔNG làm"), even when a mapper
  // also tagged them amenity=bus_station.
  final roadStop =
      tags['highway'] == 'bus_stop' || tags['public_transport'] == 'platform';
  if ((!isTrain && !isRoad) || (!isTrain && roadStop)) {
    return const Classification.drop(DropReason.notStation);
  }
  if (tags['disused'] == 'yes' ||
      tags['abandoned'] == 'yes' ||
      tags.containsKey('construction') ||
      tags.containsKey('proposed') ||
      _lifecycleRailway.contains(railway)) {
    return const Classification.drop(DropReason.lifecycle);
  }
  final access = tags['access'];
  if (access == 'private' || access == 'no') {
    return const Classification.drop(DropReason.private);
  }
  final rawName = rawNameOf(tags);
  if (rawName == null) {
    return const Classification.drop(DropReason.noName);
  }
  if (isTrain) {
    if (_metroStationValues.contains(tags['station'])) {
      return const Classification.drop(DropReason.metro);
    }
    final light = [
      'subway',
      'light_rail',
      'monorail',
      'tram',
    ].any((k) => tags[k] == 'yes');
    if (light && tags['train'] != 'yes') {
      return const Classification.drop(DropReason.metro);
    }
    final net = foldVi('${tags['network'] ?? ''} ${tags['operator'] ?? ''}');
    if (net.contains('metro') || net.contains('duong sat do thi')) {
      return const Classification.drop(DropReason.metro);
    }
    return const Classification.kind(StationKind.train);
  }
  final n = foldTokens(rawName);
  if (_busTokens.any(n.contains) ||
      _busNamePrefixes.any((p) => startsWithTokens(n, p))) {
    return const Classification.kind(StationKind.bus);
  }
  if (_coachNameRuns.any((r) => containsTokenRun(n, r)) ||
      tags['coach'] == 'yes') {
    return const Classification.kind(StationKind.coach);
  }
  return const Classification.kind(StationKind.bus, guessed: true);
}
