// T28 SM01-SM03: simulation entry (pure parts) on the real catalog.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/alarm_settings/domain/trip_config_builder.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';
import 'package:napstop/features/simulation/domain/sim_launch.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/features/simulation/presentation/sim_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

void main() {
  final catalog = parseSimTraceCatalog(
    File('assets/sim/catalog.json').readAsStringSync(),
  );
  final vi = lookupAppLocalizations(const Locale('vi'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('SM01 train_hn_dh: draft, simulation, arrival, valid config', () {
    final t = catalog.byId(SimTraces.trainHnDh)!;
    final draft = simDraft(t, fallbackName: t.id);
    expect(draft.destination.name, 'Ga Đồng Hới');
    expect(draft.destination.kind, DestinationKind.train);
    expect(draft.destination.lat, t.destination.lat);
    expect(draft.destination.lng, t.destination.lng);
    expect(draft.source, DestinationSource.station);
    expect(draft.vehicleHint, VehicleKindMsg.train);
    expect(draft.alarm, isNull);

    final sim = simulationOf(t, SimSpeed.x60);
    expect(sim.traceAsset, 'train_hn_dh');
    expect(sim.speedFactor, 60.0);
    expect(simArrivalAfter(t, SimSpeed.x60), const Duration(seconds: 564));
    expect(simArrivalAfter(t, SimSpeed.x1), const Duration(seconds: 33790));
    expect(simArrivalAfter(t, SimSpeed.x10), const Duration(seconds: 3379));

    final config = buildTripConfig(
      tripId: 't-1',
      draft: draft,
      settings: TripSettings.defaults,
      prefs: AlarmPreferences.defaults,
      engineParamsJson: null,
    );
    expect(
      validateTripConfig(
        config,
        draft.destination.lat,
        draft.destination.lng,
        sim,
      ),
      isNull,
    );
  });

  test('SM01 every bundled trace gives a valid draft', () {
    expect(catalog.traces.map((t) => t.id), SimTraces.all);
    for (final t in catalog.traces) {
      final draft = simDraft(t, fallbackName: t.id);
      expect(draft.destination.isValid, isTrue, reason: t.id);
      expect(draft.vehicleHint, t.vehicle, reason: t.id);
      expect(draft.destination.kind.name, t.vehicle.name, reason: t.id);
    }
    const noName = SimTrace(
      id: 'x_y',
      vehicle: VehicleKindMsg.bus,
      sampleIntervalS: 5,
      durationS: 10,
      arrivalT: 9,
      destination: SimDestination(id: 'd', lat: 21, lng: 105),
    );
    expect(simDraft(noName, fallbackName: 'x_y').destination.name, 'x_y');
    expect(kDefaultSimSpeed, SimSpeed.x60);
    expect(kSimLongPress, const Duration(seconds: 3));
  });

  test('SM02 trace titles: 6 bundled ids in vi and en, unknown → null', () {
    for (final id in SimTraces.all) {
      expect(simTraceTitle(vi, id), isNotNull, reason: id);
      expect(simTraceTitle(en, id), isNotNull, reason: id);
    }
    expect(
      simTraceTitle(vi, SimTraces.coachGbPhulyOvershoot),
      'Xe khách Giáp Bát → Phủ Lý (đi quá trạm)',
    );
    expect(simTraceTitle(en, SimTraces.trainHnDh), 'Train Hanoi → Dong Hoi');
    expect(simTraceTitle(vi, 'other_trace'), isNull);
  });

  test('SM03 formatSimDuration', () {
    String f(AppLocalizations l, int s) =>
        formatSimDuration(l, Duration(seconds: s));
    expect(f(vi, 45), '45 giây');
    expect(f(vi, 563), '9 phút 23 giây');
    expect(f(vi, 33790), '9 giờ 23 phút');
    expect(f(en, 45), '45 s');
    expect(f(en, 563), '9 min 23 s');
    expect(f(en, 33790), '9 h 23 min');
    expect(f(vi, 0), '0 giây');
    expect(f(vi, 60), '1 phút 0 giây');
    expect(f(vi, 3600), '1 giờ 0 phút');
  });
}
