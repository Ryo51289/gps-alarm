import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/home/presentation/home_format.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Chuyến gần đây": one row per recent destination; a tap restarts it
/// (screen 3 prefilled, T22 §9.3).
class RecentTripsSection extends StatelessWidget {
  const new({required this.trips, required this.onTap, super.key});

  /// null: the database could not be read.
  final List<TripRecord>? trips;
  final void Function(TripRecord record) onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final trips = this.trips;
    if (trips == null || trips.isEmpty) {
      return Text(
        trips == null ? l.homeRecentError : l.homeRecentEmpty,
        style: context.napText.bodySmall!.copyWith(
          color: context.napColors.textSecondary,
        ),
      );
    }
    final locale = Localizations.localeOf(context);
    return NapListGroup(
      children: [
        for (final r in trips)
          MergeSemantics(
            child: Semantics(
              onTapHint: l.homeRecentRestartHint,
              child: NapListRow(
                leading: NapIconTile(icon: _iconOf(r)),
                title: r.destination.name,
                subtitle: _subtitleOf(r, l, locale),
                chevron: true,
                onTap: () => onTap(r),
              ),
            ),
          ),
      ],
    );
  }

  static String _subtitleOf(TripRecord r, AppLocalizations l, Locale locale) {
    final alarm = alarmSummary(r.alarm, l, locale);
    final vehicle = r.displayVehicle;
    final vehicleLabel = vehicle == null ? null : l.vehicleLabel(vehicle);
    return vehicleLabel == null
        ? alarm
        : l.homeRecentSubtitle(vehicleLabel, alarm);
  }

  static IconData _iconOf(TripRecord r) {
    final vehicle = r.displayVehicle;
    if (vehicle != null) {
      return switch (vehicle) {
        VehicleKindMsg.train => NapIcons.train,
        VehicleKindMsg.coach => NapIcons.coach,
        VehicleKindMsg.bus => NapIcons.bus,
        VehicleKindMsg.unknown => NapIcons.place,
      };
    }
    return switch (r.destination.kind) {
      DestinationKind.train => NapIcons.train,
      DestinationKind.coach => NapIcons.coach,
      DestinationKind.bus => NapIcons.bus,
      DestinationKind.address || DestinationKind.pin => NapIcons.place,
    };
  }
}
