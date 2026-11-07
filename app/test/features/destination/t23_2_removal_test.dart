// T23.2 RU01, RU02, RT01: what the removal of Google Places leaves behind.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/db/converters.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

void main() {
  test('RU01 three filter chips, no address chip', () {
    expect(DestinationFilter.values, [
      DestinationFilter.all,
      DestinationFilter.train,
      DestinationFilter.coach,
    ]);
  });

  test('RU02 rows written by a Places build still read back', () {
    expect(
      const DestinationSourceConverter().fromSql('places'),
      DestinationSource.places,
    );
    expect(
      const DestinationKindConverter().fromSql('address'),
      DestinationKind.address,
    );
  });

  test('RT01 no Places non-fatal reason; the map one stays', () {
    final names = NonFatalReason.values.map((r) => r.name);
    expect(names, isNot(contains('placesRequestFailed')));
    expect(names, contains('mapsLoadFailed'));
  });
}
