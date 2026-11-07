// T23.3 MA01-MA05: the MapKit map of screen 2 (seam, layout D9, pin hint,
// channel mapping) without a real platform view.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_controller.dart';
import 'package:napstop/features/destination/presentation/widgets/apple_destination_map.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';
import 'package:napstop/features/destination/presentation/widgets/map_unavailable_placeholder.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../../helpers/fake_nap_map_platform.dart';
import 'destination_harness.dart';

const _noMatchVi = 'Không có ga, bến xe nào khớp "zzzz".';
const _pinHintVi =
    'Không có trong danh sách? Nhấn giữ trên bản đồ để ghim điểm đến.';
const _pinHintEn = 'Not in the list? Long-press the map to drop a pin.';

DestinationMapProps _props({
  MapPoint? point,
  int cameraRequestId = 0,
  MapPadding padding = (top: 191, left: 48, bottom: 48, right: 48),
  ValueChanged<MapPoint>? onLongPress,
  ValueChanged<MapPoint>? onPinDragEnd,
}) => DestinationMapProps(
  point: point,
  radiusM: 1000,
  cameraRequestId: cameraRequestId,
  framePadding: padding,
  onLongPress: onLongPress ?? (_) {},
  onPinDragEnd: onPinDragEnd ?? (_) {},
);

/// Top of the panel: the box the sheet sizes (its content may be scrolled).
double _panelTop(WidgetTester tester) => tester
    .getRect(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(FractionallySizedBox),
            ),
            matching: find.byType(LayoutBuilder),
          )
          .first,
    )
    .top;

