/// Bundled simulation traces (T18 §9): ids and catalog entries of
/// `assets/sim/catalog.json`. Display names are ARB keys by id (T28).
library;

import 'package:napstop/core/bridge/core_api.g.dart';

/// Ids of the bundled simulation traces (assets/sim/catalog.json, T18),
/// passed as `SimulationMsg.traceAsset`.
abstract final class SimTraces {
  static const trainHnDh = 'train_hn_dh';
  static const coachMdTb = 'coach_md_tb';
  static const busHnBrt01 = 'bus_hn_brt01';
  static const coachDnLangcoTunnel = 'coach_dn_langco_tunnel';
  static const coachGbPhulyOvershoot = 'coach_gb_phuly_overshoot';
  static const busHnBrt01Noisy = 'bus_hn_brt01_noisy';

  /// Catalog order (PRD §4).
  static const List<String> all = [
    trainHnDh,
    coachMdTb,
    busHnBrt01,
    coachDnLangcoTunnel,
    coachGbPhulyOvershoot,
    busHnBrt01Noisy,
  ];
}

/// Destination of a bundled trace (the station the trace ends at).
final class SimDestination {
  const new({
    required this.id,
    required this.lat,
    required this.lng,
    this.name,
  });

  final String id;
  final String? name;
  final double lat;
  final double lng;

  /// No coordinates in logs.
  @override
  String toString() => 'SimDestination($id)';
}

/// One entry of the catalog: what the trace is and where it goes.
final class SimTrace {
  const new({
    required this.id,
    required this.vehicle,
    required this.sampleIntervalS,
    required this.durationS,
    required this.arrivalT,
    required this.destination,
  });

  final String id;
  final VehicleKindMsg vehicle;
  final int sampleIntervalS;

  /// Trace length (trace seconds; real time = durationS / speed).
  final int durationS;

  /// Trace second the vehicle reaches the destination.
  final int arrivalT;
  final SimDestination destination;

  /// No coordinates in logs.
  @override
  String toString() => 'SimTrace($id, ${vehicle.name}, ${durationS}s)';
}
