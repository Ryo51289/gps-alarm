// T28 H11-H13: filter, status, month stats, month start (pure).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/history/domain/history_logic.dart';

import '../../helpers/trip_fixtures.dart';

TripRecord rec(
  String id, {
  TripOutcomeMsg? result,
  int? endedAtMs,
  VehicleKindMsg hint = VehicleKindMsg.train,
  VehicleKindMsg? guess,
  int? travelledM,
  bool simulated = false,
  int startedAtMs = 1700000000000,
}) {
  final base = sampleRecord(
    id: id,
    vehicleHint: hint,
    simulated: simulated,
    startedAtMs: startedAtMs,
  );
  return TripRecord(
    id: base.id,
    destination: base.destination,
    source: base.source,
    alarm: base.alarm,
    vehicleHint: base.vehicleHint,
    simulated: base.simulated,
    startedAtMs: base.startedAtMs,
    endedAtMs: endedAtMs ?? (result == null ? null : startedAtMs + 1000),
    result: result,
    travelledM: travelledM,
    vehicleGuess: guess,
  );
}

void main() {
  group('H11 filterHistory', () {
    final train = rec('t', result: TripOutcomeMsg.onTime);
    final coach = rec('c', hint: VehicleKindMsg.coach);
    // The guess wins over the hint.
    final bus = rec('b', guess: VehicleKindMsg.bus);
    final unknown = rec('u', hint: VehicleKindMsg.unknown);
    final unknownGuess = rec(
      'ug',
      hint: VehicleKindMsg.coach,
      guess: VehicleKindMsg.unknown,
    );
    final all = [train, coach, bus, unknown, unknownGuess];

    test('by display vehicle; unknown vehicle only in all', () {
      expect(filterHistory(all, HistoryFilter.all), all);
      expect(filterHistory(all, HistoryFilter.train), [train]);
      expect(filterHistory(all, HistoryFilter.coach), [coach, unknownGuess]);
      expect(filterHistory(all, HistoryFilter.bus), [bus]);
      expect(filterHistory(const [], HistoryFilter.bus), isEmpty);
    });
  });

  group('H11 historyStatusOf', () {
    HistoryStatus? status(TripRecord r, {String? active, bool known = true}) =>
        historyStatusOf(r, activeTripId: active, activeKnown: known);

    test('results map 1:1', () {
      expect(
        status(rec('a', result: TripOutcomeMsg.onTime)),
        HistoryStatus.onTime,
      );
      expect(
        status(rec('a', result: TripOutcomeMsg.snoozed)),
        HistoryStatus.snoozed,
      );
      expect(
        status(rec('a', result: TripOutcomeMsg.missed)),
        HistoryStatus.missed,
      );
      expect(
        status(rec('a', result: TripOutcomeMsg.cancelled), active: 'a'),
        HistoryStatus.cancelled,
      );
    });

    test('no result', () {
      final open = rec('a');
      expect(status(open, active: 'a'), HistoryStatus.running);
      expect(status(open, active: 'a', known: false), HistoryStatus.running);
      expect(status(open, known: false), isNull);
      expect(status(open, active: 'other'), HistoryStatus.unknown);
      expect(status(open), HistoryStatus.unknown);
      // A row marked as an orphan by mistake (native said "no trip" while its
      // snapshot loaded) is still the running trip once it is known (#1).
      final orphan = rec('a', endedAtMs: 5);
      expect(status(orphan, active: 'a'), HistoryStatus.running);
      expect(status(orphan, active: 'a', known: false), HistoryStatus.running);
      expect(status(orphan, known: false), HistoryStatus.unknown);
      expect(status(orphan), HistoryStatus.unknown);
    });

    test('canRestart: real trips that are not running', () {
      expect(canRestart(rec('a'), HistoryStatus.onTime), isTrue);
      expect(canRestart(rec('a'), HistoryStatus.unknown), isTrue);
      expect(canRestart(rec('a'), null), isTrue);
      expect(canRestart(rec('a'), HistoryStatus.running), isFalse);
      expect(
        canRestart(rec('a', simulated: true), HistoryStatus.onTime),
        isFalse,
      );
    });
  });

  test('H12 monthStats of the PRD §4 example', () {
    final records = [
      rec('1', result: TripOutcomeMsg.onTime, travelledM: 498000),
      rec('2', result: TripOutcomeMsg.snoozed, travelledM: 110000),
      rec('3', result: TripOutcomeMsg.onTime, travelledM: 32000),
      rec('4', result: TripOutcomeMsg.missed, travelledM: 498000),
      rec('5', result: TripOutcomeMsg.onTime, travelledM: 290000),
      rec('6', result: TripOutcomeMsg.cancelled),
      // Defensive: ignored even if the query let them through.
      rec(
        's',
        result: TripOutcomeMsg.onTime,
        travelledM: 999000,
        simulated: true,
      ),
      rec('n'),
    ];
    final s = monthStats(records);
    expect(s.tripCount, 6);
    expect(s.travelledM, 1428000);
    expect(s.travelledKm, 1428);
    expect(s.wokeOnTime, 4);
    expect(s.alarmed, 5);
    expect(monthStats(const []), HistoryStats.empty);
  });

  test('H13 monthStartMs on the local clock', () {
    expect(
      monthStartMs(DateTime(2026, 11, 30, 23, 59)),
      DateTime(2026, 11).millisecondsSinceEpoch,
    );
    expect(
      monthStartMs(DateTime(2026, 12)),
      DateTime(2026, 12).millisecondsSinceEpoch,
    );
    expect(
      monthStartMs(DateTime(2027, 1, 15)),
      DateTime(2027).millisecondsSinceEpoch,
    );
  });
}
