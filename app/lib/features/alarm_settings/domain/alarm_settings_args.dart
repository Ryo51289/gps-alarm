/// What screen 3 receives through `GoRouterState.extra` (T25 §2.2).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

/// PRIVACY: [toString] never prints the destination.
@immutable
final class AlarmSettingsArgs {
  const new({required this.draft, this.preset, this.simulation});

  final TripDraft draft;

  /// Full settings to start from (T28 history). Wins over `draft.alarm`.
  final TripSettings? preset;

  /// Demo simulation (T28, PRD §4); null for a real trip.
  final SimulationMsg? simulation;

  /// [AlarmSettingsArgs] as is; a bare [TripDraft] (screens 1, 2); anything
  /// else, e.g. a route restored without `extra`, null.
  static AlarmSettingsArgs? fromExtra(Object? extra) => switch (extra) {
    final AlarmSettingsArgs args => args,
    final TripDraft draft => AlarmSettingsArgs(draft: draft),
    _ => null,
  };

  @override
  String toString() =>
      'AlarmSettingsArgs($draft, $preset, simulated: ${simulation != null})';
}
