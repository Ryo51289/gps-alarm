// T27 W01–W10: screen 8 after the alarm was dismissed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm/data/maps_launcher.dart';

import '../../../core/telemetry/telemetry_fakes.dart';
import '../../../helpers/app_harness.dart';
import '../../../helpers/trip_fixtures.dart';
import '../helpers/alarm_fakes.dart';

const _dongHoiUri =
    'https://www.google.com/maps/dir/?api=1&destination=17.478300%2C106.600300';

/// Started one hour before the harness "now" (auto-open allowed).
TripRecord _recent({bool simulated = false}) => sampleRecord(
  id: 't-1',
  startedAtMs: kHarnessNow
      .subtract(const Duration(hours: 1))
      .millisecondsSinceEpoch,
  simulated: simulated,
);

void main() {
  late FakeMapsLauncher maps;
  late RecordingAnalyticsSink analytics;

  Future<AppHarness> pump(
    WidgetTester tester, {
    String location = '/overshoot?trip=t-1&past=1234',
    TripRecord? record,
    bool seedRecord = true,
    Locale locale = const Locale('vi'),
    Size size = kHarnessSize,
    double textScale = 1,
  }) {
    maps = FakeMapsLauncher();
    final (telemetry, sink) = recordingTelemetry();
    analytics = sink;
    return pumpAppHarness(
      tester,
      initialLocation: location,
      locale: locale,
      size: size,
      textScale: textScale,
      overrides: [
        mapsLauncherProvider.overrideWithValue(maps.call),
        telemetryProvider.overrideWithValue(telemetry),
      ],
      seed: seedRecord
          ? (c) => c
                .read(tripsRepositoryProvider)
                .insertStarted(record ?? sampleRecord(id: 't-1'))
          : null,
    );
  }

  List<Map<String, Object>> events(String name) => [
    for (final (n, p) in analytics.events)
      if (n == name) p,
  ];

  testWidgets('W01 layout, dark on a light phone, a11y guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await pump(tester);
    expect(h.location, AppRoutes.overshoot);
    expect(find.text('ĐÃ QUA ĐIỂM ĐẾN'), findsOneWidget);
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Đã qua 1,2 km'), findsOneWidget);
    expect(find.text('Đã tắt báo thức'), findsOneWidget);
    expect(find.text('Đã dừng theo dõi chuyến này'), findsOneWidget);
    expect(find.text('Chỉ đường quay lại'), findsOneWidget);
    expect(find.text('Về trang chủ'), findsOneWidget);
    expect(find.text('Bạn đã đi quá điểm đến'), findsNothing);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.backgroundColor, const Color(0xFF0F1115));
    // Old trip (2023): no auto-open.
    expect(maps.opened, isEmpty);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  for (final locale in const [Locale('vi'), Locale('en')]) {
    testWidgets('W02 320×568, text ×2: no overflow, scrolls to the buttons '
        '($locale)', (tester) async {
      await pump(
        tester,
        locale: locale,
        size: const Size(320, 568),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final home = locale.languageCode == 'vi' ? 'Về trang chủ' : 'Go to home';
      await tester.scrollUntilVisible(
        find.text(home),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(home).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('W03 no past: generic line, no "Đã qua"', (tester) async {
    await pump(tester, location: '/overshoot?trip=t-1');
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Bạn đã đi quá điểm đến'), findsOneWidget);
    expect(find.textContaining('Đã qua '), findsNothing);
  });

  testWidgets('W04 no history row: generic title, no directions', (
    tester,
  ) async {
    final h = await pump(
      tester,
      location: '/overshoot?trip=t-1&past=1200&open=1',
      seedRecord: false,
    );
    expect(find.text('Bạn đã đi quá điểm đến'), findsOneWidget);
    expect(find.text('Đã qua 1,2 km'), findsOneWidget);
    expect(find.text('Chỉ đường quay lại'), findsNothing);
    expect(maps.opened, isEmpty);
    await tester.tap(find.text('Về trang chủ'));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W05 directions: URI, telemetry, double tap once', (
    tester,
  ) async {
    await pump(tester);
    maps.gate = Completer<void>();
    await tester.tap(find.text('Chỉ đường quay lại'));
    await tester.tap(find.text('Chỉ đường quay lại'));
    await tester.pump();
    maps.gate!.complete();
    await tester.pumpAndSettle();
    expect(maps.opened.map((u) => u.toString()), [_dongHoiUri]);
    expect(events('overshoot_action'), [
      {'action': 'open_maps', 'simulated': 0},
    ]);
    maps.gate = null;
    await tester.tap(find.text('Chỉ đường quay lại'));
    await tester.pumpAndSettle();
    expect(maps.opened, hasLength(2));
  });

  testWidgets('W06 launcher fails: SnackBar; a throw reports the type only', (
    tester,
  ) async {
    await pump(tester);
    maps.result = false;
    await tester.tap(find.text('Chỉ đường quay lại'));
    await tester.pumpAndSettle();
    expect(
      find.text('Không mở được Google Maps. Thử lại sau giây lát.'),
      findsOneWidget,
    );

    final reported = ReportedErrors();
    addTearDown(reported.restore);
    maps.error = PlatformException(code: 'x', message: _dongHoiUri);
    await tester.tap(find.text('Chỉ đường quay lại'));
    await tester.pumpAndSettle();
    reported.restore();
    expect(reported.texts, hasLength(1));
    expect(reported.texts.single, contains('PlatformException'));
    for (final secret in ['17.4783', '106.6003', 'google.com', 'Đồng Hới']) {
      expect(reported.texts.single, isNot(contains(secret)));
    }
    expect(
      find.text('Không mở được Google Maps. Thử lại sau giây lát.'),
      findsOneWidget,
    );
  });

  testWidgets('W07 open=1: Maps once after the first frame, not on rebuilds', (
    tester,
  ) async {
    await pump(
      tester,
      location: '/overshoot?trip=t-1&past=1234&open=1',
      record: _recent(),
    );
    expect(maps.opened.map((u) => u.toString()), [_dongHoiUri]);
    for (final size in const [Size(400, 800), Size(800, 400), kHarnessSize]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
    }
    expect(maps.opened, hasLength(1));
  });

  testWidgets('W07 open=1 for a trip started 49 h ago: no auto-open', (
    tester,
  ) async {
    await pump(
      tester,
      location: '/overshoot?trip=t-1&open=1',
      record: sampleRecord(
        id: 't-1',
        startedAtMs: kHarnessNow
            .subtract(const Duration(hours: 49))
            .millisecondsSinceEpoch,
      ),
    );
    expect(find.text('Chỉ đường quay lại'), findsOneWidget);
    expect(maps.opened, isEmpty);
  });

  testWidgets('W08 Back and "Về trang chủ" → /home, dismiss logged once', (
    tester,
  ) async {
    final h = await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(events('overshoot_action'), [
      {'action': 'dismiss', 'simulated': 0},
    ]);

    h.router.go('/overshoot?trip=t-1&past=10');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Về trang chủ'));
    await tester.tap(find.text('Về trang chủ'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(events('overshoot_action'), hasLength(2));
  });

  testWidgets('W09 simulated trip: note and simulated = 1', (tester) async {
    await pump(tester, record: sampleRecord(id: 't-1', simulated: true));
    expect(
      find.text('Chuyến giả lập: đường đi tính từ vị trí thật của máy'),
      findsOneWidget,
    );
    await tester.tap(find.text('Chỉ đường quay lại'));
    await tester.pumpAndSettle();
    expect(events('overshoot_action'), [
      {'action': 'open_maps', 'simulated': 1},
    ]);
  });

  testWidgets('W10 bad queries redirect to /home', (tester) async {
    final h = await pump(tester, location: AppRoutes.home);
    for (final bad in [
      '/overshoot?trip=a%2Fb',
      '/overshoot',
      '/overshoot?trip=',
      '/alarm',
      '/alarm?trip=a%20b',
    ]) {
      h.router.go(bad);
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.home, reason: bad);
    }
  });
}
