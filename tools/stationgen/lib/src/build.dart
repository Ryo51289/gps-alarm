/// `stationgen build`: snapshot → stations.json + BUILD_REPORT.md (spec T24
/// §4.1). Pure: no IO besides [BuildInputs.read].
library;

import 'dart:convert';
import 'dart:io';

import 'package:stationgen/src/acceptance.dart';
import 'package:stationgen/src/acceptance_bus.dart';
import 'package:stationgen/src/classify.dart';
import 'package:stationgen/src/classify_bus.dart';
import 'package:stationgen/src/dedupe.dart';
import 'package:stationgen/src/geo.dart';
import 'package:stationgen/src/merge_bus.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/model_bus.dart';
import 'package:stationgen/src/names.dart';
import 'package:stationgen/src/overrides.dart';
import 'package:stationgen/src/prefixes.dart';
import 'package:stationgen/src/provinces.dart';
import 'package:stationgen/src/raw.dart';
import 'package:stationgen/src/report.dart';
import 'package:stationgen/src/report_bus.dart';
import 'package:stationgen/src/writer.dart';
import 'package:stationgen/src/writer_bus.dart';

/// Text of every input file of a build.
final class BuildInputs {
  const new({
    required this.query,
    required this.fetchMeta,
    required this.raw,
    required this.provinces,
    required this.overrides,
    required this.mustHave,
  });

  /// Reads the inputs from the data directory (`data/stations`).
  factory read(Directory data) {
    String text(String rel) {
      final f = File('${data.path}/$rel');
      if (!f.existsSync()) {
        throw StationgenException(kErrInputMissing, '${f.path} not found');
      }
      try {
        return utf8.decode(f.readAsBytesSync());
      } on FormatException {
        throw StationgenException(kErrInputMissing, '$rel is not UTF-8');
      }
    }

    return BuildInputs(
      query: text('query.overpassql'),
      fetchMeta: text('raw/fetch-meta.json'),
      raw: text('raw/overpass.json'),
      provinces: text('provinces.json'),
      overrides: text('overrides.json'),
      mustHave: text('must_have.json'),
    );
  }

  final String query;
  final String fetchMeta;
  final String raw;
  final String provinces;
  final String overrides;
  final String mustHave;
}

/// Output of [buildDataset].
final class BuildResult {
  const new({
    required this.stationsJson,
    required this.report,
    required this.stations,
    required this.failures,
    required this.droppedCount,
  });

  final String stationsJson;
  final String report;

  /// Final stations in output order.
  final List<Candidate> stations;
  final List<AcceptanceFailure> failures;
  final int droppedCount;

  bool get accepted => failures.isEmpty;
}

/// Text of every input file of the bus stop build (spec T24.3 §2).
final class BusBuildInputs {
  const new({
    required this.query,
    required this.fetchMeta,
    required this.raw,
    required this.provinces,
    required this.overrides,
    required this.mustHave,
  });

  /// Reads the inputs from the data directory (`data/stations`).
  factory read(Directory data) {
    String text(String rel) {
      final f = File('${data.path}/$rel');
      if (!f.existsSync()) {
        throw StationgenException(kErrInputMissing, '${f.path} not found');
      }
      try {
        return utf8.decode(f.readAsBytesSync());
      } on FormatException {
        throw StationgenException(kErrInputMissing, '$rel is not UTF-8');
      }
    }

    return BusBuildInputs(
      query: text('bus_query.overpassql'),
      fetchMeta: text('raw/bus_fetch-meta.json'),
      raw: text('raw/bus_overpass.json'),
      provinces: text('provinces.json'),
      overrides: text('bus_overrides.json'),
      mustHave: text('bus_must_have.json'),
    );
  }

  final String query;
  final String fetchMeta;
  final String raw;
  final String provinces;
  final String overrides;
  final String mustHave;
}

/// Output of [buildBusDataset].
final class BusBuildResult {
  const new({
    required this.busStopsJson,
    required this.report,
    required this.stops,
    required this.provinces,
    required this.failures,
    required this.droppedCount,
  });

  final String busStopsJson;
  final String report;

  /// Final stops in output order.
  final List<BusStop> stops;

  /// Provinces of the output, in file order.
  final List<String> provinces;
  final List<AcceptanceFailure> failures;
  final int droppedCount;

  bool get accepted => failures.isEmpty;
}

