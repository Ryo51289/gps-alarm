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
import 'package:napstop/app/locales.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/db/db_providers.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import 'fake_core_bridge.dart';

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
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = bridge ?? FakeCoreBridge();
  final database = db ?? memoryDatabase();
  final fixedNow = now ?? kHarnessNow;
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
      ...overrides,
    ],
  );
  if (seed != null) {
    await seed(container);
  }
  final themeData = fontFamily == null
      ? NapThemes.of(theme)
      : NapThemes.of(theme, fontFamily: fontFamily);
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
