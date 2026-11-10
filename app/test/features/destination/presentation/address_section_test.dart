// T23.5 AS-W01..AS-W05: the address section of screen 2 (iOS, map on).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_point.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/data/trip_start_reporter.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/presentation/widgets/osm_attribution.dart';

import 'address_controller_test.dart' show FakeAddressClient;
import 'destination_harness.dart';

const _header = 'Địa chỉ · Apple Maps';
const _disclosure =
    'Nội dung bạn gõ được gửi tới Apple để tìm địa chỉ. '
    'NapStop không gửi vị trí của bạn.';

CompleteReply _ok(int gen) => CompleteReply(
  gen: gen,
  status: AddressStatus.ok,
  items: const [
    AddressSuggestion(title: 'Nguyễn Trãi', subtitle: 'Thanh Xuân, Hà Nội'),
    AddressSuggestion(title: 'Phố Nguyễn Trãi', subtitle: ''),
    AddressSuggestion(title: 'Đường Nguyễn Trãi', subtitle: 'Quận 5'),
  ],
);

Future<DestinationHarness> _pump(
  WidgetTester tester,
  FakeAddressClient client,
) => pumpDestination(
  tester,
  overrides: [addressSearchClientProvider.overrideWithValue(client)],
);

/// Types [text] and waits out the debounce; no settle: the loading line
/// spins for as long as the fake client has not answered.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

Future<void> _answer(WidgetTester tester, FakeAddressClient client) async {
  client.completes.last.done.complete(_ok(client.completes.last.gen));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AS-W01 section under the OSM line, disclosure, 3 rows', (
    tester,
  ) async {
    final client = FakeAddressClient();
    await _pump(tester, client);
    await _type(tester, 'nguyen trai');
    await _answer(tester, client);
    expect(find.text(_header), findsOneWidget);
    expect(find.text(_disclosure), findsOneWidget);
    expect(find.byKey(const ValueKey('address-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('address-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('address-2')), findsOneWidget);
    expect(find.text('Địa chỉ'), findsOneWidget); // fallback subtitle
    expect(find.text('Tìm ga, bến xe, địa chỉ…'), findsOneWidget);
    final headerY = tester.getTopLeft(find.text(_header)).dy;
    final rows = find.byType(OsmAttribution);
    if (rows.evaluate().isNotEmpty) {
      expect(headerY, greaterThan(tester.getTopLeft(rows).dy));
    }
  });

  testWidgets('AS-W02 picking a row frames it and collapses the panel', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _type(tester, 'nguyen trai');
    await _answer(tester, client);
    final camera = h.map.last.cameraRequestId;
    await tester.ensureVisible(find.byKey(const ValueKey('address-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('address-1')));
    await tester.pump();
    expect(find.text('Đang lấy vị trí…'), findsOneWidget);
    client.resolves.single.done.complete(
      const ResolveReply(
        status: AddressStatus.ok,
        point: MapPoint(21, 105.8),
        country: 'VN',
      ),
    );
    await tester.pumpAndSettle();
    expect(h.map.last.point, const MapPoint(21, 105.8));
    expect(h.map.last.cameraRequestId, camera + 1);
    expect(find.text('Chọn Phố Nguyễn Trãi'), findsOneWidget);
  });

  testWidgets('AS-W03 state lines', (tester) async {
    final client = FakeAddressClient();
    await _pump(tester, client);
    await _type(tester, 'nguyen trai');
    expect(find.text('Đang tìm địa chỉ…'), findsOneWidget);
    client.completes.last.done.complete(
      CompleteReply(
        gen: client.completes.last.gen,
        status: AddressStatus.network,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Không có mạng. Vẫn tìm được ga, bến xe.'),
      findsOneWidget,
    );
    expect(find.text(_disclosure), findsOneWidget);
    await _type(tester, 'nguyen trai 2');
    client.completes.last.done.complete(
      CompleteReply(gen: client.completes.last.gen, status: AddressStatus.ok),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy địa chỉ nào.'), findsOneWidget);
    await _type(tester, 'nguyen trai 23');
    client.completes.last.done.complete(
      CompleteReply(
        gen: client.completes.last.gen,
        status: AddressStatus.failed,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không tìm được địa chỉ lúc này.'), findsOneWidget);
  });

  testWidgets('AS-W04 without a client nothing is shown (Android)', (
    tester,
  ) async {
    await pumpDestination(tester);
    await _type(tester, 'nguyen trai');
    expect(find.text(_header), findsNothing);
    expect(find.text(_disclosure), findsNothing);
    expect(find.text('Tìm ga, bến xe…'), findsOneWidget);
  });

  testWidgets('AS-W05 outside area and failure snack bars', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _type(tester, 'nguyen trai');
    await _answer(tester, client);
    final before = h.map.last.point;
    await tester.ensureVisible(find.byKey(const ValueKey('address-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('address-0')));
    await tester.pump();
    client.resolves.last.done.complete(
      const ResolveReply(
        status: AddressStatus.ok,
        point: MapPoint(16.5, 111.6),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('NapStop chưa hỗ trợ điểm đến ở khu vực này.'),
      findsOneWidget,
    );
    expect(h.map.last.point, before);
    await tester.tap(find.byKey(const ValueKey('address-0')));
    await tester.pump();
    client.resolves.last.done.complete(
      const ResolveReply(status: AddressStatus.failed),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Không lấy được vị trí của địa chỉ này. Thử lại.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'AS-W07 confirming an address opens screen 3 with places/address',
    (tester) async {
      final client = FakeAddressClient();
      final h = await _pump(tester, client);
      await _type(tester, 'nguyen trai');
      await _answer(tester, client);
      await tester.ensureVisible(find.byKey(const ValueKey('address-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('address-0')));
      await tester.pump();
      client.resolves.single.done.complete(
        const ResolveReply(
          status: AddressStatus.ok,
          point: MapPoint(21, 105.8),
          country: 'VN',
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Chọn Nguyễn Trãi'));
      expect(h.app.location, AppRoutes.alarmSettings);
      final draft = h.app.extra! as TripDraft;
      expect(draft.source, DestinationSource.places);
      expect(draft.destination.kind, DestinationKind.address);
      expect(draft.destination.detail, 'Thanh Xuân, Hà Nội');
      expect(draft.vehicleHint, VehicleKindMsg.unknown);
      // The analytics event of this choice carries two tags and no text.
      final event = DestinationSelectedEvent(
        source: destSourceTagOf(draft.source),
        kind: DestKindTag.address,
      );
      expect(event.toParameters(), {'source': 'places', 'kind': 'address'});
    },
  );

  testWidgets('AS-W06 small screen, big text, dark: no overflow', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = FakeAddressClient();
    await pumpDestination(
      tester,
      textScale: 2,
      theme: NapThemeKind.dark,
      overrides: [addressSearchClientProvider.overrideWithValue(client)],
    );
    await _type(tester, 'nguyen trai');
    await _answer(tester, client);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(_header));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text(_header)),
      matchesSemantics(label: _header, isHeader: true),
    );
  });
}
