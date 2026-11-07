// T23.3 Phần B (PO Q1 = A), MB01-MB05: the map card of screen 4 on iOS,
// with a fake platform-view host (no MapKit).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/trip_map_target.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_map_card.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/fake_nap_map_platform.dart';
import '../tracking_fixtures.dart';
import '../tracking_harness.dart';

const _dest = MapPoint(17.4688, 106.6223);
const _show = 'Xem bản đồ';
const _hide = 'Ẩn bản đồ';
const _myLocation = 'Vị trí của tôi';
const _simNote = 'Chuyến giả lập: bản đồ không hiện vị trí của bạn.';
final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// Reader answering [target] for every trip id; counts the reads.
class _Reader {
  new(this.target);

  final TripMapTarget? target;
  final List<String> reads = [];

  Future<TripMapTarget?> call(String tripId) async {
    reads.add(tripId);
    return target;
  }
}

FakeCoreBridge _bridge({
  SimulationMsg? simulation,
  LocationAccessMsg location = LocationAccessMsg.whileInUse,
}) => trackingBridge(
  config: configMsg(mode: AlarmModeMsg.distance, distanceThresholdM: 1000),
  simulation: simulation,
)..permissions = iosPermissions(location: location);

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<_Reader> _pump(
  WidgetTester tester, {
  FakeCoreBridge? bridge,
  TripMapTarget? target = (destination: _dest, radiusM: 1000.0),
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  final reader = _Reader(target);
  await pumpTracking(
    tester,
    bridge: bridge ?? _bridge(),
    textScale: textScale,
    size: size,
    overrides: [tripMapTargetReaderProvider.overrideWithValue(reader.call)],
  );
  return reader;
}

TripRecord _record({
  AlarmModeMsg mode = AlarmModeMsg.distance,
  int? distanceThresholdM = 1500,
  double lat = 17.4688,
}) => TripRecord(
  id: kTripId,
  destination: TripDestination(
    name: 'Ga Đồng Hới',
    lat: lat,
    lng: 106.6223,
    kind: DestinationKind.train,
  ),
  source: DestinationSource.station,
  alarm: TripAlarmChoice(
    mode: mode,
    preAlertEnabled: true,
    distanceThresholdM: distanceThresholdM,
    timeThresholdMin: mode == AlarmModeMsg.time ? 15 : null,
  ),
  vehicleHint: VehicleKindMsg.train,
  simulated: false,
  startedAtMs: kAtMs,
);

void main() {
  testWidgets('MB01 real trip: card, pin, circle, location dot, my location', (
    tester,
  ) async {
    final platform = FakeNapMapPlatform()..install();
    final reader = await _pump(tester);
    expect(reader.reads, [kTripId]);
    expect(find.text(_show), findsOneWidget);
    expect(platform.created, isEmpty, reason: 'closed by default');

    await _tapText(tester, _show);
    expect(find.text(_hide), findsOneWidget);
    expect(find.byType(TrackingMapCard), findsOneWidget);
    expect(platform.created, hasLength(1));
    final params = platform.params[platform.lastId]!;
    expect(params['state'], {
      'pin': [_dest.lat, _dest.lng],
      'radiusM': 1000.0,
      'pinDraggable': false,
      'longPress': false,
      'showsUser': true,
      'dark': false,
    });
    expect(params['initial'], frameBounds(_dest, 1000).toWire());
    expect(params['maxDistanceM'], kMaxCardCameraDistanceM);
    expect(params['eastLimit'], kVisibleEastLimitLng);
    expect(params['maxLngSpan'], kMaxVisibleLngSpan);
    expect(find.bySemanticsLabel('Bản đồ chuyến đi'), findsOneWidget);

    // First `ready`: frame the destination only, without animation.
    await platform.emit('ready');
    await tester.pump();
    var frames = platform.callsOf('frame');
    expect(frames.single.arguments, isA<Map<Object?, Object?>>());
    expect((frames.single.arguments as Map)['includeUser'], isFalse);
    expect((frames.single.arguments as Map)['animated'], isFalse);
    expect(
      (frames.single.arguments as Map)['bounds'],
      frameBounds(_dest, 1000).toWire(),
    );
    // A second `ready` frames nothing more.
    await platform.emit('ready');
    await tester.pump();
    expect(platform.callsOf('frame'), hasLength(1));

    await _tapText(tester, _myLocation);
    frames = platform.callsOf('frame');
    expect(frames, hasLength(2));
    expect((frames.last.arguments as Map)['includeUser'], isTrue);
    expect((frames.last.arguments as Map)['animated'], isTrue);

    // Hide: the view goes away.
    await _tapText(tester, _hide);
    expect(find.byType(TrackingMapCard), findsNothing);
    expect(platform.disposed, [platform.lastId]);
    expect(reader.reads, [kTripId], reason: 'row read once per trip');
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  testWidgets('MB02 simulated trip: no location dot, note, no button', (
    tester,
  ) async {
    final platform = FakeNapMapPlatform()..install();
    await _pump(
      tester,
      bridge: _bridge(
        simulation: SimulationMsg(traceAsset: 'train_hn_dh', speedFactor: 60),
      ),
    );
    await _tapText(tester, _show);
    final state = platform.params[platform.lastId]!['state']! as Map;
    expect(state['showsUser'], isFalse);
    expect(state['pinDraggable'], isFalse);
    expect(find.text(_simNote), findsOneWidget);
    expect(find.text(_myLocation), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  testWidgets('MB02 time mode: no circle', (tester) async {
    final platform = FakeNapMapPlatform()..install();
    await _pump(tester, target: (destination: _dest, radiusM: null));
    await _tapText(tester, _show);
    final state = platform.params[platform.lastId]!['state']! as Map;
    expect(state['radiusM'], isNull);
    expect(
      platform.params[platform.lastId]!['initial'],
      frameBounds(_dest, kCardFrameRadiusM).toWire(),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  testWidgets('MB02 location not allowed: no dot, no button', (tester) async {
    final platform = FakeNapMapPlatform()..install();
    await _pump(tester, bridge: _bridge(location: LocationAccessMsg.denied));
    await _tapText(tester, _show);
    final state = platform.params[platform.lastId]!['state']! as Map;
    expect(state['showsUser'], isFalse);
    expect(find.text(_myLocation), findsNothing);
    expect(find.text(_simNote), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  testWidgets('MB03 hidden app: location dot off, back on when shown', (
    tester,
  ) async {
    final platform = FakeNapMapPlatform()..install();
    await _pump(tester);
    await _tapText(tester, _show);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    // No frame is drawn while hidden: the view itself sends the change.
    expect(platform.lastState()?['showsUser'], isFalse);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.lastState()?['showsUser'], isTrue);
    expect(find.text(_myLocation), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  testWidgets('review #4: a route over screen 4 turns the location dot off', (
    tester,
  ) async {
    final platform = FakeNapMapPlatform()..install();
    await _pump(tester);
    await _tapText(tester, _show);
    expect(platform.lastState()?['showsUser'], isTrue);
    final nav = Navigator.of(tester.element(find.byType(TrackingMapCard)))
      ..push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(platform.lastState()?['showsUser'], isFalse);
    nav.pop();
    await tester.pumpAndSettle();
    expect(platform.lastState()?['showsUser'], isTrue);
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  for (final size in const [Size(360, 640), Size(320, 568)]) {
    testWidgets('MB04 text scale 2.0 ${size.width.toInt()}: no overflow', (
      tester,
    ) async {
      FakeNapMapPlatform().install();
      await _pump(tester, textScale: 2, size: size);
      await _tapText(tester, _show);
      await tester.ensureVisible(find.text(_myLocation));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TrackingMapCard)).height,
        greaterThanOrEqualTo(200),
      );
      expect(tester.getSize(find.text(_myLocation)).height, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    }, variant: _ios);
  }

  testWidgets('MB04 Android: no map button, no row read', (tester) async {
    final reader = await _pump(tester);
    expect(find.text(_show), findsNothing);
    expect(reader.reads, isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('D15 a load failure is reported once, by type only', (
    tester,
  ) async {
    final platform = FakeNapMapPlatform()..install();
    await _pump(tester);
    await _tapText(tester, _show);
    await platform.emit('loadFailed');
    await platform.emit('loadFailed');
    await tester.pumpAndSettle();
    final map = trackingCrash.errors
        .where((e) => e.reason == 'mapsLoadFailed')
        .toList();
    expect(map, hasLength(1));
    expect(map.single.error.toString(), 'NapMapLoadError');
    expect(map.single.fatal, isFalse);
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  testWidgets('MB05 no trip row: no map button, no error', (tester) async {
    final reader = await _pump(tester, target: null);
    expect(reader.reads, [kTripId]);
    expect(find.text(_show), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: _ios);

  group('trip row → card target', () {
    test('distance mode keeps the radius, other modes none', () {
      final d = tripMapTargetOf(_record())!;
      expect(d.destination, _dest);
      expect(d.radiusM, 1500);
      expect(
        tripMapTargetOf(
          _record(mode: AlarmModeMsg.time, distanceThresholdM: null),
        )!.radiusM,
        isNull,
      );
      expect(
        tripMapTargetOf(
          _record(mode: AlarmModeMsg.smart, distanceThresholdM: null),
        )!.radiusM,
        isNull,
      );
    });

    test('invalid destination: none', () {
      expect(tripMapTargetOf(_record(lat: 95)), isNull);
    });

    test('threshold outside the wire range: pin kept, no circle', () {
      for (final bad in [0, -5, 100001]) {
        final t = tripMapTargetOf(_record(distanceThresholdM: bad))!;
        expect(t.destination, _dest);
        expect(t.radiusM, isNull, reason: 'threshold $bad');
      }
      expect(
        tripMapTargetOf(_record(distanceThresholdM: 100000))!.radiusM,
        100000,
      );
    });

    test('reader: missing row or failing read gives null', () async {
      expect(await readTripMapTarget(_Repo(null), kTripId), isNull);
      expect(await readTripMapTarget(_Repo(StateError('db')), kTripId), isNull);
      final ok = await readTripMapTarget(_Repo(_record()), kTripId);
      expect(ok!.destination, _dest);
    });

    test('card height is clamped', () {
      expect(trackingMapCardHeight(400), 200);
      expect(trackingMapCardHeight(800), closeTo(256, 1e-9));
      expect(trackingMapCardHeight(1200), 320);
    });
  });
}

/// byId answers a record, null, or throws an error.
class _Repo implements TripsRepository {
  new(this.answer);

  final Object? answer;

  @override
  Future<TripRecord?> byId(String tripId) async {
    final a = answer;
    if (a is Error) {
      throw a;
    }
    return a as TripRecord?;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
