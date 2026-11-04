import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const String profileId = 'coach_dn_langco_tunnel';
const String routeId = 'road_dn_langco';
const String profileFile = 'profiles/$profileId.json';
const String routeFile = 'routes/$routeId.json';

Map<String, Object?> readJson(String relative) =>
    jsonDecode(File('${dataDir.path}/$relative').readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> obj(Object? v) => v! as Map<String, Object?>;
List<Object?> arr(Object? v) => v! as List<Object?>;

/// Writes (possibly mutated) copies of the tunnel profile and its route to
/// a temporary data directory and loads the profile.
Future<(Profile, Route)> loadMutated({
  void Function(Map<String, Object?> profile)? profile,
  void Function(Map<String, Object?> route)? route,
}) async {
  final tmp = await Directory.systemTemp.createTemp('tracegen_profile_');
  addTearDown(() => tmp.delete(recursive: true));
  await Directory('${tmp.path}/profiles').create();
  await Directory('${tmp.path}/routes').create();
  final p = readJson(profileFile);
  final r = readJson(routeFile);
  profile?.call(p);
  route?.call(r);
  await File('${tmp.path}/$profileFile').writeAsString(jsonEncode(p));
  await File('${tmp.path}/$routeFile').writeAsString(jsonEncode(r));
  return ProfileRepository(tmp).load(profileId);
}

void main() {
  group('ProfileRepository (TC19)', () {
    test('lists the seventeen profiles in id order', () {
      expect(ProfileRepository(dataDir).profileIds(), [
        'bus_hn_brt01',
        'bus_hn_brt01_noisy',
        'bus_hn_brt01_noisy_traps',
        'bus_hn_slow',
        'coach_dn_langco_neardest',
        'coach_dn_langco_shortgap',
        'coach_dn_langco_tunnel',
        'coach_gb_caugie_gappass',
        'coach_gb_phuly_offroute',
        'coach_gb_phuly_offroute_2k',
        'coach_gb_phuly_overshoot',
        'coach_md_tb',
        'train_hn_dh',
        'train_hn_dh_midgap',
        'train_hn_dh_stopgap',
        'train_longstop',
        'train_longstop_nospd',
      ]);
    });

    test('loads a valid profile', () async {
      final (p, r) = await loadMutated();
      expect(p.id, profileId);
      expect(p.vehicle, Vehicle.coach);
      expect(p.noiseSeed, p.seed);
      expect(p.gpsGaps.single.durationS, 360);
      expect(p.cases, hasLength(2));
      final gpsLost = p.cases.first;
      expect(gpsLost.status, 'final');
      expect(gpsLost.testIds, ['TR05']);
      expect(gpsLost.preAlert, isFalse);
      expect(gpsLost.expect.first.filter.cause, 'NO_FIX_TIMEOUT');
      expect(p.cases.last.expectSummaryVehicle, 'UNKNOWN');
      expect(r.waypoints, hasLength(8));
    });

    final cases =
        <
          String,
          (
            String,
            void Function(Map<String, Object?>)?,
            void Function(Map<String, Object?>)?,
          )
        >{
          'unknown route': (
            '$profileFile: route',
            (p) => p['route'] = 'nope',
            null,
          ),
          'duplicate waypoint id': (
            '$routeFile: waypoints[1].id',
            null,
            (r) => obj(arr(r['waypoints'])[1])['id'] = 'bx_trung_tam_da_nang',
          ),
          'bad source': (
            '$routeFile: waypoints[1].source',
            null,
            (r) => obj(arr(r['waypoints'])[1])['source'] = 'osm:foo/1',
          ),
          'lat 91': (
            '$routeFile: waypoints[2].lat',
            null,
            (r) => obj(arr(r['waypoints'])[2])['lat'] = 91,
          ),
          'first speed limit not at the first waypoint': (
            '$profileFile: speedLimits[0].from',
            (p) => obj(arr(p['speedLimits'])[0])['from'] = 'hoa_khanh',
            null,
          ),
          'speed limits out of order': (
            '$profileFile: speedLimits[2].from',
            (p) {
              final l = arr(p['speedLimits']);
              final t = l[1];
              l[1] = l[2];
              l[2] = t;
            },
            null,
          ),
          'unknown from': (
            '$profileFile: speedLimits[1].from',
            (p) => obj(arr(p['speedLimits'])[1])['from'] = 'nope',
            null,
          ),
          'stop at the last waypoint': (
            '$profileFile: stops[0].at',
            (p) {
              p['stops'] = [
                {'at': 'lang_co_center', 'dwellS': 60},
              ];
            },
            null,
          ),
          'dwell shorter than 2 samples': (
            '$profileFile: stops[0].dwellS',
            (p) {
              p['stops'] = [
                {'at': 'kim_lien', 'dwellS': 5},
              ];
            },
            null,
          ),
          'gap not a multiple of the interval': (
            '$profileFile: gpsGaps[0].durationS',
            (p) => obj(arr(p['gpsGaps'])[0])['durationS'] = 362,
            null,
          ),
          'rho = 1': (
            '$profileFile: noise.rho',
            (p) => obj(p['noise'])['rho'] = 1,
            null,
          ),
          'outlierMinM > outlierMaxM': (
            '$profileFile: noise.outlierMinM',
            (p) {
              obj(p['noise'])
                ..['outlierMinM'] = 10
                ..['outlierMaxM'] = 5;
            },
            null,
          ),
          'duplicate case id': (
            '$profileFile: cases[1].id',
            (p) {
              final c = arr(p['cases']);
              c.insert(1, deepCopy(c[0]));
            },
            null,
          ),
          'unknown event': (
            '$profileFile: cases[0].expect[0].event',
            (p) => obj(arr(obj(arr(p['cases'])[0])['expect'])[0])['event'] =
                'boom',
            null,
          ),
          'bad anchor': (
            '$profileFile: cases[0].expect[0].notBefore.anchor',
            (p) {
              obj(
                obj(arr(obj(arr(p['cases'])[0])['expect'])[0])['notBefore'],
              )['anchor'] = 'route<1000';
            },
            null,
          ),
          'gap anchor out of range': (
            '$profileFile: cases[0].expect[0].notBefore.anchor',
            (p) {
              obj(
                obj(arr(obj(arr(p['cases'])[0])['expect'])[0])['notBefore'],
              )['anchor'] = 'gpsGap[1].start';
            },
            null,
          ),
          'startTime without Z': (
            '$profileFile: startTime',
            (p) => p['startTime'] = '2026-03-14T02:00:00',
            null,
          ),
          'unknown key': (
            '$profileFile: speedlimit',
            (p) => p['speedlimit'] = 1,
            null,
          ),
          'unknown nested key': (
            '$profileFile: motion.accel',
            (p) => obj(p['motion'])['accel'] = 1,
            null,
          ),
          'id differs from the file name': (
            '$profileFile: id',
            (p) => p['id'] = 'other',
            null,
          ),
          'event both expected and forbidden': (
            '$profileFile: cases[0].forbid[0]',
            (p) => obj(arr(p['cases'])[0])['forbid'] = ['alarm'],
            null,
          ),
          'integer field given as decimal': (
            '$profileFile: sampleIntervalS',
            (p) => p['sampleIntervalS'] = 5.5,
            null,
          ),
        };

    for (final MapEntry(key: name, value: (path, profile, route))
        in cases.entries) {
      test('rejects: $name', () async {
        await expectLater(
          loadMutated(profile: profile, route: route),
          throwsA(isA<ProfileException>().having((e) => e.path, 'path', path)),
        );
      });
    }
  });
}
