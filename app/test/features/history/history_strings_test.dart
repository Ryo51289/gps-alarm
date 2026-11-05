// T28 review #3: date and meta line of screen 11 rows; #8: screen reader
// sentence of a month without alarms (pure formatting).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/history/domain/history_logic.dart';
import 'package:napstop/features/history/presentation/history_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../helpers/trip_fixtures.dart';

final DateTime _now = DateTime(2026, 11, 28, 20);

TripRecord _row({
  VehicleKindMsg hint = VehicleKindMsg.train,
  int? travelledM,
  DateTime? startedAt,
}) {
  final base = sampleRecord(
    id: 'r',
    destination: const TripDestination(
      name: 'Ngõ 12',
      lat: 21,
      lng: 105.8,
      kind: DestinationKind.address,
    ),
    vehicleHint: hint,
    startedAtMs:
        (startedAt ?? DateTime(2026, 10, 26, 8)).millisecondsSinceEpoch,
  );
  return TripRecord(
    id: base.id,
    destination: base.destination,
    source: base.source,
    alarm: base.alarm,
    vehicleHint: base.vehicleHint,
    simulated: false,
    startedAtMs: base.startedAtMs,
    travelledM: travelledM,
  );
}

void main() {
  final vi = lookupAppLocalizations(const Locale('vi'));
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(initializeDateFormatting);

  test('historyDate: day/month this year, with the year otherwise', () {
    final thisYear = DateTime(2026, 10, 26, 8).millisecondsSinceEpoch;
    final lastYear = DateTime(2025, 10, 26, 8).millisecondsSinceEpoch;
    expect(historyDate(thisYear, _now, 'vi'), '26/10');
    expect(historyDate(lastYear, _now, 'vi'), '26/10/2025');
    expect(historyDate(thisYear, _now, 'en'), '10/26');
    expect(historyDate(lastYear, _now, 'en'), '10/26/2025');
  });

  test('historyMetaLine: missing parts leave out their separator', () {
    expect(
      vi.historyMetaLine(_row(travelledM: 498000), _now),
      'Tàu · 26/10 · 498 km',
    );
    expect(vi.historyMetaLine(_row(), _now), 'Tàu · 26/10');
    expect(
      vi.historyMetaLine(
        _row(hint: VehicleKindMsg.unknown, travelledM: 1500),
        _now,
      ),
      '26/10 · 1,5 km',
    );
    expect(
      vi.historyMetaLine(_row(hint: VehicleKindMsg.unknown), _now),
      '26/10',
    );
    expect(
      en.historyMetaLine(
        _row(
          hint: VehicleKindMsg.coach,
          travelledM: 850,
          startedAt: DateTime(2025, 3, 4, 8),
        ),
        _now,
      ),
      'Coach · 3/4/2025 · 850 m',
    );
  });

  test('stats sentence: ratio, or "no alarm yet" in a month without one', () {
    const some = HistoryStats(
      tripCount: 6,
      travelledM: 1428000,
      wokeOnTime: 4,
      alarmed: 5,
    );
    expect(
      vi.statsSemantics(some, _now),
      '6 chuyến tháng 11, 1.428 km đã đi, 4/5 lần tỉnh đúng lúc',
    );
    expect(
      vi.statsSemantics(HistoryStats.empty, _now),
      '0 chuyến tháng 11, 0 km đã đi, chưa có lần báo nào',
    );
    expect(
      en.statsSemantics(HistoryStats.empty, _now),
      '0 trips in November, 0 km travelled, no alarms yet',
    );
    expect(vi.statsTrips(_now), 'chuyến tháng 11');
    expect(en.statsTrips(_now), 'trips in November');
  });
}
