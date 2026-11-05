/// Pure logic of screen 11 "Lịch sử" (T28 §3.3).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

enum HistoryFilter { all, train, coach, bus }

enum HistoryStatus { running, onTime, snoozed, missed, cancelled, unknown }

/// Rows of [f] by `record.displayVehicle` (T22: guess, else hint). A trip of
/// unknown vehicle only shows under [HistoryFilter.all].
List<TripRecord> filterHistory(List<TripRecord> records, HistoryFilter f) {
  final vehicle = switch (f) {
    HistoryFilter.all => null,
    HistoryFilter.train => VehicleKindMsg.train,
    HistoryFilter.coach => VehicleKindMsg.coach,
    HistoryFilter.bus => VehicleKindMsg.bus,
  };
  if (vehicle == null) {
    return records;
  }
  return [
    for (final r in records)
      if (r.displayVehicle == vehicle) r,
  ];
}

/// The badge of [r]. A result maps 1:1. Without one: the running trip →
/// running, even if the row was marked as an orphan (native may answer "no
/// trip" while its snapshot is still loading, review T28 #1); no end while
/// the running trip is not known yet ([activeKnown] false) → null (no badge
/// for a moment); otherwise unknown (an orphan, T28 D4).
HistoryStatus? historyStatusOf(
  TripRecord r, {
  required String? activeTripId,
  required bool activeKnown,
}) {
  final result = r.result;
  if (result != null) {
    return switch (result) {
      TripOutcomeMsg.onTime => HistoryStatus.onTime,
      TripOutcomeMsg.snoozed => HistoryStatus.snoozed,
      TripOutcomeMsg.missed => HistoryStatus.missed,
      TripOutcomeMsg.cancelled => HistoryStatus.cancelled,
    };
  }
  if (activeTripId != null && r.id == activeTripId) {
    return HistoryStatus.running;
  }
  if (r.endedAtMs == null && !activeKnown) {
    return null;
  }
  return HistoryStatus.unknown;
}

/// "Tháng này" card (T28 D6).
@immutable
final class HistoryStats {
  const new({
    required this.tripCount,
    required this.travelledM,
    required this.wokeOnTime,
    required this.alarmed,
  });

  static const HistoryStats empty = HistoryStats(
    tripCount: 0,
    travelledM: 0,
    wokeOnTime: 0,
    alarmed: 0,
  );

  /// Real trips with a result.
  final int tripCount;

  /// Sum of `travelledM`.
  final int travelledM;

  /// onTime + snoozed.
  final int wokeOnTime;

  /// onTime + snoozed + missed (a cancelled trip had no alarm).
  final int alarmed;

  /// Whole kilometres, rounded.
  int get travelledKm => (travelledM / 1000).round();

  @override
  bool operator ==(Object other) =>
      other is HistoryStats &&
      other.tripCount == tripCount &&
      other.travelledM == travelledM &&
      other.wokeOnTime == wokeOnTime &&
      other.alarmed == alarmed;

  @override
  int get hashCode => Object.hash(tripCount, travelledM, wokeOnTime, alarmed);

  @override
  String toString() =>
      'HistoryStats($tripCount, $travelledM, $wokeOnTime/$alarmed)';
}

/// D6. [records] come from `watchRealTripsSince(monthStart)`; rows without a
/// result or simulated are ignored anyway.
HistoryStats monthStats(List<TripRecord> records) {
  var trips = 0;
  var meters = 0;
  var woke = 0;
  var alarmed = 0;
  for (final r in records) {
    final result = r.result;
    if (r.simulated || result == null) {
      continue;
    }
    trips++;
    meters += r.travelledM ?? 0;
    switch (result) {
      case TripOutcomeMsg.onTime || TripOutcomeMsg.snoozed:
        woke++;
        alarmed++;
      case TripOutcomeMsg.missed:
        alarmed++;
      case TripOutcomeMsg.cancelled:
        break;
    }
  }
  return HistoryStats(
    tripCount: trips,
    travelledM: meters,
    wokeOnTime: woke,
    alarmed: alarmed,
  );
}

/// Local midnight of the 1st of [now]'s month, epoch ms.
int monthStartMs(DateTime now) =>
    DateTime(now.year, now.month).millisecondsSinceEpoch;

/// Restart is offered only for real trips that are not running.
bool canRestart(TripRecord r, HistoryStatus? s) =>
    !r.simulated && s != HistoryStatus.running;
