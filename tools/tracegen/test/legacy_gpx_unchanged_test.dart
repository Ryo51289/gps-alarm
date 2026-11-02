// T11 TG20 / T11.1 TG49 (tester): every committed GPX keeps its exact bytes.
//
// Size + FNV-1a 32 of the committed files:
// - TG20 (T11, "Không đổi GPX của 6 trace cũ"): the six T02 traces, captured
//   when they were byte-identical to the T02 commit (git blobs 223d656d
//   bus_hn_brt01, 7ea0e8b1 bus_hn_brt01_noisy, 7e4b40ed
//   coach_dn_langco_tunnel, 569f00f3 coach_gb_phuly_overshoot, 164581f3
//   coach_md_tb, d62d43f1 train_hn_dh).
// - TG49 (T11.1 "Toàn bộ GPX giữ nguyên byte"): the nine traces added by T11,
//   captured from HEAD before T11.1 (commit 41d1859, blobs 6c675365
//   bus_hn_brt01_noisy_traps, ddb702a2 bus_hn_slow, 03625e7a
//   coach_dn_langco_neardest, 737ad63a coach_dn_langco_shortgap, fac71fce
//   coach_gb_phuly_offroute, 2641de32 train_hn_dh_midgap, 53d35680
//   train_hn_dh_stopgap, 0a0cc60b train_longstop, cf7e85cc
//   train_longstop_nospd).
//
// fixtures_up_to_date_test only proves fixture == generator; this test also
// catches a generator change that silently rewrites the traces. Changing them
// on purpose needs a task that says so; then update the table.
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

int _fnv1a32(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}

void main() {
  const t02 = [
    ('bus_hn_brt01', 84846, 0x146148bc),
    ('bus_hn_brt01_noisy', 80843, 0x4dc7e10d),
    ('coach_dn_langco_tunnel', 60488, 0xf72e1f15),
    ('coach_gb_phuly_overshoot', 115615, 0x71935514),
    ('coach_md_tb', 263166, 0x68f60dc3),
    ('train_hn_dh', 1202318, 0xdb3d496b),
  ];
  const t11 = [
    ('bus_hn_brt01_noisy_traps', 80876, 0xa001580c),
    ('bus_hn_slow', 129280, 0x08c57263),
    ('coach_dn_langco_neardest', 49528, 0x82b416e6),
    ('coach_dn_langco_shortgap', 68985, 0x435da1e2),
    ('coach_gb_phuly_offroute', 115599, 0x39c091f8),
    ('train_hn_dh_midgap', 1170487, 0xe256d893),
    ('train_hn_dh_stopgap', 1023972, 0xf0b734c4),
    ('train_longstop', 169416, 0x41112048),
    ('train_longstop_nospd', 165712, 0xcc3f179e),
  ];

  void check(String tg, String since, String id, int size, int hash) {
    test('$tg $id.gpx is unchanged since $since', () {
      final bytes = File('${fixturesDir.path}/$id.gpx').readAsBytesSync();
      expect(bytes.length, size, reason: '$id.gpx size changed');
      expect(_fnv1a32(bytes), hash, reason: '$id.gpx content changed');
    });
  }

  for (final (id, size, hash) in t02) {
    check('TG20', 'T02', id, size, hash);
  }
  for (final (id, size, hash) in t11) {
    check('TG49', 'T11', id, size, hash);
  }

  // Traces added after T11.1 (no pinned hash: fixtures_up_to_date_test
  // covers them; T11.2 TG55 checks that the 2 km trackpoints equal
  // coach_gb_phuly_offroute).
  const added = {'coach_gb_phuly_offroute_2k'};

  test('TG49 the table covers every profile and every committed GPX', () {
    final golden = {
      for (final (id, _, _) in [...t02, ...t11]) id,
    };
    expect(golden, hasLength(15));
    expect(golden.intersection(added), isEmpty);
    final all = {...golden, ...added};
    expect(ProfileRepository(dataDir).profileIds().toSet(), all);
    final gpx = {
      for (final f in fixturesDir.listSync().whereType<File>())
        if (f.path.endsWith('.gpx'))
          f.uri.pathSegments.last.replaceAll('.gpx', ''),
    };
    expect(gpx, all);
  });

  test('TG49 FNV-1a 32 reference vectors', () {
    // Guards the hash itself (a broken hash would make the table useless).
    expect(_fnv1a32(const []), 0x811c9dc5);
    expect(_fnv1a32('a'.codeUnits), 0xe40c292c);
    expect(_fnv1a32('foobar'.codeUnits), 0xbf9cf968);
  });
}
