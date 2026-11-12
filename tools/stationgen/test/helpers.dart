import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';

/// Package root of stationgen (tests run with it as the working directory).
Directory get packageDir => Directory.current;

/// Real data directory (`data/stations`).
Directory get dataDir => Directory('${packageDir.path}/../../data/stations');

/// Committed app asset.
File get assetFile => File('${packageDir.path}/../../app/assets/stations.json');

/// Real province table.
ProvinceTable realProvinces() => ProvinceTable.parse(
  File('${dataDir.path}/provinces.json').readAsStringSync(),
);

/// Query used by synthetic builds.
const String kTestQuery = '[out:json];\nnode(1);\nout;\n';

const String kTestOsmBase = '2026-11-01T00:00:00Z';

Map<String, Object?> node(
  int id,
  double lat,
  double lon,
  Map<String, String> tags,
) => {'type': 'node', 'id': id, 'lat': lat, 'lon': lon, 'tags': tags};

Map<String, Object?> way(
  int id,
  double lat,
  double lon,
  Map<String, String> tags,
) => {
  'type': 'way',
  'id': id,
  'center': {'lat': lat, 'lon': lon},
  'nodes': [1, 2, 3],
  'tags': tags,
};

Map<String, Object?> relation(
  int id,
  double lat,
  double lon,
  Map<String, String> tags,
) => {
  'type': 'relation',
  'id': id,
  'center': {'lat': lat, 'lon': lon},
  'members': <Object?>[],
  'tags': tags,
};

/// Admin area group: area tags + member elements of part A.
typedef Group = (String name, List<Map<String, Object?>> members);

/// Overpass JSON with part A = [elements] and part B = [groups].
String overpassJson(
  List<Map<String, Object?>> elements, {
  List<Group> groups = const [],
  String osmBase = kTestOsmBase,
  Map<String, Object?> extra = const {},
}) {
  final all = <Object?>[...elements];
  var areaId = 3600000001;
  for (final (name, members) in groups) {
    all.add({
      'type': 'area',
      'id': areaId++,
      'tags': {'name': name, 'admin_level': '4', 'boundary': 'administrative'},
    });
    for (final m in members) {
      all.add({'type': m['type'], 'id': m['id']});
    }
  }
  return const JsonEncoder.withIndent('  ').convert({
    'version': 0.6,
    'generator': 'Overpass API test',
    'osm3s': {
      'timestamp_osm_base': osmBase,
      'timestamp_areas_base': osmBase,
      'copyright': 'test',
    },
    ...extra,
    'elements': all,
  });
}

String fetchMetaJson({
  String query = kTestQuery,
  String osmBase = kTestOsmBase,
}) => FetchMeta(
  fetchedAt: '2026-11-01T00:00:01Z',
  endpoint: 'https://example.test/api/interpreter',
  osmBase: osmBase,
  areasBase: osmBase,
  bytes: 1,
  query: query,
).encode();

const String kEmptyOverrides =
    '{"schemaVersion": 1, "drop": [], "patch": [], "add": []}';

/// Synthetic build inputs with the real province table.
BuildInputs synthInputs({
  required String raw,
  String overrides = kEmptyOverrides,
  String mustHave = '[]',
  String query = kTestQuery,
  String? fetchMeta,
}) => BuildInputs(
  query: query,
  fetchMeta: fetchMeta ?? fetchMetaJson(),
  raw: raw,
  provinces: File('${dataDir.path}/provinces.json').readAsStringSync(),
  overrides: overrides,
  mustHave: mustHave,
);

/// Station candidate for unit tests.
Candidate cand(
  String id,
  String name, {
  StationKind kind = StationKind.coach,
  String province = 'Hà Nội',
  double lat = 21,
  double lng = 105.8,
  List<String> aliases = const [],
  bool primary = true,
  int typeRank = 0,
  int? osmId,
}) => Candidate(
  id: id,
  name: name,
  kind: kind,
  province: province,
  lat: lat,
  lng: lng,
  aliases: aliases,
  primary: primary,
  typeRank: typeRank,
  osmId: osmId ?? int.parse(id.replaceAll(RegExp('[^0-9]'), '0')),
);

/// Copies the real data inputs of both datasets (not the reports) into a new
/// temp dir.
Directory copyDataToTemp() {
  final tmp = Directory.systemTemp.createTempSync('stationgen_');
  Directory('${tmp.path}/raw').createSync();
  for (final rel in [
    'query.overpassql',
    'provinces.json',
    'overrides.json',
    'must_have.json',
    'raw/overpass.json',
    'raw/fetch-meta.json',
    'bus_query.overpassql',
    'bus_overrides.json',
    'bus_must_have.json',
    'raw/bus_overpass.json',
    'raw/bus_fetch-meta.json',
  ]) {
    File('${dataDir.path}/$rel').copySync('${tmp.path}/$rel');
  }
  return tmp;
}

/// Collects everything written to an [IOSink].
final class CapturedSink {
  new() : this._(<int>[]);

  new _(this._bytes) : sink = IOSink(_Collector(_bytes));

  final List<int> _bytes;
  final IOSink sink;

  Future<String> text() async {
    await sink.flush();
    return utf8.decode(_bytes);
  }
}

final class _Collector implements StreamConsumer<List<int>> {
  new(this._bytes);

  final List<int> _bytes;

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_bytes.addAll);

  @override
  Future<void> close() async {}
}

/// Result of [runCliCaptured].
final class CliRun {
  const new(this.exitCode, this.out, this.err);

  final int exitCode;
  final String out;
  final String err;
}

Future<CliRun> runCliCaptured(
  List<String> args, {
  Directory? workingDirectory,
  Transport? transport,
  DateTime Function()? clock,
}) async {
  final out = CapturedSink();
  final err = CapturedSink();
  final code = await runCli(
    args,
    out: out.sink,
    err: err.sink,
    workingDirectory: workingDirectory ?? packageDir,
    transport: transport,
    clock: clock,
  );
  return CliRun(code, await out.text(), await err.text());
}
