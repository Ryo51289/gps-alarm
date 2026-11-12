/// Classification of an OSM element as a bus stop and normalisation of its
/// `route_ref` (spec T24.3 §4, D6, D7).
library;

import 'package:stationgen/src/classify.dart';
import 'package:stationgen/src/model_bus.dart';
import 'package:stationgen/src/names.dart';

/// Result of [classifyBus]: either a stop [name] or a [drop] reason.
final class BusClassification {
  const new stop(String this.name) : drop = null;

  const new drop(BusDropReason this.drop) : name = null;

  /// Display name (`name:vi ?? name`, spaces collapsed).
  final String? name;
  final BusDropReason? drop;

  @override
  String toString() => name != null
      ? 'BusClassification(stop "$name")'
      : 'BusClassification(${drop!.label})';
}

/// Classifies [tags] (values compared case sensitively, as in OSM).
BusClassification classifyBus(Map<String, String> tags) {
  final isStop =
      tags['highway'] == 'bus_stop' ||
      (tags['public_transport'] == 'platform' && tags['bus'] == 'yes');
  if (!isStop) {
    return const BusClassification.drop(BusDropReason.notStop);
  }
  if (tags['disused'] == 'yes' ||
      tags['abandoned'] == 'yes' ||
      tags.containsKey('construction') ||
      tags.containsKey('proposed')) {
    return const BusClassification.drop(BusDropReason.lifecycle);
  }
  final access = tags['access'];
  if (access == 'private' || access == 'no' || tags['bus'] == 'no') {
    return const BusClassification.drop(BusDropReason.private);
  }
  final rawName = rawNameOf(tags);
  if (rawName == null) {
    return const BusClassification.drop(BusDropReason.noName);
  }
  return BusClassification.stop(collapseSpaces(rawName));
}

/// At most this many routes per stop (D7).
const int kMaxRoutes = 6;

/// At most this many characters per route (D7).
const int kMaxRouteChars = 8;

/// Outcome of [normalizeRouteRef].
enum RouteRefStatus {
  /// No `route_ref` or nothing left after trimming.
  none,

  /// Kept as is (after trimming and de-duplication).
  ok,

  /// More than [kMaxRoutes] routes; only the first ones kept.
  truncated,

  /// A route is longer than [kMaxRouteChars]; the whole field is dropped.
  invalid,
}

/// Normalised routes of a stop and how they were obtained.
typedef RouteRefResult = ({List<String> routes, RouteRefStatus status});

/// Splits `route_ref` on `;`, trims, drops empty values and duplicates (first
/// occurrence wins), drops the whole field when a route has more than
/// [kMaxRouteChars] characters, and keeps at most [kMaxRoutes] routes.
RouteRefResult normalizeRouteRef(String? routeRef) {
  if (routeRef == null) {
    return (routes: const <String>[], status: RouteRefStatus.none);
  }
  final out = <String>[];
  for (final part in routeRef.split(';')) {
    final r = collapseSpaces(part);
    if (r.isEmpty || out.contains(r)) {
      continue;
    }
    if (r.runes.length > kMaxRouteChars) {
      return (routes: const <String>[], status: RouteRefStatus.invalid);
    }
    out.add(r);
  }
  if (out.isEmpty) {
    return (routes: const <String>[], status: RouteRefStatus.none);
  }
  if (out.length > kMaxRoutes) {
    return (
      routes: out.sublist(0, kMaxRoutes),
      status: RouteRefStatus.truncated,
    );
  }
  return (routes: out, status: RouteRefStatus.ok);
}

/// True when [routes] obeys D7 (used by acceptance B2).
bool validRoutes(List<String> routes) {
  if (routes.length > kMaxRoutes || routes.toSet().length != routes.length) {
    return false;
  }
  return routes.every(
    (r) =>
        r.isNotEmpty &&
        r.runes.length <= kMaxRouteChars &&
        !r.contains(';') &&
        r == collapseSpaces(r),
  );
}

/// Union of [a] and [b] in order (a first), at most [kMaxRoutes].
List<String> unionRoutes(List<String> a, List<String> b) {
  final out = [...a];
  for (final r in b) {
    if (out.length >= kMaxRoutes) {
      break;
    }
    if (!out.contains(r)) {
      out.add(r);
    }
  }
  return out;
}
