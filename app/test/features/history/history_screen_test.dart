// T28 H14-H21: screen 11 over the app harness (in-memory database, fake
// bridge, fixed clock).
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/history/presentation/history_providers.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';

/// End of November: every row of the month fits before "now".
final DateTime _now = DateTime(2026, 11, 28, 20);

int _at(int day, [int month = 11]) =>
    DateTime(2026, month, day, 8).millisecondsSinceEpoch;

const TripDestination _benXeThaiBinh = TripDestination(
  name: 'Bến xe Thái Bình',
  lat: 20.449,
  lng: 106.334,
  kind: DestinationKind.coach,
);

const TripAlarmChoice _distance2km = TripAlarmChoice(
  mode: AlarmModeMsg.distance,
  distanceThresholdM: 2000,
  preAlertEnabled: false,
);

/// A started row + its result (when [outcome] is set).
Future<void> _trip(
  ProviderContainer c,
  String id, {
  required int startedAtMs,
  TripOutcomeMsg? outcome,
  TripDestination destination = kGaDongHoi,
  TripAlarmChoice alarm = kTime15,
  int travelledM = 498000,
  int snoozeCount = 0,
  bool simulated = false,
  VehicleKindMsg guess = VehicleKindMsg.unknown,
}) async {
  final repo = c.read(tripsRepositoryProvider);
  await repo.insertStarted(
    sampleRecord(
      id: id,
      destination: destination,
      alarm: alarm,
      startedAtMs: startedAtMs,
      simulated: simulated,
    ),
  );
  if (outcome != null) {
    await repo.applyFinished(
      finishedTrip(
        id,
        outcome: outcome,
        travelledM: travelledM,
        snoozeCount: snoozeCount,
        vehicleGuess: guess,
      ),
    );
  }
}

/// H12 data (5 real November trips + 1 cancelled), plus an October trip, a
/// simulated trip, an orphan and the running trip `run`.
Future<void> _seedH14(ProviderContainer c) async {
  await _trip(c, 'n1', startedAtMs: _at(20), outcome: TripOutcomeMsg.onTime);
  await _trip(
    c,
    'n2',
    startedAtMs: _at(19),
    outcome: TripOutcomeMsg.snoozed,
    snoozeCount: 1,
    travelledM: 110000,
    destination: _benXeThaiBinh,
  );
  await _trip(
    c,
    'n3',
    startedAtMs: _at(18),
    outcome: TripOutcomeMsg.onTime,
    travelledM: 32000,
  );
  await _trip(c, 'n4', startedAtMs: _at(17), outcome: TripOutcomeMsg.missed);
  await _trip(
    c,
    'n5',
    startedAtMs: _at(16),
    outcome: TripOutcomeMsg.onTime,
    travelledM: 290000,
  );
  await _trip(
    c,
    'n6',
    startedAtMs: _at(15),
    outcome: TripOutcomeMsg.cancelled,
    travelledM: 0,
  );
  await _trip(
    c,
    'oct',
    startedAtMs: _at(26, 10),
    outcome: TripOutcomeMsg.onTime,
  );
  await _trip(
    c,
    'sim',
    startedAtMs: _at(21),
    outcome: TripOutcomeMsg.onTime,
    simulated: true,
  );
  await _trip(c, 'orphan', startedAtMs: _at(14));
  await c
      .read(tripsRepositoryProvider)
      .markUnfinishedAsUnknown(
        exceptTripId: 'run',
        startedBeforeMs: _at(15),
        endedAtMs: _at(14) + 1000,
      );
  await _trip(c, 'run', startedAtMs: _at(28));
}

const Size _tall = Size(390, 2600);

Future<AppHarness> _pump(
  WidgetTester tester, {
  FakeCoreBridge? bridge,
  Future<void> Function(ProviderContainer c)? seed = _seedH14,
  Size size = _tall,
  Locale locale = const Locale('vi'),
  double textScale = 1,
  NapThemeKind theme = NapThemeKind.light,
  List<Override> overrides = const [],
}) => pumpAppHarness(
  tester,
  bridge: bridge ?? FakeCoreBridge(active: activeTrip(tripId: 'run')),
  initialLocation: AppRoutes.history,
  now: _now,
  seed: seed,
  size: size,
  locale: locale,
  textScale: textScale,
  theme: theme,
  overrides: overrides,
);

Finder _restartButtons() => find.byTooltip('Đặt lại chuyến này');

