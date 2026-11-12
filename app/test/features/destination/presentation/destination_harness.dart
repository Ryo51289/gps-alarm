// Shared setup of the screen 2 widget tests (T23, T23.2): fake map behind
// destinationMapBuilderProvider, URL launcher recorder. Not a test file.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';
import 'package:napstop/features/destination/presentation/widgets/osm_attribution.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';

/// Key of the fake map.
const Key kFakeMapKey = ValueKey('fake-map');

/// Records what the screen gives the map.
class FakeMap {
  final List<DestinationMapProps> builds = [];

  DestinationMapProps get last => builds.last;

  Widget build(DestinationMapProps props) {
    builds.add(props);
    return const ColoredBox(key: kFakeMapKey, color: Color(0xFFDDE3EA));
  }
}

/// URLs opened through [externalUrlLauncherProvider].
class LaunchRecorder {
  final List<Uri> opened = [];
  bool result = true;

  Future<bool> launch(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

/// Everything a screen 2 test needs.
class DestinationHarness {
  const new({required this.app, required this.map, required this.launcher});

  final AppHarness app;
  final FakeMap map;
  final LaunchRecorder launcher;

  FakeCoreBridge get bridge => app.bridge;
}

/// Pumps the app on screen 1 and, with [open], pushes screen 2 on top.
/// [withMap] false = no map on this platform (the default provider, null):
/// screen 2 shows the placeholder (T23.2 D4).
Future<DestinationHarness> pumpDestination(
  WidgetTester tester, {
  bool withMap = true,
  FakeCoreBridge? bridge,
  List<Override> overrides = const [],
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1.0,
  Locale locale = const Locale('vi'),
  String? fontFamily,
  AppDatabase? db,
  Future<void> Function(ProviderContainer container)? seed,
  bool open = true,
  Future<StationCatalog> Function()? stationCatalog,
  Future<StationCatalog> Function()? busStopCatalog,
}) async {
  final map = FakeMap();
  final launcher = LaunchRecorder();
  final fake = bridge ?? FakeCoreBridge();
  final app = await pumpAppHarness(
    tester,
    bridge: fake,
    db: db,
    theme: theme,
    textScale: textScale,
    locale: locale,
    fontFamily: fontFamily,
    seed: seed,
    stationCatalog: stationCatalog,
    busStopCatalog: busStopCatalog,
    overrides: [
      if (withMap) destinationMapBuilderProvider.overrideWithValue(map.build),
      externalUrlLauncherProvider.overrideWithValue(launcher.launch),
      ...overrides,
    ],
  );
  if (open) {
    unawaited(app.router.push(AppRoutes.destination));
    await tester.pumpAndSettle();
  }
  return DestinationHarness(app: app, map: map, launcher: launcher);
}

/// Types [text] into the search field and waits past every debounce.
Future<void> typeQuery(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view, taps it and settles.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// The screen 1 element (for `context.pickDestination()`).
BuildContext homeContext(WidgetTester tester) =>
    tester.element(find.byType(HomeScreen));
