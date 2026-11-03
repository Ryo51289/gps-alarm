// T25 U12-U16: TripConfigMsg builder and validator (T14 §6 V1-V11).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/trip_config_builder.dart';

import '../../../helpers/trip_fixtures.dart';

const _prefs = AlarmPreferences(
  soundId: 'default',
  volumePct: 80,
  rampUp: false,
  vibration: VibrationMsg.medium,
  flash: true,
);

const _draft = TripDraft(
  destination: kGaDongHoi,
  source: DestinationSource.station,
);

TripConfigMsg _config({
  AlarmModeMsg mode = AlarmModeMsg.smart,
  String tripId = 'trip-1',
  TripDraft draft = _draft,
  String? json,
}) => buildTripConfig(
  tripId: tripId,
  draft: draft,
  settings: TripSettings.defaults.copyWith(
    mode: mode,
    distanceThresholdM: 2000,
    timeThresholdMin: 20,
  ),
  prefs: _prefs,
  engineParamsJson: json,
);

void main() {
  test('U12 buildAlarmSettings per style', () {
    final ring = buildAlarmSettings(
      AlarmStyle.ringAndVibrate,
      DismissMethodMsg.swipe,
      _prefs,
    );
    expect(ring.soundId, 'default');
    expect(ring.volume, 0.8);
    expect(ring.rampUp, isFalse);
    expect(ring.vibration, VibrationMsg.medium);
    expect(ring.flash, isTrue);
    expect(ring.preferHeadphones, isFalse);
    expect(ring.dismissMethod, DismissMethodMsg.swipe);

    final vibrate = buildAlarmSettings(
      AlarmStyle.vibrateOnly,
      DismissMethodMsg.shake,
      _prefs,
    );
    expect(vibrate.volume, 0.0);
    expect(vibrate.vibration, VibrationMsg.strong);
    expect(vibrate.preferHeadphones, isFalse);
    expect(vibrate.flash, isTrue);
    expect(vibrate.dismissMethod, DismissMethodMsg.shake);

    final phones = buildAlarmSettings(
      AlarmStyle.headphonesOnly,
      DismissMethodMsg.math,
      _prefs,
    );
    expect(phones.volume, 0.8);
    expect(phones.vibration, VibrationMsg.medium);
    expect(phones.preferHeadphones, isTrue);
    expect(phones.dismissMethod, DismissMethodMsg.math);
  });

  test('U13 only the threshold of the mode', () {
    final distance = _config(mode: AlarmModeMsg.distance);
    expect(
      (distance.distanceThresholdM, distance.timeThresholdMin),
      (2000, null),
    );
    final time = _config(mode: AlarmModeMsg.time);
    expect((time.distanceThresholdM, time.timeThresholdMin), (null, 20));
    final smart = _config();
    expect((smart.distanceThresholdM, smart.timeThresholdMin), (null, null));
    expect(smart.vehicleHint, VehicleKindMsg.train);
    expect(smart.destinationName, 'Ga Đồng Hới');
    expect(smart.preAlertEnabled, isTrue);
    expect(smart.engineParamsJson, isNull);
  });

  test('U13 engineParamsJson verbatim, explicit vehicle hint kept', () {
    const json = '{"a":60.0}';
    expect(_config(json: json).engineParamsJson!.codeUnits, json.codeUnits);
    final hinted = _config(
      draft: _draft.copyWith(vehicleHint: VehicleKindMsg.coach),
    );
    expect(hinted.vehicleHint, VehicleKindMsg.coach);
  });

  test('U13 truncateDestinationName', () {
    expect(truncateDestinationName('  Ga Huế  '), 'Ga Huế');
    expect(truncateDestinationName('a' * 250), 'a' * 200);
    expect(truncateDestinationName('a' * 200), 'a' * 200);
    // An emoji at units 199-200 would be split: keep 199.
    final emoji = '${'a' * 199}\u{1F600}${'b' * 10}';
    final cut = truncateDestinationName(emoji);
    expect(cut, 'a' * 199);
    expect(cut.length, 199);
    final before = '${'a' * 198}\u{1F600}${'b' * 10}';
    expect(truncateDestinationName(before), '${'a' * 198}\u{1F600}');
  });

  test('U14 every rule, in order, without values', () {
    final ok = _config();
    expect(validateTripConfig(ok, 17.5, 106.6, null), isNull);

    String? v(
      TripConfigMsg c, {
      double lat = 17.5,
      double lng = 106.6,
      SimulationMsg? sim,
    }) => validateTripConfig(c, lat, lng, sim);

    TripConfigMsg c({
      String tripId = 'trip-1',
      String name = 'Ga',
      AlarmModeMsg mode = AlarmModeMsg.smart,
      int? distance,
      int? time,
      String soundId = 'default',
      double volume = 1,
      String? json,
    }) => TripConfigMsg(
      tripId: tripId,
      destinationName: name,
      mode: mode,
      distanceThresholdM: distance,
      timeThresholdMin: time,
      preAlertEnabled: true,
      vehicleHint: VehicleKindMsg.train,
      alarm: AlarmSettingsMsg(
        soundId: soundId,
        volume: volume,
        rampUp: true,
        vibration: VibrationMsg.strong,
        flash: false,
        preferHeadphones: false,
        dismissMethod: DismissMethodMsg.swipe,
      ),
      engineParamsJson: json,
    );

    final cases = <(String?, String)>[
      (v(c(tripId: '')), 'tripId: format'),
      (v(c(tripId: 'a b')), 'tripId: format'),
      (v(c(tripId: 'x' * 65)), 'tripId: format'),
      (v(c(name: ' \u00A0\u3000')), 'destinationName: empty'),
      (v(c(name: '\u001C')), 'destinationName: empty'),
      (v(c(name: 'x' * 201)), 'destinationName: too long'),
      (v(c(), lat: 91.5), 'destLat: out of range'),
      (v(c(), lat: double.nan), 'destLat: out of range'),
      (v(c(), lng: 180), 'destLng: out of range'),
      (v(c(), lng: double.infinity), 'destLng: out of range'),
      (v(c(mode: AlarmModeMsg.distance)), 'distanceThresholdM: required'),
      (v(c(mode: AlarmModeMsg.time)), 'timeThresholdMin: required'),
      (v(c(distance: 199)), 'distanceThresholdM: out of range'),
      (v(c(distance: 10001)), 'distanceThresholdM: out of range'),
      (v(c(time: 4)), 'timeThresholdMin: out of range'),
      (v(c(time: 61)), 'timeThresholdMin: out of range'),
      (v(c(soundId: '')), 'alarm.soundId: empty'),
      (v(c(volume: 1.01)), 'alarm.volume: out of range'),
      (v(c(volume: double.nan)), 'alarm.volume: out of range'),
      (
        v(c(), sim: SimulationMsg(traceAsset: '', speedFactor: 60)),
        'simulation.traceAsset: empty',
      ),
      (
        v(c(), sim: SimulationMsg(traceAsset: 'stub/normal', speedFactor: 0.5)),
        'simulation.speedFactor: out of range',
      ),
      (
        v(c(), sim: SimulationMsg(traceAsset: 'stub/normal', speedFactor: 601)),
        'simulation.speedFactor: out of range',
      ),
      (v(c(json: 'x' * 16385)), 'engineParamsJson: too long'),
      // Order: the first failing rule wins.
      (v(c(tripId: '', name: '')), 'tripId: format'),
      (v(c(distance: 199), lat: 91.5), 'destLat: out of range'),
    ];
    for (final (actual, expected) in cases) {
      expect(actual, expected);
      expect(actual, isNot(matches(RegExp(r'\d{2,}'))));
    }
    // Limits are accepted.
    expect(v(c(json: 'x' * 16384)), isNull);
    expect(v(c(distance: 200, time: 60), lat: -90, lng: -180), isNull);
    expect(v(c(volume: 0)), isNull);
    expect(
      v(c(), sim: SimulationMsg(traceAsset: 'stub/normal', speedFactor: 600)),
      isNull,
    );
  });

  test('U15 newTripId: UUID v4, unique', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (final rnd in [Random(1), Random.secure()]) {
      final ids = {for (var i = 0; i < 1000; i++) newTripId(rnd)};
      expect(ids, hasLength(1000));
      for (final id in ids) {
        expect(id, matches(pattern));
        expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')));
      }
    }
    expect(newTripId(), matches(pattern));
  });

  test('U16 vehicleHintFor', () {
    expect(DestinationKind.values.map(vehicleHintFor).toList(), [
      VehicleKindMsg.train,
      VehicleKindMsg.coach,
      VehicleKindMsg.bus,
      VehicleKindMsg.unknown,
      VehicleKindMsg.unknown,
    ]);
  });
}
