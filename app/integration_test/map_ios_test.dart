// T23.3 MI01-MI06, MI05b-f, MI06b-c (docs/specs/T23.3.md; MI05f added by
// the tester): the MapKit platform view on the iOS Simulator, real app, real
// channel. Debug build (NAPSTOP_DIAG: the `diag*`
// commands of Runner/Map/NapMapPlatformView.swift drive a long press and a
// pin drag and read the native state). Map tiles are not judged (the
// Simulator may have no network; `ready` then comes from the 3 s fallback).
// Skipped on Android. Logs no destination and no user location; MI05, MI05b
// and MI06b print the camera numbers they measured (public bounds, for the
// spec notes).
// By hand on a Mac:
//   flutter test integration_test/map_ios_test.dart -d <udid>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_view.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart'
    show distanceM;
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/features/tracking/presentation/tracking_screen.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_map_card.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import 'support/sim_expectations.dart';

final bool _notIos = !Platform.isIOS;

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

/// The app's providers. At tear-down the widget tree is removed FIRST, then the
/// container is disposed: a tree left mounted on a disposed container (its
/// GoRouter disposed) breaks the next file of the CI group that pumps a widget
/// ("building InheritedGoRouter" assertions, first CI run 07/11).
ProviderContainer _newContainer(WidgetTester tester, String initialLocation) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [startupLocationProvider.overrideWithValue(initialLocation)],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  return container;
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NapStopApp(flavor: AppFlavor.dev),
      ),
    );

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      return false;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

Future<void> _wait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

NapMapViewState _map(WidgetTester tester) =>
    tester.state<NapMapViewState>(find.byType(NapMapView));

MethodChannel _channel(WidgetTester tester) =>
    MethodChannel(napMapChannelName(_map(tester).viewId!));

Future<Map<Object?, Object?>> _diagState(WidgetTester tester) async {
  final r = await _channel(tester).invokeMethod<Object?>('diagState');
  return r! as Map<Object?, Object?>;
}

Future<void> _diag(WidgetTester tester, String method, MapPoint p) =>
    _channel(tester).invokeMethod<void>(method, [p.lat, p.lng]);

MapPoint _pinOf(Map<Object?, Object?> s) {
  final l = s['pin']! as List;
  return MapPoint((l[0]! as num).toDouble(), (l[1]! as num).toDouble());
}

MapBounds _visibleOf(Map<Object?, Object?> s) {
  final m = s['visible']! as Map;
  double d(String k) => (m[k]! as num).toDouble();
  return MapBounds(south: d('s'), west: d('w'), north: d('n'), east: d('e'));
}

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(DestinationScreen)));

/// Opens screen 2 and waits for the native map and its `ready`.
Future<void> _openScreen2(WidgetTester tester) async {
  final container = _newContainer(tester, AppRoutes.destination);
  await _pumpApp(tester, container);
  expect(
    await _pumpUntil(
      tester,
      () => find.byType(NapMapView).evaluate().isNotEmpty,
    ),
    isTrue,
    reason: 'no NapMapView',
  );
  expect(find.byType(UiKitView), findsOneWidget);
  expect(
    await _pumpUntil(
      tester,
      () => _map(tester).isReady,
      timeout: const Duration(seconds: 10),
    ),
    isTrue,
    reason: 'no ready within 10 s',
  );
}

/// Types [query] and taps the row [name]. The field is focused by a tap first:
/// after a choice it has no focus (the panel collapsed), and the first CI run
/// (07/11) found no row when typing into it unfocused (MI05e).
Future<void> _choose(WidgetTester tester, String query, String name) async {
  final field = find.byType(TextField);
  await tester.tap(field);
  await _wait(tester, const Duration(milliseconds: 500));
  await tester.enterText(field, query);
  expect(
    await _pumpUntil(
      tester,
      () => find.text(name).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 5),
    ),
    isTrue,
    reason:
        'no row "$name"; field text: '
        '"${tester.widget<TextField>(field).controller?.text}"',
  );
  final row = find.text(name).first;
  await tester.ensureVisible(row);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(row);
  await _wait(tester, const Duration(seconds: 2));
}

