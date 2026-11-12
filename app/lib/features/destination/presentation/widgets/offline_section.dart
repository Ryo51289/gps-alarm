import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/destination_strings.dart';
import 'package:napstop/features/destination/presentation/widgets/bus_stop_section.dart';
import 'package:napstop/features/destination/presentation/widgets/osm_attribution.dart';
import 'package:napstop/features/destination/presentation/widgets/result_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Station results of chips "Tất cả / Ga tàu / Bến xe" (T23 §9): state line
/// or rows, the bus stop section (T24.3: under the stations, above them for
/// a "trạm buýt …" query, alone on chip "Trạm buýt"), then one OSM
/// attribution line when a station or bus stop is listed.
class OfflineSection extends StatelessWidget {
  const new({
    required this.state,
    required this.isSelected,
    required this.onSelect,
    required this.onRetry,
    this.onRetryBusStops,
    this.showNoMatchPinHint = false,
    this.addressOn = false,
    super.key,
  });

  final DestinationState state;
  final bool Function(Station s) isSelected;
  final ValueChanged<Station> onSelect;
  final VoidCallback onRetry;

  /// "Thử lại" of the bus stop section (T24.3 D10).
  final VoidCallback? onRetryBusStops;

  /// T23.3: a map is shown, so "no match" also says how to drop a pin.
  final bool showNoMatchPinHint;

  /// T23.5: address search is on, so the "start typing" note mentions it.
  final bool addressOn;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final busSection = BusStopSection(
      state: state,
      isSelected: isSelected,
      onSelect: onSelect,
      onRetry: onRetryBusStops ?? () {},
      addressOn: addressOn,
    );
    final attribution = OsmAttribution(
      label: l.stationDataAttribution,
      hint: l.destinationOsmAttributionHint,
    );
    if (state.filter == DestinationFilter.busStop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [busSection, if (state.busStops.isNotEmpty) attribution],
      );
    }
    final busFirst = busStopsFirst(state.query, state.filter);
    final query = state.query.trim();
    final rows = state.offline;
    final catalog = state.catalog;
    final Widget? status;
    if (catalog.hasError && !catalog.hasValue) {
      status = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NapSpace.s16,
          vertical: NapSpace.s8,
        ),
        child: NapBanner(
          message: l.destinationCatalogError,
          action: NapButton(
            label: l.commonRetry,
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.small,
            onPressed: onRetry,
          ),
        ),
      );
    } else if (!catalog.hasValue) {
      status = PanelNote(l.destinationCatalogLoading, loading: true);
    } else if (queryChars(state.query) < kMinOfflineQueryChars) {
      status = PanelNote(
        addressOn
            ? l.destinationStartTypingWithAddress
            : l.destinationStartTyping,
      );
    } else if (rows.isEmpty && busStopsPending(state)) {
      // Review T24.3 #1: bus stops match (or are loading) below: no "no
      // match" / "pin it yourself" line above them.
      status = null;
    } else if (rows.isEmpty) {
      status = showNoMatchPinHint
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelNote(l.destinationNoStationMatch(query)),
                PanelNote(l.destinationNoMatchPinHint),
              ],
            )
          : PanelNote(l.destinationNoStationMatch(query));
    } else {
      status = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busFirst) busSection,
        ?status,
        for (final m in rows)
          ResultRow(
            key: ValueKey('station-${m.station.id}'),
            icon: stationKindIcon(m.station.kind),
            title: m.station.name,
            subtitle: l.stationRowSubtitle(
              m.station,
              state.distanceByStationId[m.station.id],
            ),
            selected: isSelected(m.station),
            onTap: () => onSelect(m.station),
          ),
        if (!busFirst) busSection,
        if (rows.isNotEmpty || state.busStops.isNotEmpty) attribution,
      ],
    );
  }
}
