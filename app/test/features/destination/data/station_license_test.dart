// TC35: ODbL notice in the LicenseRegistry.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/data/station_license.dart';

void main() {
  setUp(() {
    LicenseRegistry.reset();
    resetStationDataLicenseRegistration();
  });

  Future<List<LicenseEntry>> stationEntries() async => [
    await for (final e in LicenseRegistry.licenses)
      if (e.packages.contains(kStationDataLicensePackage)) e,
  ];

  test('registers one entry with attribution, license and URLs', () async {
    registerStationDataLicense();
    registerStationDataLicense(); // idempotent
    final entries = await stationEntries();
    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('OpenStreetMap'));
    expect(text, contains('ODbL'));
    expect(text, contains('https://opendatacommons.org/licenses/odbl/1-0/'));
    expect(text, contains('https://www.openstreetmap.org/copyright'));
    expect(kStationDataPublicUrl, isNull);
    expect(text, isNot(contains('Full station database')));
  });

  test('database line once the public URL is known', () {
    expect(
      stationDataLicenseText(publicUrl: 'https://example.test/stations'),
      endsWith('Full station database: https://example.test/stations'),
    );
  });
}