/// Parses `bus_overrides.json`: the format of `overrides.json` (T24 §4.6),
/// without `kind` changes and aliases (bus stops have neither); `add`
/// entries must say `"kind": "bus"`.
Overrides parseBusOverrides(String source, ProvinceTable provinces) {
  final ov = Overrides.parse(source, provinces);
  Never bad(String m) => throw StationgenException(kErrOverrideInvalid, m);
  for (final p in ov.patch) {
    if (p.kind != null || p.aliasesAdd.isNotEmpty) {
      bad(
        'bus_overrides.json patch ${p.osm}: "kind" and "aliasesAdd" are '
        'not allowed for bus stops',
      );
    }
  }
  for (final a in ov.add) {
    if (a.kind != StationKind.bus || a.aliases.isNotEmpty) {
      bad(
        'bus_overrides.json add ${a.id}: "kind" must be "bus" and '
        '"aliases" is not allowed',
      );
    }
  }
  return ov;
}

/// Builds the bus stop dataset (spec T24.3 §4). [stations] are the final
/// stations of [buildDataset] (stops repeating a bus/coach station are
/// dropped). Throws [StationgenException] on invalid input.
BusBuildResult buildBusDataset(
  BusBuildInputs inputs,
  List<Candidate> stations,
) {
  final meta = parseFetchMeta(inputs.fetchMeta);
  if (meta.query != normalizeLf(inputs.query)) {
    throw const StationgenException(
      kErrQueryChanged,
      'bus_query.overpassql differs from the query of the snapshot; run '
      'fetch --dataset bus',
    );
  }
  final snap = parseOverpass(inputs.raw);
  if (snap.osmBase != meta.osmBase) {
    throw const StationgenException(
      kErrRawInvalid,
      'bus_fetch-meta.json osmBase does not match raw/bus_overpass.json',
    );
  }
  final provinces = ProvinceTable.parse(inputs.provinces);
  final ov = parseBusOverrides(inputs.overrides, provinces);
  final mustHave = parseBusMustHave(inputs.mustHave, provinces);

  final known = {for (final e in snap.elements) e.ref};
  final stale = [
    for (final r in ov.osmRefs)
      if (!known.contains(r)) r,
  ];
  if (stale.isNotEmpty) {
    throw StationgenException(
      kErrStaleOverride,
      'bus overrides refer to elements not in the snapshot: '
      '${stale.join(', ')}',
    );
  }

  final groupsOf = <String, List<AreaGroup>>{};
  final areas = <(String, String?, int)>[];
  final required = <String>{};
  for (final g in snap.groups) {
    for (final r in g.refs) {
      (groupsOf[r] ??= []).add(g);
    }
    final p = provinces.resolve(g.displayName);
    areas.add((g.displayName, p, g.refs.length));
    if (p != null) {
      required.add(p);
    }
  }

  final dropped = <BusDropped>[];
  final candidates = <BusCandidate>[];
  final ambiguities = <ProvinceAmbiguity>[];
  final applied = <String>[];
  final unresolved = <String>[];
  final truncated = <RouteRefIssue>[];
  final invalid = <RouteRefIssue>[];

  for (final e in snap.elements) {
    final ref = e.ref;
    final rawName = rawNameOf(e.tags);
    final drop = ov.dropFor(ref);
    if (drop != null) {
      dropped.add(BusDropped(ref, rawName, BusDropReason.overrideDrop));
      applied.add('drop `$ref` ($rawName): ${drop.reason} [${drop.source}]');
      continue;
    }
    final patch = ov.patchFor(ref);
    var tags = e.tags;
    var cls = classifyBus(tags);
    if (cls.drop == BusDropReason.noName && patch?.name != null) {
      tags = {...tags, 'name:vi': patch!.name!};
      cls = classifyBus(tags);
    }
    var reason = cls.drop;
    if (reason == null && (e.lat == null || e.lon == null)) {
      reason = BusDropReason.noGeometry;
    }
    if (reason == null && !insideVnBbox(e.lat!, e.lon!)) {
      reason = BusDropReason.outsideBbox;
    }
    if (reason != null) {
      if (patch != null) {
        throw StationgenException(
          kErrOverrideInvalid,
          'bus patch for $ref, but the element is dropped as '
          '${reason.label}; a patch cannot bring it back (use "add")',
        );
      }
      dropped.add(BusDropped(ref, rawName, reason));
      continue;
    }
    final resolved = <String>{
      for (final g in groupsOf[ref] ?? const <AreaGroup>[])
        ?provinces.resolve(g.displayName),
    }.toList()..sort((a, b) => provinceKey(a).compareTo(provinceKey(b)));
    final routeRef = e.tags['route_ref'];
    final routes = normalizeRouteRef(routeRef);
    switch (routes.status) {
      case RouteRefStatus.truncated:
        truncated.add((ref, routeRef!));
      case RouteRefStatus.invalid:
        invalid.add((ref, routeRef!));
      case RouteRefStatus.none:
      case RouteRefStatus.ok:
        break;
    }
    final c = BusCandidate(
      id: ref,
      name: cls.name!,
      province: resolved.isEmpty ? '' : resolved.first,
      lat: e.lat!,
      lng: e.lon!,
      routes: routes.routes,
      typeRank: e.type.index,
      osmId: e.id,
    );
    if (patch != null) {
      c
        ..name = patch.name ?? c.name
        ..province = patch.province ?? c.province
        ..lat = patch.lat ?? c.lat
        ..lng = patch.lng ?? c.lng;
      applied.add('patch `$ref` ($rawName): ${patch.reason} [${patch.source}]');
    }
    if (patch?.province == null) {
      if (resolved.isEmpty) {
        unresolved.add(ref);
      } else if (resolved.length > 1) {
        ambiguities.add(ProvinceAmbiguity(ref, c.name, resolved, c.province));
      }
    }
    candidates.add(c);
  }
  for (final a in ov.add) {
    candidates.add(
      BusCandidate(
        id: a.id,
        name: collapseSpaces(a.name),
        province: a.province,
        lat: a.lat,
        lng: a.lng,
        routes: const [],
        typeRank: 3,
        osmId: 0,
      ),
    );
    applied.add('add `${a.id}` (${a.name}): ${a.reason} [${a.source}]');
  }
  if (unresolved.isNotEmpty) {
    throw StationgenException(
      kErrProvinceUnresolved,
      'no province for bus stops: ${unresolved.join(', ')} (fix with a '
      'patch "province")',
    );
  }

  final dups = <DupOfStation>[];
  final kept = <BusCandidate>[];
  for (final c in candidates) {
    final s = coveringStation(c, stations);
    if (s == null) {
      kept.add(c);
      continue;
    }
    dups.add((c, s, distanceM(c.lat, c.lng, s.lat, s.lng)));
    dropped.add(BusDropped(c.id, c.name, BusDropReason.dupOfStation));
  }

  final merged = mergeSides(kept);
  final outProvinces = busProvinces(merged, provinces.names);
  final stops = sortBusStops(merged, outProvinces);
  final json = encodeBusStopsJson(
    osmBase: snap.osmBase,
    stops: stops,
    provinceOrder: provinces.names,
  );
  final fileBytes = utf8.encode(json).length;
  final requiredProvinces = [
    for (final p in provinces.names)
      if (required.contains(p)) p,
  ];
  final failures = checkBusAcceptance(
    stops: stops,
    fileBytes: fileBytes,
    mustHave: mustHave,
    provinces: provinces,
    requiredProvinces: requiredProvinces,
  );
  final report = buildBusReport(
    BusReportData(
      meta: meta,
      snapshot: snap,
      provinces: outProvinces,
      requiredProvinces: requiredProvinces,
      stops: stops,
      fileBytes: fileBytes,
      failures: failures,
      mustHave: mustHave,
      dropped: dropped,
      dupOfStation: dups,
      nearSameName: findNearSameName(stops),
      routesTruncated: truncated,
      routesInvalid: invalid,
      ambiguities: ambiguities,
      areas: areas,
      overridesApplied: applied,
    ),
  );
  return BusBuildResult(
    busStopsJson: json,
    report: report,
    stops: stops,
    provinces: outProvinces,
    failures: failures,
    droppedCount: dropped.length,
  );
}

