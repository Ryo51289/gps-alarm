// T23.3 tester: edge cases outside the spec table (docs/test-reports/T23.3.md).
// - controller: retry after a failed setState (D17 "dot off" must not be
//   lost), only the newest pending state, double attach, dispose first;
// - NapMapView lifecycle: hide/show with no location dot, state changed
//   while hidden;
// - D11 arithmetic: invariant sweep around the 3.0° knee, monotonicity;
//   every station still centerable at the largest alarm radius (10 km) on
//   the screen 2 map and in the screen 4 card;
// - trip row → card target at the edges of the threshold range;
// - native order guard (R2-1): frame() sets the center boundary for the
//   target span BEFORE setVisibleMapRect (Swift is iOS-only, not runnable
//   on Windows/WSL; MI05d/MI06c check the behaviour on CI).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_controller.dart';
import 'package:napstop/core/map/nap_map_view.dart';
import 'package:napstop/core/map/trip_map_target.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../helpers/fake_nap_map_platform.dart';
import '../../helpers/test_station_catalog.dart';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

const _dot = NapMapState(
  pin: MapPoint(17.4688, 106.6223),
  radiusM: 1000,
  showsUser: true,
);
const _noDot = NapMapState(pin: MapPoint(17.4688, 106.6223), radiusM: 1000);

