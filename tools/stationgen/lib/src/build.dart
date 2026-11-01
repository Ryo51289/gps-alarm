/// `stationgen build`: snapshot → stations.json + BUILD_REPORT.md (spec T24
/// §4.1). Pure: no IO besides [BuildInputs.read].
library;

import 'dart:convert';
import 'dart:io';

import 'package:stationgen/src/acceptance.dart';
import 'package:stationgen/src/classify.dart';
import 'package:stationgen/src/dedupe.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/names.dart';
import 'package:stationgen/src/overrides.dart';
import 'package:stationgen/src/prefixes.dart';
import 'package:stationgen/src/provinces.dart';
import 'package:stationgen/src/raw.dart';
import 'package:stationgen/src/report.dart';
import 'package:stationgen/src/writer.dart';

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