/// Runs the whole build. Throws [StationgenException] on invalid input.
BuildResult buildDataset(BuildInputs inputs) {
  final meta = parseFetchMeta(inputs.fetchMeta);
  if (meta.query != normalizeLf(inputs.query)) {
    throw const StationgenException(
      kErrQueryChanged,
      'query.overpassql differs from the query of the snapshot; run fetch',
    );
  }
  final snap = parseOverpass(inputs.raw);
  if (snap.osmBase != meta.osmBase) {
    throw const StationgenException(
      kErrRawInvalid,
      'fetch-meta.json osmBase does not match raw/overpass.json',
    );
  }
  final provinces = ProvinceTable.parse(inputs.provinces);
  final ov = Overrides.parse(inputs.overrides, provinces);
  final mustHave = parseMustHave(inputs.mustHave, provinces);

  final known = {for (final e in snap.elements) e.ref};
  final stale = [
    for (final r in ov.osmRefs)
      if (!known.contains(r)) r,
  ];
  if (stale.isNotEmpty) {
    throw StationgenException(
      kErrStaleOverride,
      'overrides refer to elements not in the snapshot: ${stale.join(', ')}',
    );
  }

  final groupsOf = <String, List<AreaGroup>>{};
  for (final g in snap.groups) {
    for (final r in g.refs) {
      (groupsOf[r] ??= []).add(g);
    }
  }
  final unmatched = <String, int>{};
  for (final g in snap.groups) {
    if (provinces.resolve(g.displayName) == null) {
      unmatched[g.displayName] =
          (unmatched[g.displayName] ?? 0) + g.refs.length;
    }
  }

  final dropped = <Dropped>[];
  final candidates = <Candidate>[];
  final guessed = <String>{};
  final ambiguities = <ProvinceAmbiguity>[];
  final applied = <String>[];
  final unresolved = <String>[];

  for (final e in snap.elements) {
    final ref = e.ref;
    final id = e.stationId;
    final rawName = rawNameOf(e.tags);
    final drop = ov.dropFor(ref);
    if (drop != null) {
      dropped.add(Dropped(id, rawName, DropReason.overrideDrop));
      applied.add('drop `$id` ($rawName): ${drop.reason} [${drop.source}]');
      continue;
    }
    final patch = ov.patchFor(ref);
    var tags = e.tags;
    var cls = classify(tags);
    if (cls.drop == DropReason.noName && patch?.name != null) {
      tags = {...tags, 'name:vi': patch!.name!};
      cls = classify(tags);
    }
    var reason = cls.drop;
    if (reason == null && (e.lat == null || e.lon == null)) {
      reason = DropReason.noGeometry;
    }
    if (reason == null && !insideVnBbox(e.lat!, e.lon!)) {
      reason = DropReason.outsideBbox;
    }
    if (reason != null) {
      if (patch != null) {
        throw StationgenException(
          kErrOverrideInvalid,
          'patch for $ref, but the element is dropped as ${reason.label}; '
          'a patch cannot bring it back (use "add")',
        );
      }
      dropped.add(Dropped(id, rawName, reason));
      continue;
    }
    final kind = cls.kind!;
    final names = namesOf(tags, kind);
    final resolved = <String>{
      for (final g in groupsOf[ref] ?? const <AreaGroup>[])
        ?provinces.resolve(g.displayName),
    }.toList()..sort((a, b) => provinceKey(a).compareTo(provinceKey(b)));
    final c = Candidate(
      id: id,
      name: names.name,
      kind: kind,
      province: resolved.isEmpty ? '' : resolved.first,
      lat: e.lat!,
      lng: e.lon!,
      aliases: names.aliases,
      // From the kind after the patch, so a patched kind ranks right.
      primary: (patch?.kind ?? kind) == StationKind.train
          ? (tags['railway'] == 'station' || tags['railway'] == 'halt')
          : tags['amenity'] == 'bus_station',
      typeRank: e.type.index,
      osmId: e.id,
    );
    if (patch != null) {
      patch.applyTo(c);
      applied.add('patch `$id` ($rawName): ${patch.reason} [${patch.source}]');
    }
    if (patch?.province == null) {
      if (resolved.isEmpty) {
        unresolved.add(id);
      } else if (resolved.length > 1) {
        ambiguities.add(ProvinceAmbiguity(id, c.name, resolved, c.province));
      }
    }
    if (cls.guessed && patch?.kind == null) {
      guessed.add(id);
    }
    candidates.add(c);
  }
  for (final a in ov.add) {
    candidates.add(a.toCandidate());
    applied.add('add `${a.id}` (${a.name}): ${a.reason} [${a.source}]');
  }
  if (unresolved.isNotEmpty) {
    throw StationgenException(
      kErrProvinceUnresolved,
      'no province for: ${unresolved.join(', ')} (fix with a patch "province")',
    );
  }

  final deduped = dedupe(candidates);
  final stations = [...deduped.kept]..sort(compareStations);
  final json = encodeStationsJson(osmBase: snap.osmBase, stations: stations);
  final fileBytes = utf8.encode(json).length;
  final failures = checkAcceptance(
    stations: stations,
    fileBytes: fileBytes,
    mustHave: mustHave,
    provinces: provinces,
  );
  final keptIds = {for (final s in stations) s.id};
  final report = buildReport(
    ReportData(
      meta: meta,
      snapshot: snap,
      provinces: provinces,
      stations: stations,
      fileBytes: fileBytes,
      failures: failures,
      mustHave: mustHave,
      dropped: dropped,
      nearDuplicates: deduped.nearDuplicates,
      guessed: [
        for (final s in candidates)
          if (guessed.contains(s.id)) (s, keptIds.contains(s.id)),
      ],
      ambiguities: ambiguities,
      unmatchedAreas: unmatched,
      overridesApplied: applied,
    ),
  );
  return BuildResult(
    stationsJson: json,
    report: report,
    stations: stations,
    failures: failures,
    droppedCount: dropped.length,
  );
}
