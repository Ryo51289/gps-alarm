/// Entry into a simulated trip from screen 12 (T28 §5, PRD §4). Pure Dart.
library;

import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

/// Playback speeds of PRD §4.
enum SimSpeed {
  x1(1),
  x10(10),
  x60(60);

  new(this.factor);

  final int factor;
}

/// Speed of the demo script (T41).
const SimSpeed kDefaultSimSpeed = SimSpeed.x60;

/// Hold time of the hidden entry (logo + version on screen 12).
const Duration kSimLongPress = Duration(seconds: 3);

/// Screen 3 draft of [t]: its destination (name, else [fallbackName]), kind
/// from the vehicle, `station` source (no new enum value: no database or
/// analytics wire change), hint = the trace's vehicle, no alarm choice.
TripDraft simDraft(SimTrace t, {required String fallbackName}) {
  final d = t.destination;
  final name = d.name?.trim();
  return TripDraft(
    destination: TripDestination(
      name: name == null || name.isEmpty ? fallbackName : name,
      lat: d.lat,
      lng: d.lng,
      kind: switch (t.vehicle) {
        VehicleKindMsg.train => DestinationKind.train,
        VehicleKindMsg.coach => DestinationKind.coach,
        VehicleKindMsg.bus || VehicleKindMsg.unknown => DestinationKind.bus,
      },
    ),
    source: DestinationSource.station,
    vehicleHint: t.vehicle,
  );
}

SimulationMsg simulationOf(SimTrace t, SimSpeed s) =>
    SimulationMsg(traceAsset: t.id, speedFactor: s.factor.toDouble());

/// Real time until the trace reaches its destination: ceil(arrivalT /
/// factor) seconds.
Duration simArrivalAfter(SimTrace t, SimSpeed s) =>
    Duration(seconds: (t.arrivalT / s.factor).ceil());
