// T24.3 BS-C01–BS-C07: bus stops in DestinationController (lazy load,
// rows per chip, selection, failure and retry, row subtitles).
import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/bus_stop_repository.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/destination_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../../core/telemetry/telemetry_fakes.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_station_catalog.dart';

final Object _key = Object();

/// Bus stop file with [rows] (`[id, name, provinceIndex, lat, lng, routes]`).
String busStopsJson(List<List<Object>> rows) => jsonEncode({
  'schemaVersion': 1,
  'source': {
    'osmBase': '2026-11-12T01:24:05Z',
    'attribution': '© OpenStreetMap contributors',
    'licenseUrl': 'https://opendatacommons.org/licenses/odbl/1-0/',
  },
  'provinces': ['Hà Nội', 'TP. Hồ Chí Minh'],
  'stops': rows,
});

/// Synthetic bus stops: 3 "Đại học Bách khoa" (two in Hà Nội far apart,
/// one in TP. HCM), 25 "Chợ n", one with 4 routes.
final StationCatalog kFakeBusStops = buildBusStopCatalog(
  busStopsJson([
    ['n1', 'Đại học Bách khoa', 0, 21.00512, 105.84321, '03;14'],
    ['n2', 'Đại học Bách khoa', 0, 21.03, 105.84321, ''],
    ['n3', 'Đại học Bách khoa', 1, 10.772, 106.658, ''],
    ['n4', 'Kim Mã', 0, 21.031, 105.82, '09;18;22;32'],
    for (var i = 0; i < 25; i++) ['n${100 + i}', 'Chợ $i', 0, 21.0, 105.8, ''],
  ]),
);

