// T26 U07-U18: TripState → screen 4 view model (§4).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';

import '../tracking_fixtures.dart';

const int _now = kAtMs + 1000;
final _sim = SimulationMsg(traceAsset: 'train_hn_dh', speedFactor: 60);

TrackingView _view(
  TrackedTrip t, {
  int now = _now,
  List<StartRequirement> missing = const [],
  DeviceStatusMsg? device,
  String locale = 'vi',
}) => buildTrackingView(
  t,
  TrackingEnv(nowMs: now, locale: locale, missing: missing, device: device),
);

DeviceStatusMsg _device({
  int? batteryPct = 70,
  bool? charging = false,
  bool? headphones,
}) => DeviceStatusMsg(
  batteryPct: batteryPct,
  charging: charging,
  interruptionFilter: InterruptionFilterMsg.all,
  headphonesConnected: headphones,
);

void main() {
  group('U07 alarmCopyOf (T10 §10)', () {
    AlarmCopy copy(
      AlarmReasonMsg? reason, {
      int? distanceM,
      int? etaS,
      int? batteryPct,
    }) => alarmCopyOf(
      stateMsg(
        phase: TripPhaseMsg.alarming,
        alarmReason: reason,
        distanceM: distanceM,
        etaS: etaS,
        batteryPct: batteryPct,
      ),
      'vi',
    );
    const generic = AlarmCopy(AlarmCopyKind.generic);

    test('distance reasons', () {
      for (final r in [
        AlarmReasonMsg.distance,
        AlarmReasonMsg.smartDistance,
        AlarmReasonMsg.smartSlowDistance,
      ]) {
        expect(
          copy(r, distanceM: 900),
          const AlarmCopy(
            AlarmCopyKind.distance,
            distance: FormattedDistance('900', isKm: false),
          ),
          reason: r.name,
        );
        expect(copy(r), generic, reason: '${r.name} without distance');
      }
    });

    test('time reasons', () {
      for (final r in [AlarmReasonMsg.time, AlarmReasonMsg.smartTime]) {
        expect(
          copy(r, etaS: 601),
          const AlarmCopy(AlarmCopyKind.time, minutes: 11),
        );
        expect(copy(r), generic);
      }
    });

    test('battery, fixed texts, null', () {
      expect(
        copy(AlarmReasonMsg.lowBattery, batteryPct: 5),
        const AlarmCopy(AlarmCopyKind.lowBattery, percent: 5),
      );
      expect(copy(AlarmReasonMsg.lowBattery), generic);
      final fixed = {
        AlarmReasonMsg.gpsLost: AlarmCopyKind.gpsLost,
        AlarmReasonMsg.passedClosest: AlarmCopyKind.passedClosest,
        AlarmReasonMsg.overshoot: AlarmCopyKind.overshoot,
        AlarmReasonMsg.snoozeEnd: AlarmCopyKind.snoozeEnd,
        AlarmReasonMsg.timeout: AlarmCopyKind.timeout,
        AlarmReasonMsg.fallback: AlarmCopyKind.fallback,
        AlarmReasonMsg.fallbackMissed: AlarmCopyKind.fallbackMissed,
      };
      for (final MapEntry(key: r, value: kind) in fixed.entries) {
        expect(copy(r, distanceM: 900).kind, kind, reason: r.name);
      }
      expect(copy(null, distanceM: 900), generic);
      // Every reason is mapped.
      expect(fixed.length + 6, AlarmReasonMsg.values.length);
    });
  });

  test('U08 GPS lost: estimated, no speed, error, banner, tile', () {
    final v = _view(tracked(state: estimatedState()));
    expect(
      v.headline,
      const HeadlineDistance(
        FormattedDistance('148', isKm: true),
        estimated: true,
      ),
    );
    expect(v.speedKmh, isNull);
    expect(v.errorDistance, const FormattedDistance('1,2', isKm: true));
    expect(v.banners, contains(TrackingBanner.gpsLost));
    expect((v.gps, v.gpsTone), (GpsTile.lost, TileTone.warning));
    expect(v.progressEstimated, isTrue);
    expect(v.gpsAccuracy, isNull);
  });

  test('U09 real TRACKING: speed, ETA, arrival, alarm time', () {
    final s = w01State();
    final v = _view(tracked(state: s));
    expect(v.speedKmh, 58);
    expect(v.etaMinutes, 130);
    expect(v.arrivalAtMs, kAtMs + 7800000);
    expect(v.alarmAtMs, s.predictedAlarmAtMs);
    expect(v.alarmInMinutes, isNull);
    expect(v.errorDistance, isNull);
    expect(v.gpsAccuracy, const FormattedDistance('8', isKm: false));
    expect((v.progress, v.markerProgress), (0.62, 0.97));
    expect(v.banners, isEmpty);
  });

  test('U10 simulated: relative times only, never stale', () {
    final s = w01State();
    final v = _view(
      tracked(state: s, simulation: _sim),
      now: kAtMs + 3600000,
    );
    expect(v.arrivalAtMs, isNull);
    expect(v.alarmAtMs, isNull);
    expect(v.alarmInMinutes, etaMinutesOf(7200));
    expect(v.staleMinutes, isNull);
  });

  test('U11 stale view (D8 b): real trips only, > 3 min', () {
    final t = tracked(state: w01State());
    expect(_view(t, now: kAtMs + 180000).staleMinutes, isNull);
    expect(_view(t, now: kAtMs + 180001).staleMinutes, 3);
    expect(_view(t, now: kAtMs + 600000).staleMinutes, 10);
    final alarming = tracked(state: stateMsg(phase: TripPhaseMsg.alarming));
    expect(_view(alarming, now: kAtMs + 600000).staleMinutes, isNull);
  });

  test('U12 canDismiss / canStop / canPreview (D9)', () {
    TrackingView v(TripPhaseMsg phase, {bool ringing = false, double? vol}) =>
        _view(
          tracked(
            state: stateMsg(phase: phase, alarmRinging: ringing),
            config: configMsg(alarm: alarmMsg(volume: vol ?? 0.8)),
          ),
        );
    final cases = [
      (v(TripPhaseMsg.alarming, ringing: true), false),
      (v(TripPhaseMsg.alarming), true),
      (v(TripPhaseMsg.snoozed), true),
      (v(TripPhaseMsg.overshot, ringing: true), false),
      (v(TripPhaseMsg.overshot), true),
      (v(TripPhaseMsg.tracking), false),
    ];
    for (final (i, (view, dismiss)) in cases.indexed) {
      expect(view.canDismiss, dismiss, reason: 'case $i');
      expect(view.canStop, isTrue, reason: 'case $i');
    }
    expect(v(TripPhaseMsg.ended).canStop, isFalse);
    expect(v(TripPhaseMsg.acquiring).canPreview, isTrue);
    expect(v(TripPhaseMsg.tracking).canPreview, isTrue);
    expect(v(TripPhaseMsg.tracking, vol: 0).canPreview, isFalse);
    for (final p in [
      TripPhaseMsg.alarming,
      TripPhaseMsg.snoozed,
      TripPhaseMsg.overshot,
    ]) {
      expect(v(p).canPreview, isFalse, reason: p.name);
    }
  });

  test('U13 GPS tile', () {
    (GpsTile, FormattedDistance?) gps(
      TripStateMsg s, [
      List<StartRequirement> missing = const [],
    ]) {
      final v = _view(tracked(state: s), missing: missing);
      return (v.gps, v.gpsAccuracy);
    }

    expect(
      gps(stateMsg(locationCause: AvailabilityCauseMsg.permissionRevoked)).$1,
      GpsTile.noPermission,
    );
    expect(
      gps(stateMsg(), [StartRequirement.precise]).$1,
      GpsTile.noPermission,
    );
    expect(
      gps(stateMsg(locationCause: AvailabilityCauseMsg.servicesOff)).$1,
      GpsTile.servicesOff,
    );
    expect(
      gps(stateMsg(), [StartRequirement.locationServices]).$1,
      GpsTile.servicesOff,
    );
    expect(gps(stateMsg(distanceErrorM: 8)), (
      GpsTile.good,
      const FormattedDistance('8', isKm: false),
    ));
    expect(gps(stateMsg(gps: GpsStatusMsg.lost)).$1, GpsTile.lost);
    expect(gps(stateMsg(gps: GpsStatusMsg.noFixYet)).$1, GpsTile.searching);
  });

  test('U14 battery tile', () {
    TrackingView v(
      TripStateMsg s, {
      DeviceStatusMsg? device,
      bool sim = false,
    }) => _view(
      tracked(state: s, simulation: sim ? _sim : null),
      device: device,
    );
    final charging = v(
      stateMsg(batteryPct: 30, batteryRisk: true),
      device: _device(charging: true),
    );
    expect(
      (charging.batteryNote, charging.batteryTone),
      (BatteryTileNote.charging, TileTone.success),
    );
    final risk = v(stateMsg(batteryPct: 30, batteryRisk: true));
    expect(
      (risk.batteryNote, risk.batteryTone),
      (BatteryTileNote.risk, TileTone.danger),
    );
    for (final (choice, note) in [
      (BatteryChoiceMsg.maxSaving, BatteryTileNote.maxSaving),
      (BatteryChoiceMsg.alarmAt5, BatteryTileNote.alarmAt5),
      (BatteryChoiceMsg.alarmEarlier, BatteryTileNote.alarmEarlier),
    ]) {
      final c = v(
        stateMsg(batteryPct: 30, batteryRisk: true, batteryChoice: choice),
      );
      expect((c.batteryNote, c.batteryTone), (note, TileTone.neutral));
    }
    expect(
      v(stateMsg(batteryChoice: BatteryChoiceMsg.alarmAt5)).batteryNotePct,
      5,
    );
    final low = v(stateMsg(batteryPct: 4));
    expect(
      (low.batteryNote, low.batteryTone),
      (BatteryTileNote.low, TileTone.danger),
    );
    expect(v(stateMsg(batteryPct: 60)).batteryNote, BatteryTileNote.enough);
    final sim = v(stateMsg(), device: _device(), sim: true);
    expect((sim.batteryPct, sim.batteryNote), (70, BatteryTileNote.none));
  });

  test('U15 headphones tile', () {
    TrackingView v({required bool? h, required bool only}) => _view(
      tracked(
        config: configMsg(alarm: alarmMsg(preferHeadphones: only)),
      ),
      device: _device(headphones: h),
    );
    expect(
      (
        v(h: true, only: true).headphones,
        v(h: true, only: true).headphonesTone,
      ),
      (HeadphonesTile.connectedPreferred, TileTone.success),
    );
    expect(v(h: true, only: false).headphones, HeadphonesTile.connected);
    expect(
      (
        v(h: false, only: true).headphones,
        v(h: false, only: true).headphonesTone,
      ),
      (HeadphonesTile.notConnectedSpeaker, TileTone.warning),
    );
    expect(v(h: false, only: false).headphones, HeadphonesTile.notConnected);
    for (final only in [true, false]) {
      final u = v(h: null, only: only);
      expect(u.headphones, HeadphonesTile.unknownShowStyle);
      expect(
        u.style,
        only ? AlarmStyleKind.headphonesOnly : AlarmStyleKind.ring,
      );
    }
    expect(
      _view(tracked()).headphones,
      HeadphonesTile.unknownShowStyle,
      reason: 'no device status yet',
    );
  });

  group('U16 banners (§4.4)', () {
    test('order: permission, fallback, gpsLost', () {
      final v = _view(
        tracked(
          state: stateMsg(
            locationCause: AvailabilityCauseMsg.permissionRevoked,
            fallbackStatus: FallbackStatusMsg.failed,
            isEstimated: true,
            gps: GpsStatusMsg.lost,
            distanceM: 5000,
          ),
        ),
      );
      expect(v.banners, [
        TrackingBanner.locationPermission,
        TrackingBanner.fallbackFailed,
        TrackingBanner.gpsLost,
      ]);
    });

    test('simulated: no fallbackFailed', () {
      final v = _view(
        tracked(
          state: stateMsg(fallbackStatus: FallbackStatusMsg.failed),
          simulation: _sim,
        ),
      );
      expect(v.banners, isEmpty);
    });

    test('noGps: neverAcquired or 120 s of ACQUIRING', () {
      final s = stateMsg(
        phase: TripPhaseMsg.acquiring,
        gps: GpsStatusMsg.noFixYet,
      );
      expect(_view(tracked(state: s, neverAcquired: true)).banners, [
        TrackingBanner.noGps,
      ]);
      final shortly = _view(tracked(state: s, acquiringSinceMs: _now - 119999));
      expect(shortly.banners, isEmpty);
      expect(shortly.gpsTone, TileTone.neutral);
      final long = _view(tracked(state: s, acquiringSinceMs: _now - 120000));
      expect(long.banners, [TrackingBanner.noGps]);
      expect(long.gpsTone, TileTone.warning);
    });

    test('batteryRisk hides batteryLow', () {
      expect(
        _view(tracked(state: stateMsg(batteryRisk: true, batteryPct: 30)))
            .banners,
        [TrackingBanner.batteryRisk],
      );
      expect(
        _view(tracked(state: stateMsg(batteryPct: 4, batteryRisk: true)))
            .banners,
        [TrackingBanner.batteryRisk],
      );
      expect(_view(tracked(state: stateMsg(batteryPct: 4))).banners, [
        TrackingBanner.batteryLow,
      ]);
      expect(
        _view(
          tracked(state: stateMsg(batteryPct: 4)),
          device: _device(charging: true),
        ).banners,
        isEmpty,
        reason: 'charging',
      );
      expect(
        _view(
          tracked(simulation: _sim),
          device: _device(batteryPct: 4),
        ).banners,
        isEmpty,
        reason: 'simulated: the phone level does not count',
      );
      expect(_view(tracked(), device: _device(batteryPct: 4)).banners, [
        TrackingBanner.batteryLow,
      ], reason: 'real: the phone level counts');
    });

    test('ALARMING: no gpsLost banner', () {
      final v = _view(
        tracked(
          state: stateMsg(
            phase: TripPhaseMsg.alarming,
            isEstimated: true,
            gps: GpsStatusMsg.lost,
          ),
        ),
      );
      expect(v.banners, isEmpty);
    });

    test('services off and missing permission from the env', () {
      final v = _view(
        tracked(),
        missing: [StartRequirement.location, StartRequirement.locationServices],
      );
      expect(v.banners, [
        TrackingBanner.locationPermission,
        TrackingBanner.locationServices,
      ]);
    });
  });

  test('U17 wantsBatterySheet (D10)', () {
    bool wants(TripPhaseMsg phase, {BatteryChoiceMsg? choice}) => _view(
      tracked(
        state: stateMsg(phase: phase, batteryRisk: true, batteryChoice: choice),
      ),
    ).wantsBatterySheet;
    expect(wants(TripPhaseMsg.tracking), isTrue);
    expect(wants(TripPhaseMsg.acquiring), isTrue);
    expect(wants(TripPhaseMsg.alarming), isFalse);
    expect(
      wants(TripPhaseMsg.tracking, choice: BatteryChoiceMsg.maxSaving),
      isFalse,
    );
  });

  test('U18 params from engineParamsJson (D11)', () {
    AlarmSettingsParams p(String? json) =>
        _view(tracked(config: configMsg(engineParamsJson: json))).params;
    final a = p('{"gpsLostAlarmEtaS":900,"smartTargetS":900}');
    expect((a.gpsLostAlarmEtaS, a.smartTargetS), (900, 900));
    expect(p('{"gpsLostAlarmEtaS":299}').gpsLostAlarmEtaS, 1200);
    expect(p('{"gpsLostAlarmEtaS":3601}').gpsLostAlarmEtaS, 1200);
    expect(p('{"gpsLostAlarmEtaS":3600}').gpsLostAlarmEtaS, 3600);
    expect(p(null), AlarmSettingsParams.defaults);
    expect(AlarmSettingsParams.defaults.gpsLostAlarmEtaS, 1200);
  });

  test('headlines by phase', () {
    expect(
      _view(tracked(state: stateMsg(phase: TripPhaseMsg.acquiring))).headline,
      const HeadlineAcquiring(),
    );
    expect(
      _view(tracked(state: stateMsg())).headline,
      const HeadlineAcquiring(),
      reason: 'TRACKING without a distance',
    );
    expect(
      _view(
        tracked(
          state: stateMsg(
            phase: TripPhaseMsg.alarming,
            alarmReason: AlarmReasonMsg.distance,
            alarmRinging: true,
            distanceM: 900,
          ),
        ),
      ).headline,
      const HeadlineAlarm(
        AlarmCopy(
          AlarmCopyKind.distance,
          distance: FormattedDistance('900', isKm: false),
        ),
        ringing: true,
        remaining: FormattedDistance('900', isKm: false),
      ),
    );
    expect(
      _view(
        tracked(
          state: stateMsg(
            phase: TripPhaseMsg.snoozed,
            snoozeUntilMs: _now + 45000,
          ),
        ),
      ).headline,
      const HeadlineSnoozed(45000),
    );
    expect(
      _view(
        tracked(
          state: stateMsg(phase: TripPhaseMsg.overshot, overshootPastM: 1350),
        ),
      ).headline,
      const HeadlineOvershoot(
        ringing: false,
        past: FormattedDistance('1,4', isKm: true),
      ),
    );
  });
}