/// Records calls on view [id]; the first [failures] calls throw.
List<MethodCall> _record(int id, {int failures = 0}) {
  final calls = <MethodCall>[];
  var left = failures;
  final channel = MethodChannel(napMapChannelName(id));
  _messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    if (left > 0) {
      left--;
      throw PlatformException(code: 'boom');
    }
    return null;
  });
  addTearDown(() => _messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// Span the view shows once a box is fitted into it (the R3-1 formula of
/// `MapCameraGuard.targetLngSpan`), for the station-centering check.
double _targetSpan({
  required MapBounds box,
  required double width,
  required double height,
  required MapPadding pad,
}) {
  double mercY(double lat) {
    final r = lat * math.pi / 180;
    return math.log(math.tan(math.pi / 4 + r / 2)) * 180 / math.pi;
  }

  final rectW = box.east - box.west;
  final rectH = mercY(box.north) - mercY(box.south);
  return math.max(
    rectW * width / (width - pad.left - pad.right),
    rectH * width / (height - pad.top - pad.bottom),
  );
}

TripRecord _record2({required AlarmModeMsg mode, int? distanceThresholdM}) =>
    TripRecord(
      id: 't',
      destination: const TripDestination(
        name: 'Ga Nha Trang',
        lat: 12.2482,
        lng: 109.1843,
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
      startedAtMs: 0,
    );

Widget _host(NapMapState state) => ProviderScope(
  child: MaterialApp(
    theme: NapThemes.of(NapThemeKind.light),
    locale: const Locale('vi'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SizedBox(
      width: 300,
      height: 200,
      child: NapMapView(
        state: state,
        initial: kVietnamBounds,
        semanticLabel: 'map',
        pinLabel: 'pin',
      ),
    ),
  ),
);

void _hide(WidgetTester tester) => tester.binding
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);

void _show(WidgetTester tester) => tester.binding
  ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
  ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('controller edges', () {
    test(
      'a failed setState is sent again even when equal (D17 retry)',
      () async {
        final calls = _record(3, failures: 1);
        var errors = 0;
        final c = NapMapController(
          onEvent: (_) {},
          onChannelError: () => errors++,
        )..attach(3);
        await c.setState(_noDot);
        await c.setState(_noDot);
        expect(calls.where((m) => m.method == 'setState'), hasLength(2));
        expect(calls.last.arguments, _noDot.toWire());
        expect(errors, 1);
        // Once applied, the equal state is not sent a third time.
        await c.setState(_noDot);
        expect(calls.where((m) => m.method == 'setState'), hasLength(2));
        c.dispose();
      },
    );

    test('before attach only the newest state and frame are sent', () async {
      final calls = _record(4);
      final c = NapMapController(onEvent: (_) {}, onChannelError: () {});
      await c.setState(_dot);
      await c.setState(_noDot);
      const f1 = NapMapFrame(
        bounds: MapBounds(south: 1, west: 1, north: 2, east: 2),
        padding: kNoMapPadding,
      );
      const f2 = NapMapFrame(
        bounds: MapBounds(south: 3, west: 3, north: 4, east: 4),
        padding: kNoMapPadding,
        includeUser: true,
      );
      await c.frame(f1);
      await c.frame(f2);
      c.attach(4);
      await pumpEventQueue();
      expect(calls.map((m) => m.method), ['setState', 'frame']);
      // A stale "dot on" never reaches native.
      expect((calls[0].arguments as Map)['showsUser'], isFalse);
      expect(calls[1].arguments, f2.toWire());
      c.dispose();
    });

    test(
      'a second attach is ignored; dispose before attach sends nothing',
      () async {
        final a = _record(5);
        final b = _record(6);
        final c = NapMapController(onEvent: (_) {}, onChannelError: () {})
          ..attach(5)
          ..attach(6);
        expect(c.viewId, 5);
        await c.setState(_noDot);
        expect(a, hasLength(1));
        expect(b, isEmpty);
        c.dispose();

        final d = NapMapController(onEvent: (_) {}, onChannelError: () {});
        await d.setState(_dot);
        d
          ..dispose()
          ..attach(6);
        await pumpEventQueue();
        expect(b, isEmpty);
        expect(d.isAttached, isFalse);
      },
    );
  });

  group('NapMapView lifecycle (D17)', () {
    testWidgets('no location dot: hide/show sends nothing new', (tester) async {
      final platform = FakeNapMapPlatform()..install();
      await tester.pumpWidget(_host(_noDot));
      await tester.pumpAndSettle();
      final before = platform.callsOf('setState').length;
      _hide(tester);
      await tester.pump();
      _show(tester);
      await tester.pumpAndSettle();
      expect(platform.callsOf('setState'), hasLength(before));
      expect(platform.lastState()?['showsUser'], isFalse);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('dot turned off while hidden stays off when shown', (
      tester,
    ) async {
      final platform = FakeNapMapPlatform()..install();
      final state = ValueNotifier(_dot);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: state,
          builder: (_, s, _) => _host(s),
        ),
      );
      await tester.pumpAndSettle();
      expect(platform.lastState()?['showsUser'], isTrue);
      _hide(tester);
      await tester.pump();
      expect(platform.lastState()?['showsUser'], isFalse);
      // Permission revoked while hidden (screen 4 rebuilds with no dot).
      state.value = _noDot;
      _show(tester);
      await tester.pumpAndSettle();
      expect(platform.lastState()?['showsUser'], isFalse);
      // Hiding twice in a row never turns the dot on.
      _hide(tester);
      await tester.pump();
      expect(platform.lastState()?['showsUser'], isFalse);
      _show(tester);
      await tester.pumpAndSettle();
      expect(platform.lastState()?['showsUser'], isFalse);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('disposing the view stops events and calls', (tester) async {
      final platform = FakeNapMapPlatform()..install();
      await tester.pumpWidget(_host(_dot));
      await tester.pumpAndSettle();
      final id = platform.lastId;
      await tester.pumpWidget(const SizedBox());
      expect(platform.disposed, [id]);
      final sent = platform.calls[id]!.length;
      // Lifecycle after dispose: the listener is gone, nothing sent.
      _hide(tester);
      _show(tester);
      await tester.pump();
      expect(platform.calls[id]!.length, sent);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('D11 arithmetic edges', () {
    test(
      'east edge never passes 110.9 for any span up to 8.8 (fine sweep)',
      () {
        for (var i = 1; i <= 8800; i++) {
          final span = i / 1000;
          final east = centerEastLimit(span) + span / 2;
          expect(
            east,
            lessThanOrEqualTo(kVisibleEastLimitLng + 1e-9),
            reason: '$span',
          );
        }
      },
    );

    test('knee at 3.0°: cap up to it, below the cap right after', () {
      expect(centerEastLimit(3), kCameraCenterBounds.east);
      expect(centerEastLimit(3 + 1e-6), lessThan(kCameraCenterBounds.east));
      expect(centerEastLimit(double.infinity), kCameraCenterBounds.east);
      expect(
        centerEastLimit(double.negativeInfinity),
        kCameraCenterBounds.east,
      );
      expect(centerEastLimit(double.minPositive), kCameraCenterBounds.east);
    });

    test('centerEastLimit never rises as the span grows', () {
      var previous = double.infinity;
      for (var i = 0; i <= 2000; i++) {
        final v = centerEastLimit(i / 100);
        expect(v, lessThanOrEqualTo(previous));
        previous = v;
      }
    });

    test('every station is centerable at the largest alarm radius', () {
      final stations = kTestStationCatalog.dataset.stations;
      // Screen 2 portrait map (MW07 sizes, framing padding of MA04) and the
      // screen 4 card on the smallest screen (SE: 667 × 0.32 = 213 pt).
      const views = [
        (
          w: 390.0,
          h: 531.0,
          pad: (top: 191.0, left: 48.0, bottom: 48.0, right: 48.0),
        ),
        (
          w: 343.0,
          h: 213.0,
          pad: (top: 48.0, left: 48.0, bottom: 48.0, right: 48.0),
        ),
        (
          w: 844.0,
          h: 300.0,
          pad: (top: 48.0, left: 48.0, bottom: 48.0, right: 48.0),
        ),
      ];
      final blocked = <String>[];
      for (final s in stations) {
        for (final r in [
          kMinDistanceThresholdM,
          1000,
          kMaxDistanceThresholdM,
        ]) {
          final box = frameBounds(MapPoint(s.lat, s.lng), r.toDouble());
          for (final v in views) {
            final span = _targetSpan(
              box: box,
              width: v.w,
              height: v.h,
              pad: v.pad,
            );
            final limit = math.max(
              kCameraCenterBounds.west,
              centerEastLimit(span),
            );
            if (s.lng > limit) {
              blocked.add('${s.id} r=$r ${v.w}x${v.h}');
            }
            // And the framed view keeps its east edge inside the limit.
            expect(s.lng + span / 2, lessThan(kIslandsWestLng), reason: s.id);
          }
        }
      }
      expect(blocked, isEmpty);
    });
  });

  group('trip row → card target edges', () {
    test('threshold range edges', () {
      for (final (t, want) in [
        (1, 1.0),
        (kMinDistanceThresholdM, kMinDistanceThresholdM.toDouble()),
        (kMaxDistanceThresholdM, kMaxDistanceThresholdM.toDouble()),
        (kMaxWireRadiusM.toInt(), kMaxWireRadiusM),
        (kMaxWireRadiusM.toInt() + 1, null),
        (0, null),
        (-1, null),
        (null, null),
      ]) {
        final target = tripMapTargetOf(
          _record2(mode: AlarmModeMsg.distance, distanceThresholdM: t),
        );
        expect(target, isNotNull, reason: '$t');
        expect(target!.radiusM, want, reason: '$t');
        expect(target.destination, const MapPoint(12.2482, 109.1843));
      }
    });

    test('smart mode with a stored threshold draws no circle', () {
      final target = tripMapTargetOf(
        _record2(mode: AlarmModeMsg.smart, distanceThresholdM: 1000),
      );
      expect(target?.radiusM, isNull);
      expect(target?.destination, isNotNull);
    });
  });

  test(
    'R2-1 order guard: frame() sets the boundary before moving the camera',
    () {
      final src = File('ios/Core/Sources/NapStopIOS/Map/NapMapController.swift')
          .readAsStringSync();
      final start = src.indexOf('public func frame(_ f: MapFrameWire)');
      expect(start, greaterThan(0));
      final end = src.indexOf('public func longPress(', start);
      final body = src.substring(start, end);
      final suspend = body.indexOf('boundaryUpdatesSuspended = true');
      final setBoundary = body.indexOf('setBoundaryEast(');
      final move = body.lastIndexOf('setVisibleMapRect(');
      final resume = body.indexOf('boundaryUpdatesSuspended = false');
      expect(suspend, greaterThan(0), reason: 'layer 2 suspended');
      expect(
        setBoundary,
        greaterThan(suspend),
        reason: 'boundary set after suspend',
      );
      expect(
        move,
        greaterThan(setBoundary),
        reason: 'camera moves after boundary',
      );
      expect(
        resume,
        greaterThan(move),
        reason: 'layer 2 resumed after the move',
      );
      // The boundary uses the span of the TARGET box (both axes, R3-1).
      expect(body, contains('MapCameraGuard.targetLngSpan('));
      expect(body, contains('rectHeightLng:'));
      expect(body.indexOf('targetLngSpan('), lessThan(setBoundary));
    },
  );
}
