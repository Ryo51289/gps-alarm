// Shared harness that pumps the whole app (router, shell, providers) with a
// fake bridge, an in-memory database and a fixed clock (T22; reused by T21,
// T23, T25-T28). Not a test file.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/db/db_providers.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';
import 'package:napstop/features/battery_guide/data/battery_guide_providers.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import 'fake_core_bridge.dart';
import 'fake_key_value_store.dart';
import 'test_battery_guides.dart';
import 'test_station_catalog.dart';

/// Default "now" of the harness: 19:30 local time ("Chào buổi tối").
final DateTime kHarnessNow = DateTime(2026, 11, 2, 19, 30);

/// Default view size (wireframe width, dpr 1).
const Size kHarnessSize = Size(390, 844);

/// Key of the RepaintBoundary around the app, for golden tests.
const Key kAppHarnessBoundaryKey = ValueKey('app-harness-boundary');

/// An in-memory [AppDatabase] for tests.
AppDatabase memoryDatabase() {
  // Every test opens its own in-memory database of the same class.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// What a test needs after [pumpAppHarness].
class AppHarness {
  const new({required this.container, required this.bridge, required this.db});

  final ProviderContainer container;
  final FakeCoreBridge bridge;
  final AppDatabase db;

  GoRouter get router => container.read(appRouterProvider);

  /// Location of the top route, pushed routes included, e.g. `/home`.
  String get location => router.state.matchedLocation;

  /// The draft received by `/alarm-settings`, or null.
  Object? get extra => router.state.extra;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);
}

/// Pumps the app like `NapStopApp` (same router, themes, localizations), at
/// [size] with dpr 1. [bridge] and [db] default to a [FakeCoreBridge] and an
/// in-memory database. [fontFamily] is for golden tests (FlutterTest font).
/// [seed] runs against the database before the first frame.
/// [stationCatalog] replaces the real dataset of screen 2 (T23).
/// [keyValueStore] holds the preferences (T25); empty by default.
/// [batteryGuides] replaces the real guides of screens 0 and 9 (T21).
/// [useApp] pumps the real `NapStopApp` instead (T28): language and theme
/// follow screen 12, and `AppBackgroundTasks` runs (history sync, native
/// language); [locale], [theme], [textScale] and [fontFamily] are then
/// ignored.
Future<AppHarness> pumpAppHarness(
  WidgetTester tester, {
  List<Override> overrides = const [],
  FakeCoreBridge? bridge,
  AppDatabase? db,
  String initialLocation = AppRoutes.home,
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1.0,
  Locale locale = const Locale('vi'),
  Size size = kHarnessSize,
  String? fontFamily,
  DateTime? now,
  Future<void> Function(ProviderContainer container)? seed,
  bool settle = true,
  Future<StationCatalog> Function()? stationCatalog,
  KeyValueStore? keyValueStore,
  Future<BatteryGuideCatalog> Function()? batteryGuides,
  bool useApp = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = bridge ?? FakeCoreBridge();
  final database = db ?? memoryDatabase();
  final fixedNow = now ?? kHarnessNow;
  final store = keyValueStore ?? FakeKeyValueStore();
  final container = ProviderContainer.test(
    retry: (_, _) => null,
    overrides: [
      coreBridgeProvider.overrideWithValue(fake),
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(database.close);
        return database;
      }),
      clockProvider.overrideWithValue(() => fixedNow),
      appRouterProvider.overrideWith((ref) {
        final router = createAppRouter(initialLocation: initialLocation);
        ref.onDispose(router.dispose);
        return router;
      }),
      // Screen 3 (T25): preferences in memory, empty unless overridden.
      keyValueStoreProvider.overrideWithValue(store),
      // Screen 0 flags (T21): the same in-memory store.
      onboardingStoreProvider.overrideWithValue(store),
      // Screen 2 (T23): the real dataset, already decoded.
      stationCatalogProvider.overrideWith(
        (ref) => stationCatalog?.call() ?? Future.value(kTestStationCatalog),
      ),
      // Screens 0 and 9 (T21): the real guides, already parsed.
      batteryGuideCatalogProvider.overrideWith(
        (ref) =>
            batteryGuides?.call() ?? Future.value(kTestBatteryGuideCatalog),
      ),
      ...overrides,
    ],
  );
  if (seed != null) {
    await seed(container);
  }
  final themeData = fontFamily == null
      ? NapThemes.of(theme)
      : NapThemes.of(theme, fontFamily: fontFamily);
  if (useApp) {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NapStopApp(flavor: AppFlavor.dev),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return AppHarness(container: container, bridge: fake, db: database);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: themeData,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kAppSupportedLocales,
        routerConfig: container.read(appRouterProvider),
        builder: (context, child) => RepaintBoundary(
          key: kAppHarnessBoundaryKey,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
  return AppHarness(container: container, bridge: fake, db: database);
}
