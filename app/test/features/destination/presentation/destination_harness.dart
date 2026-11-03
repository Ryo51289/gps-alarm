// Shared setup of the screen 2 widget tests (T23): fake map, fake Places
// over MockClient, URL launcher recorder. Not a test file.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
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

/// Places answers: autocomplete and details may throw (network) or return
/// a status; [requests] records every call.
class FakePlacesHttp {
  final List<http.Request> requests = [];

  /// Suggestions as (placeId, mainText, secondaryText).
  List<(String, String, String?)> suggestions = [
    ('p1', 'Bến xe Đức Long', 'Gia Lai, Việt Nam'),
    ('p2', 'Đức Long Gia Lai', 'Pleiku, Gia Lai'),
  ];

  /// Status of autocomplete; null = 200 with [suggestions].
  int? autocompleteStatus;

  /// Thrown by autocomplete instead of answering.
  Exception? autocompleteError;

  /// Thrown by details instead of answering.
  Exception? detailsError;

  double lat = 13.9833;
  double lng = 108;

  int get autocompleteCount =>
      requests.where((r) => r.url.path.endsWith(':autocomplete')).length;

  MockClient get client => MockClient((r) async {
    requests.add(r);
    if (r.url.path.endsWith(':autocomplete')) {
      final error = autocompleteError;
      if (error != null) {
        throw error;
      }
      final status = autocompleteStatus;
      if (status != null) {
        return http.Response('{}', status);
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'suggestions': [
              for (final (id, main, secondary) in suggestions)
                {
                  'placePrediction': {
                    'placeId': id,
                    'text': {'text': main},
                    'structuredFormat': {
                      'mainText': {'text': main},
                      'secondaryText': ?(secondary == null
                          ? null
                          : {'text': secondary}),
                    },
                  },
                },
            ],
          }),
        ),
        200,
      );
    }
    final error = detailsError;
    if (error != null) {
      throw error;
    }
    return http.Response(
      jsonEncode({
        'location': {'latitude': lat, 'longitude': lng},
      }),
      200,
    );
  });
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
  const new({
    required this.app,
    required this.map,
    required this.places,
    required this.launcher,
  });

  final AppHarness app;
  final FakeMap map;
  final FakePlacesHttp places;
  final LaunchRecorder launcher;

  FakeCoreBridge get bridge => app.bridge;
}

/// Pumps the app on screen 1 and, with [open], pushes screen 2 on top.
/// [mapsKey] null = a build without a key.
Future<DestinationHarness> pumpDestination(
  WidgetTester tester, {
  String? mapsKey = 'test-key',
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
}) async {
  final map = FakeMap();
  final places = FakePlacesHttp();
  final launcher = LaunchRecorder();
  final fake =
      bridge ??
      FakeCoreBridge(
        mapsConfig: MapsConfigMsg(
          apiKey: mapsKey,
          androidPackage: 'app.napstop.dev',
          androidCertSha1: 'A9993E364706816ABA3E25717850C26C9CD0D89D',
        ),
      );
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
    overrides: [
      destinationMapBuilderProvider.overrideWithValue(map.build),
      placesHttpClientProvider.overrideWithValue(places.client),
      externalUrlLauncherProvider.overrideWithValue(launcher.launch),
      ...overrides,
    ],
  );
  if (open) {
    unawaited(app.router.push(AppRoutes.destination));
    await tester.pumpAndSettle();
  }
  return DestinationHarness(
    app: app,
    map: map,
    places: places,
    launcher: launcher,
  );
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
