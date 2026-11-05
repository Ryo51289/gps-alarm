// Sample destinations, records and seeding helpers (T22). Not a test file.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';

const TripDestination kGaDongHoi = TripDestination(
  name: 'Ga Đồng Hới',
  lat: 17.4783,
  lng: 106.6003,
  kind: DestinationKind.train,
  detail: 'Quảng Trị',
);

const TripDestination kGaHue = TripDestination(
  name: 'Ga Huế',
  lat: 16.4567,
  lng: 107.5781,
  kind: DestinationKind.train,
  detail: 'Huế',
);

const TripDestination kBenXeMyDinh = TripDestination(
  name: 'Bến xe Mỹ Đình',
  lat: 21.0285,
  lng: 105.7781,
  kind: DestinationKind.coach,
  detail: 'Hà Nội',
);

const TripDestination kHomeAddress = TripDestination(
  name: 'Ngõ 12 Láng Hạ',
  lat: 21.0170,
  lng: 105.8150,
  kind: DestinationKind.address,
);

const TripDestination kHometown = TripDestination(
  name: 'Ga Vinh',
  lat: 18.6796,
  lng: 105.6813,
  kind: DestinationKind.train,
  detail: 'Nghệ An',
);

const TripAlarmChoice kTime15 = TripAlarmChoice(
  mode: AlarmModeMsg.time,
  timeThresholdMin: 15,
  preAlertEnabled: true,
);

/// A started trip (no result) at [startedAtMs].
TripRecord sampleRecord({
  required String id,
  TripDestination destination = kGaDongHoi,
  TripAlarmChoice alarm = kTime15,
  VehicleKindMsg? vehicleHint,
  int startedAtMs = 1700000000000,
  bool simulated = false,
}) => TripRecord(
  id: id,
  destination: destination,
  source: DestinationSource.station,
  alarm: alarm,
  vehicleHint: vehicleHint ?? vehicleHintFor(destination.kind),
  simulated: simulated,
  startedAtMs: startedAtMs,
);

/// Seeds saved places and trips through the repositories.
Future<void> seedData(
  ProviderContainer container, {
  Map<SavedPlaceSlot, TripDestination> places = const {},
  List<TripRecord> trips = const [],
}) async {
  final placesRepo = container.read(savedPlacesRepositoryProvider);
  for (final MapEntry(key: slot, value: d) in places.entries) {
    await placesRepo.upsert(slot, d);
  }
  final tripsRepo = container.read(tripsRepositoryProvider);
  for (final t in trips) {
    await tripsRepo.insertStarted(t);
  }
}

/// W01 data: Nhà + Quê saved, two recent train trips (time 15).
Future<void> seedW01(ProviderContainer container) => seedData(
  container,
  places: const {
    SavedPlaceSlot.home: kHomeAddress,
    SavedPlaceSlot.hometown: kHometown,
  },
  trips: [
    sampleRecord(id: 'dh', startedAtMs: 20),
    sampleRecord(id: 'hue', destination: kGaHue, startedAtMs: 10),
  ],
);

/// A finished trip of the native queue (T28); defaults: on time, 498 km.
FinishedTripMsg finishedTrip(
  String id, {
  TripOutcomeMsg outcome = TripOutcomeMsg.onTime,
  int startedAtMs = 1600000000000,
  int endedAtMs = 1700000500000,
  int? alarmAtMs = 1700000400000,
  AlarmReasonMsg? alarmReason = AlarmReasonMsg.distance,
  int? dismissedAtMs = 1700000450000,
  int snoozeCount = 0,
  int travelledM = 498000,
  VehicleKindMsg vehicleGuess = VehicleKindMsg.train,
}) => FinishedTripMsg(
  tripId: id,
  outcome: outcome,
  endReason: outcome == TripOutcomeMsg.cancelled
      ? EndReasonMsg.userStop
      : EndReasonMsg.dismissed,
  endedAtMs: endedAtMs,
  startedAtMs: startedAtMs,
  alarmAtMs: alarmAtMs,
  alarmReason: alarmReason,
  dismissedAtMs: dismissedAtMs,
  snoozeCount: snoozeCount,
  travelledM: travelledM,
  vehicleGuess: vehicleGuess,
);
