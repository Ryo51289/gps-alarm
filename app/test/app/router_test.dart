// W14, W15 and the route table (T22 §3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_core_bridge.dart';
import '../helpers/trip_fixtures.dart';

void main() {
  test('route table: the 10 paths of §3.1', () {
    final router = createAppRouter();
    addTearDown(router.dispose);
    final paths = <String>{};
    void walk(List<RouteBase> routes) {
      for (final r in routes) {
        if (r is GoRoute) {
          paths.add(r.path);
        }
        walk(r.routes);
      }
    }

    walk(router.configuration.routes);
    expect(paths, {
      '/',
      AppRoutes.home,
      AppRoutes.history,
      AppRoutes.settings,
      // T28: child of /settings (= AppRoutes.tripDefaults), spec T28 §4.4.
      'trip-defaults',
      AppRoutes.onboarding,
      AppRoutes.batteryGuide,
      AppRoutes.destination,
      AppRoutes.alarmSettings,
      AppRoutes.tracking,
      AppRoutes.alarm,
      AppRoutes.overshoot,
    });
    expect(AppRoutes.history, '/trips');
    expect(AppRoutes.tripDefaults, '${AppRoutes.settings}/trip-defaults');
    expect(
      AppRoutes.destinationPick,
      '/destination?mode=$kDestinationModePick',
    );
  });

  testWidgets('W14 tabs, Back to Home, labels in semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await pumpAppHarness(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Trang chủ', 'Chuyến đi', 'Cài đặt']) {
      expect(find.text(label), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(label)), findsWidgets);
    }

    await tester.tap(find.text('Chuyến đi'));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.history);
    expect(find.text('Lịch sử chuyến đi'), findsOneWidget);
    expect(find.byTooltip('Quay lại'), findsNothing);

    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.settings);
    expect(find.text('Cài đặt chung'), findsOneWidget);

    // System Back from another tab goes to Home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);
    expect(find.text('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('full-screen routes cover the bottom navigation', (tester) async {
    // T26: screen 4 shows the running trip (without one it goes home).
    final h = await pumpAppHarness(
      tester,
      bridge: FakeCoreBridge(active: activeTrip()),
    );
    for (final (path, title) in [
      // T21: real screens 0 and 9 (first-run layout of screen 0 via go).
      (AppRoutes.onboarding, 'Để không bao giờ lỡ trạm'),
      (AppRoutes.batteryGuide, 'Giữ app chạy khi bạn ngủ'),
      (AppRoutes.destination, 'Chọn điểm đến'),
      // T26: real screen 4, titled with the destination.
      (AppRoutes.tracking, 'Ga Huế'),
      (AppRoutes.alarm, 'Báo thức'),
      (AppRoutes.overshoot, 'Đã đi quá trạm'),
    ]) {
      h.router.go(path);
      await tester.pumpAndSettle();
      expect(h.location, path);
      expect(find.text(title), findsOneWidget, reason: path);
      expect(find.byType(NavigationBar), findsNothing, reason: path);
    }
  });

  testWidgets('W15 /alarm-settings without a draft and / go to /home', (
    tester,
  ) async {
    final h = await pumpAppHarness(tester);
    h.router.go(AppRoutes.alarmSettings);
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);

    h.router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    h.router.go('/');
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.home);

    h.router.go(
      AppRoutes.alarmSettings,
      extra: const TripDraft(
        destination: kGaHue,
        source: DestinationSource.station,
      ),
    );
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.alarmSettings);
    expect(find.text('Ga Huế'), findsOneWidget);
  });

  testWidgets('pickDestination returns what screen 2 pops', (tester) async {
    final h = await pumpAppHarness(tester);
    final context = tester.element(find.text('Hôm nay bạn xuống ở đâu?'));
    final result = context.pickDestination();
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.destination);
    expect(h.router.state.uri.queryParameters['mode'], kDestinationModePick);
    h.router.pop(kGaHue);
    await tester.pumpAndSettle();
    expect(await result, kGaHue);
  });
}
