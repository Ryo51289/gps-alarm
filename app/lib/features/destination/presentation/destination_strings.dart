import 'package:flutter/widgets.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Enum to display string mappings of screen 2 (T23 §12).
extension DestinationStrings on AppLocalizations {
  String stationKindLabel(StationKind kind) => switch (kind) {
    StationKind.train => stationKindTrain,
    StationKind.coach => stationKindCoach,
    StationKind.bus => stationKindBus,
    StationKind.busStop => stationKindBusStop,
  };

  String filterLabel(DestinationFilter filter) => switch (filter) {
    DestinationFilter.all => destinationFilterAll,
    DestinationFilter.train => destinationFilterTrain,
    DestinationFilter.coach => destinationFilterCoach,
    DestinationFilter.busStop => destinationFilterBusStop,
  };

  String savedSlotLabel(SavedPlaceSlot slot) => switch (slot) {
    SavedPlaceSlot.home => homeSlotHome,
    SavedPlaceSlot.hometown => homeSlotHometown,
    SavedPlaceSlot.work => homeSlotWork,
  };

  /// "Ga tàu · Quảng Trị", with "· cách 402 km" when [meters] is known. A
  /// bus stop with routes adds "· tuyến 03, 14" (T24.3 §6.5).
  String stationRowSubtitle(Station s, double? meters) {
    final kind = stationKindLabel(s.kind);
    final distance = meters == null
        ? null
        : formatDistanceShort(meters.round(), localeName);
    final routes = routeRefsLabel(s.routeRefs);
    if (routes != null) {
      return distance == null
          ? destinationRowBusSubtitle(kind, s.province, routes)
          : destinationRowBusSubtitleDistance(
              kind,
              s.province,
              routes,
              distance,
            );
    }
    return distance == null
        ? destinationRowSubtitle(kind, s.province)
        : destinationRowSubtitleDistance(kind, s.province, distance);
  }

  /// Detail of a pin moved away from [place] (T23 §5).
  String pinnedFrom(String place, double meters) => destinationPinnedFrom(
    place,
    formatDistanceShort(meters.round(), localeName),
  );
}

/// Routes shown in a bus stop row (T24.3 §6.5).
const int kMaxShownRoutes = 3;

/// "03, 14" for [routes]: the first [kMaxShownRoutes] joined by ", ", with
/// "…" when there are more; null without routes.
String? routeRefsLabel(List<String> routes) {
  if (routes.isEmpty) {
    return null;
  }
  final shown = routes.take(kMaxShownRoutes).join(', ');
  return routes.length > kMaxShownRoutes ? '$shown…' : shown;
}

/// Icon of a station kind.
IconData stationKindIcon(StationKind kind) => switch (kind) {
  StationKind.train => NapIcons.train,
  StationKind.coach => NapIcons.coach,
  StationKind.bus => NapIcons.bus,
  StationKind.busStop => NapIcons.busStop,
};