void main() {
  late FakeCoreBridge bridge;
  late ProviderContainer container;
  late RecordingCrashSink crashSink;
  late int loads;
  late List<Future<StationCatalog> Function()> answers;
  final base = Telemetry.noop();

  setUp(() {
    bridge = FakeCoreBridge();
    crashSink = RecordingCrashSink();
    loads = 0;
    answers = [() async => kFakeBusStops];
    container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        coreBridgeProvider.overrideWithValue(bridge),
        stationCatalogProvider.overrideWith((ref) async => kTestStationCatalog),
        busStopCatalogProvider.overrideWith((ref) {
          final answer = answers[loads < answers.length ? loads : 0];
          loads++;
          return answer();
        }),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 12, 12)),
        telemetryProvider.overrideWithValue(
          Telemetry(
            analytics: base.analytics,
            crash: CrashReporter(crashSink),
            engineParams: base.engineParams,
            consent: base.consent,
          ),
        ),
      ],
    )..listen(destinationControllerFamily(_key), (_, _) {});
  });

  DestinationController ctrl() =>
      container.read(destinationControllerFamily(_key).notifier);
  DestinationState state() => container.read(destinationControllerFamily(_key));

  Future<void> settle(WidgetTester tester, [int ms = 0]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.idle();
    await tester.pump();
  }

  testWidgets('BS-C01 loaded on the 2nd letter, once', (tester) async {
    await settle(tester);
    ctrl().setQuery('b');
    await settle(tester, 200);
    expect(loads, 0);
    expect(state().busCatalog, isNull);
    ctrl().setQuery('ba');
    await settle(tester, 200);
    expect(loads, 1);
    expect(state().busCatalog?.hasValue, isTrue);
    ctrl()
      ..setQuery('bac')
      ..setFilter(DestinationFilter.busStop)
      ..setFilter(DestinationFilter.all);
    await settle(tester, 200);
    expect(loads, 1);
  });

  testWidgets('BS-C01 chip "Trạm buýt" loads without a query', (tester) async {
    await settle(tester);
    ctrl().setFilter(DestinationFilter.busStop);
    await settle(tester, 200);
    expect(loads, 1);
    expect(state().busStops, isEmpty, reason: 'no query yet');
  });

  testWidgets('BS-C02 chip all: stations as before, ≤ 5 bus stops', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('cho');
    await settle(tester, 200);
    expect(state().busStops, hasLength(5));
    ctrl().setQuery('bach khoa');
    await settle(tester, 200);
    expect(state().busStops.map((m) => m.station.id), [
      'osm:n1',
      'osm:n2',
      'osm:n3',
    ]);
    final stations = offlineResults(
      kTestStationCatalog.index,
      'bach khoa',
      DestinationFilter.all,
    );
    expect(state().offline.toString(), stations.toString());
    ctrl().setQuery('ch');
    await settle(tester, 200);
    expect(state().busStops, isEmpty, reason: '2 letters: none on chip all');
    await settle(tester, 200);
  });

  testWidgets('BS-C03 chip busStop: only bus stops, ≤ 20', (tester) async {
    await settle(tester);
    ctrl()
      ..setFilter(DestinationFilter.busStop)
      ..setQuery('cho');
    await settle(tester, 200);
    expect(state().offline, isEmpty);
    expect(state().busStops, hasLength(20));
    expect(
      state().busStops.every((m) => m.station.kind == StationKind.busStop),
      isTrue,
    );
    ctrl().setFilter(DestinationFilter.train);
    expect(state().busStops, isEmpty);
    ctrl().setFilter(DestinationFilter.coach);
    expect(state().busStops, isEmpty);
    await settle(tester, 200);
  });

  testWidgets('distances: stations then bus stops, ≤ 25 rows per call', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('cho');
    await settle(tester, 200);
    final call = bridge.distancesCalls.last;
    final rows = [...state().offline.take(20), ...state().busStops].take(25);
    expect(call.pairs, [
      for (final m in rows) ...[m.station.lat, m.station.lng],
    ]);
    expect(call.pairs.length, lessThanOrEqualTo(50));
  });

  testWidgets('BS-C04 select a bus stop; pin moves', (tester) async {
    await settle(tester);
    ctrl().setQuery('bach khoa');
    await settle(tester, 200);
    final stop = state().busStops.first.station;
    final before = state().cameraRequestId;
    ctrl().selectStation(stop);
    final sel = state().selection!;
    expect(sel.destination.kind, DestinationKind.bus);
    expect(sel.source, DestinationSource.station);
    expect(sel.destination.detail, 'Hà Nội');
    expect(sel.busStop, isTrue);
    expect(previewRadiusM(sel), 500);
    expect(state().cameraRequestId, before + 1);

    ctrl().movePin(
      MapPoint(stop.lat + 300 / 111195.08, stop.lng),
      pinnedName: 'Điểm đã ghim',
      pinnedDetail: (p, m) => 'from $p',
    );
    expect(state().selection!.busStop, isTrue);
    expect(state().selection!.destination.kind, DestinationKind.bus);
    ctrl().movePin(
      MapPoint(stop.lat + 800 / 111195.08, stop.lng),
      pinnedName: 'Điểm đã ghim',
      pinnedDetail: (p, m) => 'from $p',
    );
    expect(state().selection!.destination.kind, DestinationKind.pin);
    expect(state().selection!.busStop, isFalse);
    expect(previewRadiusM(state().selection), 1000);
    ctrl().undoPin();
    expect(state().selection!.busStop, isTrue, reason: 'undo restores it');
    await settle(tester, 200);
  });

  testWidgets('BS-C05 load failure: hidden + reported once; retry works', (
    tester,
  ) async {
    answers = [
      () => Future.error(const StationDataException('asset missing')),
      () async => kFakeBusStops,
    ];
    await settle(tester);
    ctrl().setQuery('kim ma');
    await settle(tester, 200);
    expect(state().busCatalog?.hasError, isTrue);
    expect(state().busStops, isEmpty);
    expect(state().offline, isNotEmpty, reason: 'stations still searched');
    expect(crashSink.errors, hasLength(1));
    expect(
      crashSink.errors.single.reason,
      NonFatalReason.stationCatalogLoadFailed.name,
    );
    // PRIVACY: type only.
    expect(crashSink.allText.join(' '), isNot(contains('asset missing')));
    ctrl().setQuery('kim ma ');
    await settle(tester, 200);
    expect(crashSink.errors, hasLength(1), reason: 'no second report');

    // Tapping the chip "Trạm buýt" tries again.
    ctrl().setFilter(DestinationFilter.busStop);
    await settle(tester, 200);
    expect(loads, 2);
    expect(state().busCatalog?.hasValue, isTrue);
    expect(state().busStops.map((m) => m.station.id), contains('osm:n4'));
    expect(crashSink.errors, hasLength(1));
    await settle(tester, 200);
  });

  testWidgets('BS-C05 "Thử lại" (retryBusStops) after a failure', (
    tester,
  ) async {
    answers = [
      () => Future.error(const StationDataException('x')),
      () async => kFakeBusStops,
    ];
    await settle(tester);
    ctrl()
      ..setFilter(DestinationFilter.busStop)
      ..setQuery('kim');
    await settle(tester, 200);
    expect(state().busCatalog?.hasError, isTrue);
    ctrl().retryBusStops();
    await settle(tester, 200);
    expect(state().busStops.single.station.name, 'Kim Mã');
    ctrl().retryBusStops();
    await settle(tester, 200);
    expect(loads, 2, reason: 'no reload once loaded');
  });

  testWidgets('BS-C06 two stops with the same name', (tester) async {
    await settle(tester);
    ctrl().setQuery('bach khoa');
    await settle(tester, 200);
    final [a, b, ...] = [for (final m in state().busStops) m.station];
    expect(a.name, b.name);
    ctrl().selectStation(b);
    expect(ctrl().isSelectedStation(b), isTrue);
    expect(ctrl().isSelectedStation(a), isFalse);
    await settle(tester, 200);
  });

  test('BS-C07 row subtitles', () async {
    final l = await AppLocalizations.delegate.load(const Locale('vi'));
    final stops = kFakeBusStops.dataset.stations;
    final withRoutes = stops.firstWhere((s) => s.id == 'osm:n1');
    final without = stops.firstWhere((s) => s.id == 'osm:n2');
    final four = stops.firstWhere((s) => s.id == 'osm:n4');
    expect(l.stationRowSubtitle(without, null), 'Trạm buýt · Hà Nội');
    expect(
      l.stationRowSubtitle(without, 1200),
      'Trạm buýt · Hà Nội · cách 1,2 km',
    );
    expect(
      l.stationRowSubtitle(withRoutes, null),
      'Trạm buýt · Hà Nội · tuyến 03, 14',
    );
    expect(
      l.stationRowSubtitle(withRoutes, 350),
      'Trạm buýt · Hà Nội · tuyến 03, 14 · cách 350 m',
    );
    expect(
      l.stationRowSubtitle(four, null),
      'Trạm buýt · Hà Nội · tuyến 09, 18, 22…',
    );
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      en.stationRowSubtitle(withRoutes, 350),
      'Bus stop · Hà Nội · route 03, 14 · 350 m away',
    );
    expect(routeRefsLabel(const []), isNull);
    expect(routeRefsLabel(const ['1', '2', '3']), '1, 2, 3');
  });
}