void main() {
  test('MA01 iOS builds the Apple map, Android has none', () {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final ios = ProviderContainer.test();
      final builder = ios.read(destinationMapBuilderProvider);
      expect(builder, isNotNull);
      final props = _props();
      final widget = builder!(props);
      expect(widget, isA<AppleDestinationMap>());
      expect((widget as AppleDestinationMap).props, same(props));

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final android = ProviderContainer.test();
      expect(android.read(destinationMapBuilderProvider), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('MA02 the map ends at the top of the resting panel (D9)', () {
    testWidgets('fake map', (tester) async {
      final h = await pumpDestination(tester);
      final before = h.map.last.cameraRequestId;
      await typeQuery(tester, 'dong hoi');
      await tapVisible(tester, find.text('Ga Đồng Hới').first);
      final map = tester.getRect(find.byKey(kFakeMapKey));
      expect(map.top, 0);
      expect(map.bottom, closeTo(_panelTop(tester), 1));
      // The frame of the choice was asked with the padding of the resting
      // panel (nothing covered): bottom = margin only.
      final framed = h.map.builds.firstWhere(
        (p) => p.cameraRequestId == before + 1,
      );
      expect(framed.framePadding.bottom, closeTo(kCameraPaddingPt, 1));
      expect(framed.framePadding.left, kCameraPaddingPt);
      expect(framed.framePadding.top, greaterThan(64 + kCameraPaddingPt));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('placeholder, same area', (tester) async {
      await pumpDestination(tester, withMap: false);
      await typeQuery(tester, 'dong hoi');
      await tapVisible(tester, find.text('Ga Đồng Hới').first);
      final finder = find.byType(MapUnavailablePlaceholder);
      final area = tester.getRect(finder);
      expect(area.top, 0);
      expect(area.bottom, closeTo(_panelTop(tester), 1));
      expect(
        tester.widget<MapUnavailablePlaceholder>(finder).bottomPadding,
        closeTo(0, 1),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('expanded panel covers part of the map, map size kept', (
      tester,
    ) async {
      final h = await pumpDestination(tester);
      final map = tester.getRect(find.byKey(kFakeMapKey));
      // Opened at 0.55: the panel top is above the map bottom.
      expect(_panelTop(tester), lessThan(map.bottom - 1));
      expect(h.map.last.framePadding.bottom, greaterThan(kCameraPaddingPt));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('MA03 pin hint under "no match"', () {
    testWidgets('with a map', (tester) async {
      await pumpDestination(tester);
      await typeQuery(tester, 'zzzz');
      expect(find.text(_noMatchVi), findsOneWidget);
      expect(find.text(_pinHintVi), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without a map', (tester) async {
      await pumpDestination(tester, withMap: false);
      await typeQuery(tester, 'zzzz');
      expect(find.text(_noMatchVi), findsOneWidget);
      expect(find.text(_pinHintVi), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('not shown while there are results', (tester) async {
      await pumpDestination(tester);
      await typeQuery(tester, 'dong hoi');
      expect(find.text(_pinHintVi), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('MA04 props reach the native view; events reach the props', (
    tester,
  ) async {
    final platform = FakeNapMapPlatform()..install();
    final longPresses = <MapPoint>[];
    final drags = <MapPoint>[];
    final props = ValueNotifier(
      _props(onLongPress: longPresses.add, onPinDragEnd: drags.add),
    );
    addTearDown(props.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: NapThemes.of(NapThemeKind.dark),
          locale: const Locale('vi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ValueListenableBuilder(
            valueListenable: props,
            builder: (_, p, _) => AppleDestinationMap(props: p),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.created, hasLength(1));
    final params = platform.params[platform.lastId]!;
    expect(params['v'], 1);
    expect(params['initial'], kVietnamBounds.toWire());
    expect(params['centerBounds'], kCameraCenterBounds.toWire());
    expect(params['maxDistanceM'], kMaxCameraDistanceM);
    expect(params['eastLimit'], kVisibleEastLimitLng);
    expect(params['maxLngSpan'], kMaxVisibleLngSpan);
    expect(params['pinLabel'], 'Điểm đến');
    expect(params['accent'], isA<int>());
    final state0 = params['state']! as Map;
    expect(state0['pin'], isNull);
    expect(state0['pinDraggable'], isTrue);
    expect(state0['longPress'], isTrue);
    expect(state0['showsUser'], isFalse);
    expect(state0['dark'], isTrue, reason: 'app theme, not the system');
    expect(
      find.bySemanticsLabel('Bản đồ chọn điểm đến. Nhấn giữ để ghim.'),
      findsOneWidget,
    );

    // A choice: new pin + camera request.
    const p = MapPoint(17.4688, 106.6223);
    props.value = _props(
      point: p,
      cameraRequestId: 1,
      onLongPress: longPresses.add,
      onPinDragEnd: drags.add,
    );
    await tester.pump();
    final state = platform.lastState()!;
    expect(state['pin'], [p.lat, p.lng]);
    expect(state['radiusM'], 1000.0);
    expect(state['showsUser'], isFalse);
    final frames = platform.callsOf('frame');
    expect(frames, hasLength(1));
    expect(
      frames.single.arguments,
      NapMapFrame(
        bounds: frameBounds(p, 1000),
        padding: (top: 191, left: 48, bottom: 48, right: 48),
      ).toWire(),
    );

    // Same props again: nothing new sent.
    final sent = platform.calls[platform.lastId]!.length;
    props.value = _props(
      point: p,
      cameraRequestId: 1,
      onLongPress: longPresses.add,
      onPinDragEnd: drags.add,
    );
    await tester.pump();
    expect(platform.calls[platform.lastId]!.length, sent);

    await platform.emit('longPress', [16.47, 107.59]);
    await platform.emit('pinDragEnd', [17.47, 106.63]);
    await platform.emit('longPress', [99.0, 0.0]);
    expect(longPresses, [const MapPoint(16.47, 107.59)]);
    expect(drags, [const MapPoint(17.47, 106.63)]);

    await tester.pumpWidget(const SizedBox());
    expect(platform.disposed, [platform.lastId]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('MA04 controller factory seam is used', (tester) async {
    final platform = FakeNapMapPlatform()..install();
    var made = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: NapThemes.of(NapThemeKind.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppleDestinationMap(
            props: _props(),
            controllerFactory: ({required onEvent, required onChannelError}) {
              made++;
              return NapMapController(
                onEvent: onEvent,
                onChannelError: onChannelError,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(made, 1);
    expect(platform.created, hasLength(1));
    expect(platform.lastState()?['dark'], isFalse);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  group('MA05 no overflow at text scale 2.0', () {
    for (final (locale, hint) in [
      (const Locale('vi'), _pinHintVi),
      (const Locale('en'), _pinHintEn),
    ]) {
      for (final size in [const Size(320, 568), const Size(360, 640)]) {
        testWidgets('${locale.languageCode} ${size.width.toInt()}', (
          tester,
        ) async {
          await pumpDestination(tester, textScale: 2, locale: locale);
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          await typeQuery(tester, 'zzzz');
          expect(find.text(hint), findsOneWidget);
          await typeQuery(tester, 'dong hoi');
          await tapVisible(tester, find.text('Ga Đồng Hới').first);
          expect(tester.takeException(), isNull);
          final map = tester.getRect(find.byKey(kFakeMapKey));
          expect(map.bottom, closeTo(_panelTop(tester), 1));
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });
}
