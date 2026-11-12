/// ODbL notice for the OpenStreetMap station data (spec T24 §8).
///
/// Legal text shown on Flutter's (English only) license page, so it is not
/// a UI string and does not go through ARB.
library;

import 'package:flutter/foundation.dart';

/// Public URL of the full station database (ODbL §4.6). Set when it is
/// published (spec T24 Q1, a public repository); T40 requires non-null.
const String? kStationDataPublicUrl = null;

/// Package name of the [LicenseRegistry] entry.
const String kStationDataLicensePackage =
    'NapStop station data (OpenStreetMap)';

/// First line (T24.3 §8: both offline datasets).
const String _dataLine =
    'Station data (assets/stations.json, assets/bus_stops.json) '
    '© OpenStreetMap contributors.';

const String _odblUrl = 'https://opendatacommons.org/licenses/odbl/1-0/';

/// Text of the license entry; the database line only when [publicUrl] is
/// set.
String stationDataLicenseText({String? publicUrl = kStationDataPublicUrl}) {
  final lines = [
    _dataLine,
    'Available under the Open Database License (ODbL) 1.0: $_odblUrl',
    'Source and copyright: https://www.openstreetmap.org/copyright',
    if (publicUrl != null) 'Full station database: $publicUrl',
  ];
  return lines.join('\n');
}

bool _registered = false;

/// Adds the station data notice to [LicenseRegistry] once. Only registers a
/// closure; nothing is loaded at app start.
void registerStationDataLicense() {
  if (_registered) {
    return;
  }
  _registered = true;
  LicenseRegistry.addLicense(
    () => Stream.value(
      LicenseEntryWithLineBreaks(const [
        kStationDataLicensePackage,
      ], stationDataLicenseText()),
    ),
  );
}

/// Allows tests to register again after `LicenseRegistry.reset()`.
@visibleForTesting
void resetStationDataLicenseRegistration() => _registered = false;
