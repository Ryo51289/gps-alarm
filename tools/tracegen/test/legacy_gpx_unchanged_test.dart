// T11 TG20 (tester): the six T02 GPX files keep their exact bytes (T11
// "Không đổi GPX của 6 trace cũ"). Size + FNV-1a 32 of the committed files,
// captured when they were byte-identical to the T02 commit (git blobs
// 223d656d bus_hn_brt01, 7ea0e8b1 bus_hn_brt01_noisy, 7e4b40ed
// coach_dn_langco_tunnel, 569f00f3 coach_gb_phuly_overshoot, 164581f3
// coach_md_tb, d62d43f1 train_hn_dh). fixtures_up_to_date_test only proves
// fixture == generator; this test also catches a generator change that
// silently rewrites the old traces. Changing them on purpose needs a task
// that says so; then update the table.
import 'dart:io';

import 'package:test/test.dart';

import 'helpers.dart';

int _fnv1a32(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}

void main() {
  const golden = [
    ('bus_hn_brt01', 84846, 0x146148bc),
    ('bus_hn_brt01_noisy', 80843, 0x4dc7e10d),
    ('coach_dn_langco_tunnel', 60488, 0xf72e1f15),
    ('coach_gb_phuly_overshoot', 115615, 0x71935514),
    ('coach_md_tb', 263166, 0x68f60dc3),
    ('train_hn_dh', 1202318, 0xdb3d496b),
  ];
  for (final (id, size, hash) in golden) {
    test('TG20 $id.gpx is unchanged since T02', () {
      final bytes = File('${fixturesDir.path}/$id.gpx').readAsBytesSync();
      expect(bytes.length, size, reason: '$id.gpx size changed');
      expect(_fnv1a32(bytes), hash, reason: '$id.gpx content changed');
    });
  }
}