void main() {
  testWidgets('H14 stats, badges, restart buttons, meta line (vi)', (
    tester,
  ) async {
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Lịch sử chuyến đi'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('chuyến tháng 11'), findsOneWidget);
    expect(find.text('1.428'), findsOneWidget);
    expect(find.text('km đã đi'), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);
    // onTime: n1, n3, n5, oct, sim.
    expect(find.text('Tỉnh đúng lúc'), findsNWidgets(5));
    expect(find.text('Báo lại 1 lần rồi mới dậy'), findsOneWidget);
    expect(find.text('Lỡ trạm'), findsOneWidget);
    expect(find.text('Đã dừng'), findsOneWidget);
    expect(find.text('Không rõ kết quả'), findsOneWidget);
    expect(find.text('Đang theo dõi'), findsOneWidget);
    expect(find.text('Giả lập'), findsOneWidget);
    expect(find.text('Tàu · 26/10 · 498 km'), findsOneWidget);
    // 10 rows, no restart on the simulated and the running one.
    expect(_restartButtons(), findsNWidgets(8));
    for (final id in ['sim', 'run']) {
      final tile = find.byKey(ValueKey(id));
      expect(
        find.descendant(of: tile, matching: _restartButtons()),
        findsNothing,
        reason: id,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('n1')),
        matching: _restartButtons(),
      ),
      findsOneWidget,
    );
  });

  testWidgets('H14 English', (tester) async {
    await _pump(tester, locale: const Locale('en'));
    expect(find.text('trips in November'), findsOneWidget);
    expect(find.text('1,428'), findsOneWidget);
    expect(find.text('Snoozed once, then woke up'), findsOneWidget);
    expect(find.text('Result unknown'), findsOneWidget);
    expect(find.text('Train · 10/26 · 498 km'), findsOneWidget);
  });

  testWidgets('H15 filter chips; stats unchanged', (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(NapChip, 'Xe khách'));
    await tester.pumpAndSettle();
    expect(find.text('Bến xe Thái Bình'), findsOneWidget);
    expect(find.byType(NapIconTile), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);
    expect(find.text('1.428'), findsOneWidget);

    await tester.tap(find.widgetWithText(NapChip, 'Xe buýt'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có chuyến nào loại này'), findsOneWidget);
    expect(find.byType(NapIconTile), findsNothing);

    await tester.tap(find.widgetWithText(NapChip, 'Tất cả'));
    await tester.pumpAndSettle();
    expect(find.byType(NapIconTile), findsNWidgets(10));
  });

  testWidgets('H16 "Đặt lại" opens screen 3 prefilled', (tester) async {
    final h = await _pump(
      tester,
      bridge: FakeCoreBridge(),
      seed: (c) => _trip(
        c,
        'd2',
        startedAtMs: _at(20),
        outcome: TripOutcomeMsg.onTime,
        alarm: _distance2km,
      ),
    );
    await tester.tap(_restartButtons());
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.alarmSettings);
    final draft = h.extra! as TripDraft;
    expect(draft.destination, kGaDongHoi);
    expect(draft.source, DestinationSource.recentTrip);
    expect(draft.alarm, _distance2km);
  });

  testWidgets('H17 a running trip blocks "Đặt lại"', (tester) async {
    final h = await _pump(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('n1')),
        matching: _restartButtons(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Đang có chuyến đi. Dừng chuyến đó trước khi đặt chuyến mới.'),
      findsOneWidget,
    );
    expect(h.location, AppRoutes.history);
    // Action of the snack bar → screen 4.
    await tester.tap(find.byType(SnackBarAction));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.tracking);
    // Drift closes the stream of the left screen on a zero timer.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the running row opens screen 4', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Đang theo dõi'));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.tracking);
  });

  testWidgets('review #1: a running row marked as orphan is still running', (
    tester,
  ) async {
    await _pump(
      tester,
      seed: (c) async {
        await _trip(c, 'run', startedAtMs: _at(20));
        // As if currentTrip() had answered null while its snapshot loaded.
        await c
            .read(tripsRepositoryProvider)
            .markUnfinishedAsUnknown(
              exceptTripId: null,
              startedBeforeMs: _at(21),
              endedAtMs: _at(21),
            );
      },
    );
    expect(find.text('Đang theo dõi'), findsOneWidget);
    expect(find.text('Không rõ kết quả'), findsNothing);
    expect(_restartButtons(), findsNothing);
  });

  testWidgets('review #4: no "Đặt lại" while the running trip is unknown', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(active: activeTrip(tripId: 'run'))
      ..currentTripGate = Completer<void>();
    await _pump(
      tester,
      bridge: bridge,
      seed: (c) =>
          _trip(c, 'n1', startedAtMs: _at(20), outcome: TripOutcomeMsg.onTime),
    );
    expect(find.text('Tỉnh đúng lúc'), findsOneWidget);
    expect(_restartButtons(), findsNothing);
    bridge.currentTripGate!.complete();
    await tester.pumpAndSettle();
    expect(_restartButtons(), findsOneWidget);
  });

  testWidgets('H18 empty history', (tester) async {
    await _pump(tester, bridge: FakeCoreBridge(), seed: null);
    expect(
      find.text('Chưa có chuyến nào. Chuyến đã đi sẽ hiện ở đây.'),
      findsOneWidget,
    );
    // Trips and km.
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('H18 database error + retry', (tester) async {
    var fail = true;
    await _pump(
      tester,
      bridge: FakeCoreBridge(),
      seed: null,
      overrides: [
        historyProvider.overrideWith(
          (ref) => fail
              ? Stream<List<TripRecord>>.error(StateError('db'))
              : Stream.value(const []),
        ),
      ],
    );
    expect(find.text('Không đọc được lịch sử chuyến đi.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Không đọc được lịch sử chuyến đi.'), findsNothing);
    expect(
      find.text('Chưa có chuyến nào. Chuyến đã đi sẽ hiện ở đây.'),
      findsOneWidget,
    );
  });

  testWidgets('H19 TripEndedMsg → sync → the running row gets its result', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(active: activeTrip(tripId: 'run'));
    final h = await pumpAppHarness(
      tester,
      bridge: bridge,
      initialLocation: AppRoutes.history,
      now: _now,
      size: _tall,
      seed: (c) => _trip(c, 'run', startedAtMs: _at(28)),
      useApp: true,
    );
    // The real app follows the test device language (en).
    expect(find.text('Tracking now'), findsOneWidget);
    expect(bridge.callCount('pendingFinishedTrips'), 1);
    bridge
      ..active = null
      ..pending.add(finishedTrip('run'))
      ..emit(tripEnded(tripId: 'run'));
    await tester.pumpAndSettle();
    expect(bridge.callCount('pendingFinishedTrips'), 2);
    expect(bridge.ackCalls.last, ['run']);
    expect(find.text('Tracking now'), findsNothing);
    expect(find.text('Woke up on time'), findsOneWidget);
    expect(
      (await h.read(tripsRepositoryProvider).byId('run'))!.result,
      TripOutcomeMsg.onTime,
    );
  });

  for (final locale in const [Locale('vi'), Locale('en')]) {
    for (final theme in const [NapThemeKind.light, NapThemeKind.dark]) {
      testWidgets('H20 320x568, text x2, ${locale.languageCode}, '
          '${theme.name}: no overflow, stacked stats, 44 px buttons', (
        tester,
      ) async {
        await _pump(
          tester,
          size: const Size(320, 568),
          textScale: 2,
          locale: locale,
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        // Stacked card: the three values are in one column.
        final trips = tester.getTopLeft(find.text('6'));
        final km = tester.getTopLeft(
          find.text(locale.languageCode == 'vi' ? '1.428' : '1,428'),
        );
        expect(km.dy, greaterThan(trips.dy));
        expect(km.dx, moreOrLessEquals(trips.dx));
        // Every row down to the end: no overflow, buttons >= 44 px.
        final scrollable = find.byType(Scrollable).first;
        for (var step = 0; step < 30; step++) {
          expect(tester.takeException(), isNull, reason: 'step $step');
          for (final e in find.byType(NapIconButton).evaluate()) {
            final size = (e.renderObject! as RenderBox).size;
            expect(size.width, greaterThanOrEqualTo(44));
            expect(size.height, greaterThanOrEqualTo(44));
          }
          for (final e in find.byType(NapChip).evaluate()) {
            final size = (e.renderObject! as RenderBox).size;
            expect(size.height, greaterThanOrEqualTo(44));
          }
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('H21 semantics: one card node, merged rows, labels, chips', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(
      find.bySemanticsLabel(
        '6 chuyến tháng 11, 1.428 km đã đi, 4/5 lần tỉnh đúng lúc',
      ),
      findsOneWidget,
    );
    final sim = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('sim')),
        matching: find.text('Giả lập'),
      ),
    );
    expect(sim.label, contains('Ga Đồng Hới'));
    expect(sim.label, contains('Tỉnh đúng lúc'));
    expect(sim.label, contains('Giả lập'));
    // The restart button is named by its tooltip (NapIconButton).
    final restart = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('n1')),
        matching: _restartButtons(),
      ),
    );
    expect(restart.tooltip, 'Đặt lại chuyến này');
    expect(restart.flagsCollection.isButton, isTrue);
    expect(restart.label, isNot(contains('Ga Đồng Hới')));
    final all = tester.getSemantics(find.widgetWithText(NapChip, 'Tất cả'));
    expect(all.flagsCollection.isSelected, Tristate.isTrue);
    final train = tester.getSemantics(find.widgetWithText(NapChip, 'Tàu'));
    expect(train.flagsCollection.isSelected, isNot(Tristate.isTrue));
    handle.dispose();
  });
}
