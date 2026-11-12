import 'dart:io';

import 'package:stationgen/stationgen.dart';

import 'helpers.dart';

/// Committed bus stop asset.
File get busAssetFile =>
    File('${packageDir.path}/../../app/assets/bus_stops.json');

/// Latitude offset of [m] metres.
double northM(double m) => m / kMetresPerDegLat;

/// Bus stop tags with a name.
Map<String, String> stopTags(
  String name, [
  Map<String, String> extra = const {},
]) => {'highway': 'bus_stop', 'name': name, ...extra};

/// Synthetic bus build inputs with the real province table.
BusBuildInputs busSynthInputs({
  required String raw,
  String overrides = kEmptyOverrides,
  String mustHave = '[]',
  String query = kTestQuery,
  String? fetchMeta,
}) => BusBuildInputs(
  query: query,
  fetchMeta: fetchMeta ?? fetchMetaJson(),
  raw: raw,
  provinces: File('${dataDir.path}/provinces.json').readAsStringSync(),
  overrides: overrides,
  mustHave: mustHave,
);

/// Bus stop candidate for unit tests.
BusCandidate busCand(
  String id,
  String name, {
  String province = 'Hà Nội',
  double lat = 21,
  double lng = 105.8,
  List<String> routes = const [],
}) => BusCandidate(
  id: id,
  name: name,
  province: province,
  lat: lat,
  lng: lng,
  routes: routes,
  typeRank: id.startsWith('w') ? 1 : 0,
  osmId: int.parse(id.substring(1)),
);

/// Output stop for unit tests.
BusStop busStop(
  String id,
  String name, {
  String province = 'Hà Nội',
  double lat = 21,
  double lng = 105.8,
  List<String> routes = const [],
}) => BusStop(
  id: id,
  name: name,
  province: province,
  lat: lat,
  lng: lng,
  routes: routes,
);