/// [p] moved [meters] north.
MapPoint _north(MapPoint p, double meters) =>
    MapPoint(p.lat + meters / 111320, p.lng);

/// Latitudes of MI05: Hoàng Sa, Khánh Hoà, Trường Sa.
const List<double> _islandLatitudes = [16.5, 12.2, 9];

/// R2-1: `frame` of a 1 km zone around [p] (screen-like padding, animated
/// like the app), then the camera is centered on [p] and shows it.
Future<void> _frameAndExpectCentered(
  WidgetTester tester,
  MapPoint p,
  String tag,
) async {
  await _channel(tester).invokeMethod<void>(
    'frame',
    NapMapFrame(
      bounds: frameBounds(p, 1000),
      padding: (top: 48, left: 48, bottom: 48, right: 48),
    ).toWire(),
  );
  await _wait(tester, const Duration(seconds: 3));
  final s = await _diagState(tester);
  final centerLng = ((s['center']! as List)[1]! as num).toDouble();
  // ignore: avoid_print, public camera numbers for the spec notes.
  print(
    '$tag framed center.lng=${centerLng.toStringAsFixed(4)} '
    'boundaryEast=${s['boundaryEast']}',
  );
  expect(centerLng, closeTo(p.lng, 0.01), reason: tag);
  expect(_visibleOf(s).contains(p), isTrue, reason: tag);
}

