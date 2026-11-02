// U12, U14-U17 and validity rules of the shared trip types (T22 §6).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/destination/domain/station.dart';

import '../../helpers/trip_fixtures.dart';

void main() {
  test('U12 toString never prints name or coordinates', () {
    const d = TripDestination(
      name: 'Ga Đồng Hới',
      lat: 21.0285,
      lng: 105.8542,
      kind: DestinationKind.train,
      detail: 'Đồng Hới',
    );
    const draft = TripDraft(
      destination: d,
      source: DestinationSource.station,
      alarm: kTime15,
    );
    final record = TripRecord.started(
      id: 't1',
      draft: draft,
      alarm: kTime15,
      startedAtMs: 1,
    );
    const place = SavedPlace(
      slot: SavedPlaceSlot.home,
      destination: d,
      updatedAtMs: 1,
    );
    const summary = ActiveTripSummary(
      tripId: 't1',
      destinationName: 'Ga Đồng Hới',
      phase: TripPhaseMsg.tracking,
    );
    for (final text in [
      d.toString(),
      draft.toString(),
      record.toString(),
      place.toString(),
      summary.toString(),
    ]) {
      expect(text, isNot(contains('21.0')));
      expect(text, isNot(contains('105.8')));
      expect(text, isNot(contains('Đồng Hới')));
    }
  });

  test('TripDestination.isValid (T14 V2-V4) and equality', () {
    expect(kGaDongHoi.isValid, isTrue);
    TripDestination with_({
      String name = 'A',
      double lat = 0,
      double lng = 0,
    }) => TripDestination(
      name: name,
      lat: lat,
      lng: lng,
      kind: DestinationKind.pin,
    );
    expect(with_(name: '  ').isValid, isFalse);
    expect(with_(name: 'x' * 200).isValid, isTrue);
    expect(with_(name: 'x' * 201).isValid, isFalse);
    expect(with_(lat: 90.0001).isValid, isFalse);
    expect(with_(lat: -90).isValid, isTrue);
    expect(with_(lng: 180).isValid, isFalse);
    expect(with_(lng: -180).isValid, isTrue);
    expect(with_(lat: double.nan).isValid, isFalse);
    expect(with_(lng: double.infinity).isValid, isFalse);
    expect(with_(), with_());
    expect(with_().hashCode, with_().hashCode);
    expect(with_(name: 'B'), isNot(with_()));
  });

  test('TripAlarmChoice.isValid (T14 V5-V8)', () {
    TripAlarmChoice c(AlarmModeMsg mode, {int? m, int? min}) => TripAlarmChoice(
      mode: mode,
      distanceThresholdM: m,
      timeThresholdMin: min,
      preAlertEnabled: true,
    );
    expect(c(AlarmModeMsg.distance).isValid, isFalse);
    expect(c(AlarmModeMsg.distance, m: 200).isValid, isTrue);
    expect(c(AlarmModeMsg.distance, m: 199).isValid, isFalse);
    expect(c(AlarmModeMsg.distance, m: 10000).isValid, isTrue);
    expect(c(AlarmModeMsg.distance, m: 10001).isValid, isFalse);
    expect(c(AlarmModeMsg.time).isValid, isFalse);
    expect(c(AlarmModeMsg.time, min: 5).isValid, isTrue);
    expect(c(AlarmModeMsg.time, min: 61).isValid, isFalse);
    expect(c(AlarmModeMsg.smart).isValid, isTrue);
    expect(c(AlarmModeMsg.smart, m: 50).isValid, isFalse);
    expect(c(AlarmModeMsg.smart, min: 4).isValid, isFalse);
  });

  test('U14 latestPerDestination', () {
    // ~2 m away from kGaDongHoi: same destination once rounded.
    const near = TripDestination(
      name: 'Ga Đồng Hới',
      lat: 17.47831,
      lng: 106.60031,
      kind: DestinationKind.train,
    );
    // Same name, ~200 m away: a different destination.
    const far = TripDestination(
      name: 'Ga Đồng Hới',
      lat: 17.4801,
      lng: 106.6003,
      kind: DestinationKind.train,
    );
    final records = [
      sampleRecord(id: 'r6', startedAtMs: 60),
      sampleRecord(id: 'r5', destination: near, startedAtMs: 50),
      sampleRecord(id: 'r4', destination: far, startedAtMs: 40),
      sampleRecord(id: 'r3', destination: kGaHue, startedAtMs: 30),
      sampleRecord(id: 'r2', destination: kBenXeMyDinh, startedAtMs: 20),
      sampleRecord(id: 'r1', destination: kGaHue, startedAtMs: 10),
    ];
    final latest = latestPerDestination(records);
    expect(latest.map((r) => r.id), ['r6', 'r4', 'r3']);
    expect(latestPerDestination(records, limit: 10).map((r) => r.id), [
      'r6',
      'r4',
      'r3',
      'r2',
    ]);
    expect(latestPerDestination(const []), isEmpty);
    expect(kRecentTripsLimit, 3);
  });

  group('U15 TripDraft', () {
    test('fromRecord keeps destination, alarm and hint', () {
      const alarm = TripAlarmChoice(
        mode: AlarmModeMsg.time,
        timeThresholdMin: 15,
        preAlertEnabled: false,
      );
      final r = sampleRecord(
        id: 'r1',
        alarm: alarm,
        vehicleHint: VehicleKindMsg.coach,
      );
      final draft = TripDraft.fromRecord(r);
      expect(draft.source, DestinationSource.recentTrip);
      expect(draft.destination, kGaDongHoi);
      expect(draft.alarm, alarm);
      expect(draft.vehicleHint, VehicleKindMsg.coach);
    });

    test('fromRecord drops an invalid alarm', () {
      const bad = TripAlarmChoice(
        mode: AlarmModeMsg.distance,
        distanceThresholdM: 50,
        preAlertEnabled: true,
      );
      final draft = TripDraft.fromRecord(sampleRecord(id: 'r1', alarm: bad));
      expect(draft.alarm, isNull);
    });

    test('fromSavedPlace: no alarm, hint from kind', () {
      const place = SavedPlace(
        slot: SavedPlaceSlot.home,
        destination: kBenXeMyDinh,
        updatedAtMs: 1,
      );
      final draft = TripDraft.fromSavedPlace(place);
      expect(draft.source, DestinationSource.savedPlace);
      expect(draft.alarm, isNull);
      expect(draft.vehicleHint, VehicleKindMsg.coach);
      expect(
        TripDraft.fromSavedPlace(
          const SavedPlace(
            slot: SavedPlaceSlot.work,
            destination: kHomeAddress,
            updatedAtMs: 1,
          ),
        ).vehicleHint,
        VehicleKindMsg.unknown,
      );
    });

    test('copyWith and equality', () {
      const draft = TripDraft(
        destination: kGaHue,
        source: DestinationSource.station,
      );
      expect(draft.vehicleHint, VehicleKindMsg.train);
      final changed = draft.copyWith(
        alarm: kTime15,
        vehicleHint: VehicleKindMsg.bus,
      );
      expect(changed.alarm, kTime15);
      expect(changed.vehicleHint, VehicleKindMsg.bus);
      expect(changed.destination, kGaHue);
      expect(
        draft,
        const TripDraft(destination: kGaHue, source: DestinationSource.station),
      );
      // An explicit hint equal to the derived one is the same draft.
      expect(
        draft,
        const TripDraft(
          destination: kGaHue,
          source: DestinationSource.station,
          vehicleHint: VehicleKindMsg.train,
        ),
      );
      expect(changed, isNot(draft));
    });

    test('review #6: copyWith(destination) re-derives the hint', () {
      final draft = TripDraft.fromRecord(
        sampleRecord(id: 'r', vehicleHint: VehicleKindMsg.train),
      );
      const bus = TripDestination(
        name: 'Bến xe buýt Long Biên',
        lat: 21.04,
        lng: 105.85,
        kind: DestinationKind.bus,
      );
      expect(draft.copyWith(destination: bus).vehicleHint, VehicleKindMsg.bus);
      expect(
        draft
            .copyWith(destination: bus, vehicleHint: VehicleKindMsg.coach)
            .vehicleHint,
        VehicleKindMsg.coach,
      );
      // Other changes keep the explicit hint.
      expect(
        draft.copyWith(source: DestinationSource.station).vehicleHint,
        VehicleKindMsg.train,
      );
    });

    test('TripRecord.started copies the draft', () {
      const draft = TripDraft(
        destination: kGaHue,
        source: DestinationSource.places,
        vehicleHint: VehicleKindMsg.coach,
      );
      final r = TripRecord.started(
        id: 'x',
        draft: draft,
        alarm: kTime15,
        startedAtMs: 5,
        simulated: true,
      );
      expect(r.destination, kGaHue);
      expect(r.source, DestinationSource.places);
      expect(r.vehicleHint, VehicleKindMsg.coach);
      expect(r.simulated, isTrue);
      expect(r.result, isNull);
      expect(r.snoozeCount, 0);
    });
  });

  test('U16 vehicleHintFor and fromStation', () {
    expect(vehicleHintFor(DestinationKind.train), VehicleKindMsg.train);
    expect(vehicleHintFor(DestinationKind.coach), VehicleKindMsg.coach);
    expect(vehicleHintFor(DestinationKind.bus), VehicleKindMsg.bus);
    expect(vehicleHintFor(DestinationKind.address), VehicleKindMsg.unknown);
    expect(vehicleHintFor(DestinationKind.pin), VehicleKindMsg.unknown);
    expect(
      DestinationKind.fromStation(StationKind.train),
      DestinationKind.train,
    );
    expect(
      DestinationKind.fromStation(StationKind.coach),
      DestinationKind.coach,
    );
    expect(DestinationKind.fromStation(StationKind.bus), DestinationKind.bus);
    const station = Station(
      id: 'osm:n1',
      name: 'Ga Huế',
      nameAscii: 'ga hue',
      kind: StationKind.train,
      province: 'Huế',
      lat: 16.4567,
      lng: 107.5781,
    );
    expect(
      TripDestination.fromStation(station),
      const TripDestination(
        name: 'Ga Huế',
        lat: 16.4567,
        lng: 107.5781,
        kind: DestinationKind.train,
        detail: 'Huế',
      ),
    );
  });

  test('U17 displayVehicle', () {
    TripRecord r(VehicleKindMsg hint, VehicleKindMsg? guess) => TripRecord(
      id: 'r',
      destination: kGaHue,
      source: DestinationSource.station,
      alarm: kTime15,
      vehicleHint: hint,
      simulated: false,
      startedAtMs: 1,
      vehicleGuess: guess,
    );
    expect(
      r(VehicleKindMsg.train, VehicleKindMsg.bus).displayVehicle,
      VehicleKindMsg.bus,
    );
    expect(
      r(VehicleKindMsg.train, VehicleKindMsg.unknown).displayVehicle,
      VehicleKindMsg.train,
    );
    expect(r(VehicleKindMsg.train, null).displayVehicle, VehicleKindMsg.train);
    expect(
      r(VehicleKindMsg.unknown, VehicleKindMsg.unknown).displayVehicle,
      isNull,
    );
  });
}
