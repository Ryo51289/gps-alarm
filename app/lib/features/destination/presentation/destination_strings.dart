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
  };

  String filterLabel(DestinationFilter filter) => switch (filter) {
    DestinationFilter.all => destinationFilterAll,
    DestinationFilter.train => destinationFilterTrain,
    DestinationFilter.coach => destinationFilterCoach,
    DestinationFilter.places => destinationFilterPlaces,
  };

  String savedSlotLabel(SavedPlaceSlot slot) => switch (slot) {
    SavedPlaceSlot.home => homeSlotHome,
    SavedPlaceSlot.hometown => homeSlotHometown,
    SavedPlaceSlot.work => homeSlotWork,
  };

  /// "Ga tàu · Quảng Trị", with "· cách 402 km" when [meters] is known.
  String stationRowSubtitle(Station s, double? meters) {
    final kind = stationKindLabel(s.kind);
    return meters == null
        ? destinationRowSubtitle(kind, s.province)
        : destinationRowSubtitleDistance(
            kind,
            s.province,
            formatDistanceShort(meters.round(), localeName),
          );
  }

  /// Detail of a pin moved away from [place] (T23 §5).
  String pinnedFrom(String place, double meters) => destinationPinnedFrom(
    place,
    formatDistanceShort(meters.round(), localeName),
  );
}

/// Icon of a station kind.
IconData stationKindIcon(StationKind kind) => switch (kind) {
  StationKind.train => NapIcons.train,
  StationKind.coach => NapIcons.coach,
  StationKind.bus => NapIcons.bus,
};