/// D11 invariant at the three latitudes: zoom out far beyond the range with
/// the center far east, then the visible east edge stays below 111°E.
/// Prints the public camera numbers (no user data) for the spec notes.
Future<void> _expectIslandsHidden(WidgetTester tester, String tag) async {
  for (final lat in _islandLatitudes) {
    await _diag(tester, 'diagZoomOutAt', MapPoint(lat, 112));
    await _wait(tester, const Duration(seconds: 2));
    final s = await _diagState(tester);
    final centerLng = ((s['center']! as List)[1]! as num).toDouble();
    final visible = _visibleOf(s);
    final span = visible.east - visible.west;
    // Public camera numbers for the spec notes (no user data).
    // ignore: avoid_print
    print(
      '$tag lat=$lat center.lng=${centerLng.toStringAsFixed(3)} '
      'visible.w=${visible.west.toStringAsFixed(3)} '
      'visible.e=${visible.east.toStringAsFixed(3)} '
      'distanceM=${s['distanceM']} maxDistanceM=${s['maxDistanceM']} '
      'boundaryEast=${s['boundaryEast']}',
    );
    expect(visible.east, lessThan(kIslandsWestLng), reason: '$tag lat $lat');
    expect(
      span,
      lessThanOrEqualTo(kMaxVisibleLngSpan + 0.1),
      reason: '$tag lat $lat',
    );
    expect(
      centerLng,
      lessThanOrEqualTo(centerEastLimit(span) + 0.02),
      reason: '$tag lat $lat',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MI01 screen 2 has the MapKit view and it gets ready',
    skip: _notIos,
    (tester) async {
      await _openScreen2(tester);
      final s = await _diagState(tester);
      expect(s['annotations'], 0);
      expect(s['overlays'], 0);
      expect(s['showsUser'], isFalse);
      // The first camera is centered on Vietnam (first CI run, 07/11: it
      // showed 100.8-103.2°E, center pinned to the boundary's west edge).
      final center = (s['center']! as List).cast<num>();
      // Public camera numbers for the spec notes (no user data).
      // ignore: avoid_print
      print(
        'MI01 center=${center[0].toStringAsFixed(3)},'
        '${center[1].toStringAsFixed(3)} '
        'initialCameraEnd=${s['initialCameraEnd']} '
        'applied=${s['initialCameraApplied']} '
        'events=${s['initialCameraEvents']}',
      );
      expect(center[1].toDouble(), closeTo(105.85, 0.5));
      expect(center[0].toDouble(), closeTo(15.95, 1));
      // Not timing dependent (round 7): still centered once everything
      // (D9 resize, tiles, boundary) has settled.
      await _wait(tester, const Duration(seconds: 3));
      final later = await _diagState(tester);
      final c2 = (later['center']! as List).cast<num>();
      // Public camera numbers for the spec notes (no user data).
      // ignore: avoid_print
      print(
        'MI01 later center=${c2[0].toStringAsFixed(3)},'
        '${c2[1].toStringAsFixed(3)} '
        'applied=${later['initialCameraApplied']} '
        'events=${later['initialCameraEvents']} '
        'boundaryEast=${later['boundaryEast']}',
      );
      expect(c2[1].toDouble(), closeTo(105.85, 0.5));
      expect(c2[0].toDouble(), closeTo(15.95, 1));
    },
  );

  testWidgets('MI02 long press drops a pin', skip: _notIos, (tester) async {
    await _openScreen2(tester);
    final l = _l(tester);
    const target = MapPoint(17.4688, 106.6223);
    await _diag(tester, 'diagLongPress', target);
    await _wait(tester, const Duration(seconds: 1));
    expect(
      find.text(l.destinationConfirm(l.destinationPinned)),
      findsOneWidget,
    );
    final s = await _diagState(tester);
    expect(distanceM(_pinOf(s), target), lessThanOrEqualTo(5));
    expect(s['annotations'], 1);
    expect(s['overlays'], 1);
    expect(s['radiusM'], 1000);
    expect(s['pinDraggable'], isTrue);
    expect(s['showsUser'], isFalse);
  });

  testWidgets(
    'MI03 pin drags: 300 m keeps the station, 2 km pins, undo',
    skip: _notIos,
    (tester) async {
      await _openScreen2(tester);
      final l = _l(tester);
      await _choose(tester, 'dong hoi', 'Ga Đồng Hới');
      final keep = l.destinationConfirm('Ga Đồng Hới');
      expect(find.text(keep), findsOneWidget);
      final station = _pinOf(await _diagState(tester));

      await _diag(tester, 'diagDragPin', _north(station, 300));
      await _wait(tester, const Duration(seconds: 1));
      expect(find.text(keep), findsOneWidget);
      expect(find.text(l.commonUndo), findsOneWidget);

      await _diag(tester, 'diagDragPin', _north(station, 2000));
      await _wait(tester, const Duration(seconds: 1));
      expect(
        find.text(l.destinationConfirm(l.destinationPinned)),
        findsOneWidget,
      );
      await tester.tap(find.text(l.commonUndo));
      await _wait(tester, const Duration(seconds: 1));
      expect(find.text(keep), findsOneWidget);
    },
  );

  testWidgets('MI04 choosing a station frames it and its zone', skip: _notIos, (
    tester,
  ) async {
    await _openScreen2(tester);
    await _choose(tester, 'ga ha noi', 'Ga Hà Nội');
    await _wait(tester, const Duration(seconds: 2));
    final s = await _diagState(tester);
    final station = _pinOf(s);
    final visible = _visibleOf(s);
    final zone = frameBounds(station, 1000);
    expect(visible.contains(station), isTrue);
    expect(
      visible.contains(MapPoint(zone.south, zone.west)) &&
          visible.contains(MapPoint(zone.north, zone.east)),
      isTrue,
    );
  });

  testWidgets(
    'MI05 screen 2: the camera cannot show the islands',
    skip: _notIos,
    (tester) async {
      await _openScreen2(tester);
      await _expectIslandsHidden(tester, 'MI05');
    },
  );

  testWidgets(
    'MI05b landscape view 800x300: the span limit follows the view',
    skip: _notIos,
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: NapThemes.of(NapThemeKind.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 800,
                maxHeight: 300,
                child: SizedBox(
                  width: 800,
                  height: 300,
                  child: NapMapView(
                    state: NapMapState(),
                    initial: kVietnamBounds,
                    semanticLabel: 'MI05b',
                    pinLabel: 'MI05b',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        await _pumpUntil(
          tester,
          () => _map(tester).isReady,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
      );
      // Layer 1 measures after the layout.
      await _wait(tester, const Duration(seconds: 1));
      await _expectIslandsHidden(tester, 'MI05b');
    },
  );

  testWidgets('MI05c the easternmost station can be centered', skip: _notIos, (
    tester,
  ) async {
    await _openScreen2(tester);
    // Easternmost station of the dataset (public coordinates, MW05).
    const station = MapPoint(12.90894, 109.37682);
    await _channel(tester).invokeMethod<void>(
      'frame',
      const NapMapFrame(
        bounds: MapBounds(
          south: 12.90,
          west: 109.368,
          north: 12.918,
          east: 109.386,
        ),
        padding: kNoMapPadding,
        animated: false,
      ).toWire(),
    );
    await _wait(tester, const Duration(seconds: 2));
    final s = await _diagState(tester);
    final centerLng = ((s['center']! as List)[1]! as num).toDouble();
    expect(centerLng, closeTo(station.lng, 0.01));
  });

  testWidgets(
    'MI05d zoomed out first, then framing the easternmost station (R2-1)',
    skip: _notIos,
    (tester) async {
      await _openScreen2(tester);
      // Wide span: the center boundary is lowered (layer 2).
      await _diag(tester, 'diagZoomOutAt', const MapPoint(12.9, 106));
      await _wait(tester, const Duration(seconds: 2));
      final before = await _diagState(tester);
      // ignore: avoid_print, public camera numbers for the spec notes.
      print('MI05d before boundaryEast=${before['boundaryEast']}');
      await _frameAndExpectCentered(
        tester,
        const MapPoint(12.90894, 109.37682),
        'MI05d',
      );
    },
  );

  testWidgets(
    'MI05e Ga Hà Nội, then Ga Nha Trang (animated): station in view, east '
    'edge within the limit (R3-2)',
    skip: _notIos,
    (tester) async {
      await _openScreen2(tester);
      await _choose(tester, 'ga ha noi', 'Ga Hà Nội');
      await _wait(tester, const Duration(seconds: 2));
      await _choose(tester, 'ga nha trang', 'Ga Nha Trang');
      await _wait(tester, const Duration(seconds: 3));
      final s = await _diagState(tester);
      final station = _pinOf(s);
      final visible = _visibleOf(s);
      // Public camera numbers for the spec notes (no user data).
      // ignore: avoid_print
      print(
        'MI05e visible.w=${visible.west.toStringAsFixed(3)} '
        'visible.e=${visible.east.toStringAsFixed(3)} '
        'boundaryEast=${s['boundaryEast']}',
      );
      expect(station.lng, closeTo(109.18429, 0.001));
      expect(visible.contains(station), isTrue);
      // Layer 2 resets the boundary only past 0.02° (hysteresis).
      expect(visible.east, lessThanOrEqualTo(kVisibleEastLimitLng + 0.02));
    },
  );
  // Tester T23.3 (outside the spec table): the FIRST camera, before any
  // gesture or diag command. Screen 2 opens on kVietnamBounds (height
  // 8.3-23.6°N): fitted as is into a portrait view it would span ~11.7° of
  // longitude, east edge ~111.7°E (islands). Only the starting zoom range
  // and layer 2 keep it in; nothing else measured this frame.
  testWidgets(
    'MI05f first camera of screen 2 and of an 800x300 view, no gesture: '
    'east edge below 111',
    skip: _notIos,
    (tester) async {
      await _openScreen2(tester);
      await _wait(tester, const Duration(seconds: 1));
      var s = await _diagState(tester);
      var visible = _visibleOf(s);
      // ignore: avoid_print, public camera numbers for the spec notes.
      print(
        'MI05f screen2 visible.w=${visible.west.toStringAsFixed(3)} '
        'visible.e=${visible.east.toStringAsFixed(3)} '
        'distanceM=${s['distanceM']} maxDistanceM=${s['maxDistanceM']} '
        'boundaryEast=${s['boundaryEast']}',
      );
      expect(visible.east, lessThan(kIslandsWestLng), reason: 'screen 2');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: NapThemes.of(NapThemeKind.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 800,
                maxHeight: 300,
                child: SizedBox(
                  width: 800,
                  height: 300,
                  child: NapMapView(
                    state: NapMapState(),
                    initial: kVietnamBounds,
                    semanticLabel: 'MI05f',
                    pinLabel: 'MI05f',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        await _pumpUntil(
          tester,
          () => _map(tester).isReady,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
      );
      await _wait(tester, const Duration(seconds: 1));
      s = await _diagState(tester);
      visible = _visibleOf(s);
      // ignore: avoid_print, public camera numbers for the spec notes.
      print(
        'MI05f 800x300 visible.w=${visible.west.toStringAsFixed(3)} '
        'visible.e=${visible.east.toStringAsFixed(3)} '
        'distanceM=${s['distanceM']} maxDistanceM=${s['maxDistanceM']} '
        'boundaryEast=${s['boundaryEast']}',
      );
      expect(visible.east, lessThan(kIslandsWestLng), reason: '800x300');
    },
  );

  testWidgets(
    'MI06 screen 4 card of a simulated trip: no location dot, fixed pin; '
    'MI06b islands hidden in the card',
    skip: _notIos,
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
      final container = _newContainer(tester, AppRoutes.home);
      final bridge = container.read(coreBridgeProvider);
      await cleanSlate(bridge);
      final trace = (await loadCatalog()).byId(SimTraces.trainHnDh)!;
      final tripId = _id('mi06');
      addTearDown(() async {
        if ((await bridge.currentTrip())?.config.tripId == tripId) {
          await bridge.stopTrip(tripId);
        }
      });
      await container
          .read(tripsRepositoryProvider)
          .insertStarted(
            TripRecord.started(
              id: tripId,
              draft: TripDraft(
                destination: TripDestination(
                  name: trace.destination.name ?? 'x',
                  lat: trace.destination.lat,
                  lng: trace.destination.lng,
                  kind: DestinationKind.train,
                ),
                source: DestinationSource.station,
              ),
              alarm: const TripAlarmChoice(
                mode: AlarmModeMsg.distance,
                distanceThresholdM: 1000,
                preAlertEnabled: true,
              ),
              startedAtMs: DateTime.now().millisecondsSinceEpoch,
              simulated: true,
            ),
          );
      await startSim(bridge, simConfig(tripId, trace), trace, 60);
      await _pumpApp(tester, container);
      container.read(appRouterProvider).go(AppRoutes.tracking);
      // Localizations live under MaterialApp: read them from screen 4 (first
      // CI run, 07/11: NapStopApp is above them).
      expect(
        await _pumpUntil(
          tester,
          () => find.byType(TrackingScreen).evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'no screen 4',
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(TrackingScreen)),
      );
      expect(
        await _pumpUntil(
          tester,
          () => find.text(l.trackingMapShow).evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'no map button',
      );
      await tester.ensureVisible(find.text(l.trackingMapShow));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l.trackingMapShow));
      expect(
        await _pumpUntil(
          tester,
          () =>
              find.byType(TrackingMapCard).evaluate().isNotEmpty &&
              _map(tester).isReady,
          timeout: const Duration(seconds: 10),
        ),
        isTrue,
      );
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(find.text(l.trackingMapSimulatedNote), findsOneWidget);
      final s = await _diagState(tester);
      expect(s['showsUser'], isFalse);
      expect(s['pinDraggable'], isFalse);
      expect(s['annotations'], 1);
      expect(s['overlays'], 1);
      // Review T23.3 #1: the card is a landscape view; the islands stay
      // hidden there too (MI06b numbers for the spec notes).
      await _expectIslandsHidden(tester, 'MI06b');
      // R2-1 in the card: after zooming out, framing the destination again
      // (what the card does on `ready` and after "Vị trí của tôi").
      await _frameAndExpectCentered(
        tester,
        MapPoint(trace.destination.lat, trace.destination.lng),
        'MI06c',
      );
      await bridge.stopTrip(tripId);
      await bridge.ackFinishedTrips([tripId]);
    },
  );
}
