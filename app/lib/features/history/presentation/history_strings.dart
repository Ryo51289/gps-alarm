import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/history/domain/history_logic.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Display strings of screen 11 (T28 §3.4, §9).
extension HistoryStrings on AppLocalizations {
  String filterLabel(HistoryFilter f) => switch (f) {
    HistoryFilter.all => historyFilterAll,
    HistoryFilter.train => historyFilterTrain,
    HistoryFilter.coach => historyFilterCoach,
    HistoryFilter.bus => historyFilterBus,
  };

  String statusLabel(HistoryStatus s, int snoozeCount) => switch (s) {
    HistoryStatus.onTime => historyOutcomeOnTime,
    HistoryStatus.snoozed => historyOutcomeSnoozed(snoozeCount),
    HistoryStatus.missed => historyOutcomeMissed,
    HistoryStatus.cancelled => historyOutcomeCancelled,
    HistoryStatus.unknown => historyOutcomeUnknown,
    HistoryStatus.running => historyOutcomeRunning,
  };

  /// "4/5", or "—" when no trip of the month had an alarm.
  String statsRatio(HistoryStats s) => s.alarmed == 0
      ? historyStatsRatioNone
      : historyStatsRatio(s.wokeOnTime, s.alarmed);

  /// "chuyến tháng 11" (vi: month number) / "trips in November" (en).
  String statsTrips(DateTime month) => historyStatsTrips(
    month.month,
    DateFormat('MMMM', localeName).format(month),
  );

  /// One sentence for screen readers; without any alarm this month it says
  /// so instead of reading "—".
  String statsSemantics(HistoryStats s, DateTime month) {
    final name = DateFormat('MMMM', localeName).format(month);
    return s.alarmed == 0
        ? historyStatsSemanticsNoAlarm(
            s.tripCount,
            month.month,
            name,
            statsKm(s),
          )
        : historyStatsSemantics(
            s.tripCount,
            month.month,
            name,
            statsKm(s),
            statsRatio(s),
          );
  }

  /// "1.428" (vi) / "1,428" (en).
  String statsKm(HistoryStats s) =>
      NumberFormat.decimalPattern(localeName).format(s.travelledKm);

  /// "Tàu · 26/10 · 498 km"; a missing vehicle or distance is left out with
  /// its separator.
  String historyMetaLine(TripRecord r, DateTime now) {
    final vehicle = switch (r.displayVehicle) {
      null => null,
      final v => vehicleLabel(v),
    };
    final date = historyDate(r.startedAtMs, now, localeName);
    final meters = r.travelledM;
    final distance = meters == null
        ? null
        : formatDistanceShort(meters, localeName);
    return switch ((vehicle, distance)) {
      (final v?, final d?) => historyMeta(v, date, d),
      (final v?, null) => historyMetaPair(v, date),
      (null, final d?) => historyMetaPair(date, d),
      (null, null) => date,
    };
  }
}

/// Start date of a row on the phone's clock: "26/10" in the current year,
/// "26/10/2025" otherwise (en: "10/26", "10/26/2025").
String historyDate(int startedAtMs, DateTime now, String locale) {
  final d = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
  return d.year == now.year
      ? DateFormat.Md(locale).format(d)
      : DateFormat.yMd(locale).format(d);
}

/// Badge tone of a status (wireframe: green / orange / red).
NapTone historyTone(HistoryStatus s) => switch (s) {
  HistoryStatus.onTime => NapTone.success,
  HistoryStatus.snoozed => NapTone.warning,
  HistoryStatus.missed => NapTone.danger,
  HistoryStatus.cancelled || HistoryStatus.unknown => NapTone.neutral,
  HistoryStatus.running => NapTone.accent,
};

/// Icon of a row, like the recent trips of screen 1.
IconData historyIcon(TripRecord r) => switch (r.displayVehicle) {
  VehicleKindMsg.train => NapIcons.train,
  VehicleKindMsg.coach => NapIcons.coach,
  VehicleKindMsg.bus => NapIcons.bus,
  VehicleKindMsg.unknown || null => switch (r.destination.kind) {
    DestinationKind.train => NapIcons.train,
    DestinationKind.coach => NapIcons.coach,
    DestinationKind.bus => NapIcons.bus,
    DestinationKind.address || DestinationKind.pin => NapIcons.place,
  },
};
