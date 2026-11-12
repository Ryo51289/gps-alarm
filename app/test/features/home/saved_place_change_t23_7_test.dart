// T23.7: changing a saved place ("Công ty", "Nhà", "Quê") through the real
// screen 2. Picking for a slot reads "Lưu vào <slot>"; Back with a pending
// choice asks "Lưu vào <slot>?" (Lưu / Bỏ, dismissed = stay).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_point.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/home/presentation/widgets/saved_place_tile.dart';

import '../../helpers/trip_fixtures.dart';
import '../destination/presentation/address_controller_test.dart'
    show FakeAddressClient;
import '../destination/presentation/destination_a11y_test.dart'
    show selectDongHoi;
import '../destination/presentation/destination_harness.dart';
import '../destination/presentation/destination_screen_test.dart'
    show gaDongHoi;

Finder _tile(SavedPlaceSlot slot) =>
    find.byWidgetPredicate((w) => w is SavedPlaceTile && w.slot == slot);

const Map<SavedPlaceSlot, TripDestination> _seed = {
  SavedPlaceSlot.home: kHomeAddress,
  SavedPlaceSlot.hometown: kHometown,
  SavedPlaceSlot.work: kBenXeMyDinh,
};

const Map<SavedPlaceSlot, String> _slotLabel = {
  SavedPlaceSlot.home: 'Nhà',
  SavedPlaceSlot.hometown: 'Quê',
  SavedPlaceSlot.work: 'Công ty',
};

const TripDestination _address = TripDestination(
  name: 'Phố Nguyễn Trãi',
  lat: 21,
  lng: 105.8,
  kind: DestinationKind.address,
  detail: 'Thanh Xuân, Hà Nội',
);

final Finder _dialog = find.byType(AlertDialog);
final Finder _back = find.byTooltip('Quay lại');

/// [client] null = no address search (station tests: an unanswered address
/// request would keep `pumpAndSettle` busy).
Future<DestinationHarness> _pump(
  WidgetTester tester,
  FakeAddressClient? client, {
  Map<SavedPlaceSlot, TripDestination> places = _seed,
  Locale locale = const Locale('vi'),
  String? fontFamily,
}) => pumpDestination(
  tester,
  open: false,
  locale: locale,
  fontFamily: fontFamily,
  overrides: [addressSearchClientProvider.overrideWithValue(client)],
  seed: (c) => seedData(c, places: places),
);

/// Long press on [slot] > "Đổi địa điểm": screen 2 picks for [slot].
Future<void> _openChange(
  WidgetTester tester,
  DestinationHarness h,
  SavedPlaceSlot slot,
) async {
  await tester.longPress(_tile(slot));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Đổi địa điểm'));
  await tester.pumpAndSettle();
  expect(h.app.location, AppRoutes.destination);
}

/// Types a query, answers it, taps the address row and resolves it; the
/// confirm button then reads [label].
Future<void> _pickAddress(
  WidgetTester tester,
  FakeAddressClient client, {
  String label = 'Lưu vào Công ty',
}) async {
  await tester.enterText(find.byType(TextField), 'nguyen trai');
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
  client.completes.last.done.complete(
    CompleteReply(
      gen: client.completes.last.gen,
      status: AddressStatus.ok,
      items: const [
        AddressSuggestion(
          title: 'Phố Nguyễn Trãi',
          subtitle: 'Thanh Xuân, Hà Nội',
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final row = find.byKey(const ValueKey('address-0'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pump();
  client.resolves.last.done.complete(
    const ResolveReply(
      status: AddressStatus.ok,
      point: MapPoint(21, 105.8),
      country: 'VN',
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(label), findsOneWidget);
}

Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(_back);
  await tester.pumpAndSettle();
}

/// Back arrow with a pending address for work: the dialog is open.
Future<void> _toDialog(
  WidgetTester tester,
  DestinationHarness h,
  FakeAddressClient client,
) async {
  await _openChange(tester, h, SavedPlaceSlot.work);
  await _pickAddress(tester, client);
  await _tapBack(tester);
  expect(_dialog, findsOneWidget);
}

Future<void> _expectSaved(
  DestinationHarness h,
  WidgetTester tester,
  SavedPlaceSlot slot,
  TripDestination expected,
) async {
  expect(h.app.location, AppRoutes.home);
  final saved = await h.app.read(savedPlacesRepositoryProvider).get(slot);
  expect(saved?.destination, expected);
  expect(
    find.descendant(of: _tile(slot), matching: find.text(expected.name)),
    findsOneWidget,
  );
}

/// The other slots still hold their seed.
Future<void> _expectOthersUnchanged(
  DestinationHarness h,
  SavedPlaceSlot changed,
) async {
  final repo = h.app.read(savedPlacesRepositoryProvider);
  for (final slot in SavedPlaceSlot.values) {
    if (slot != changed) {
      expect((await repo.get(slot))?.destination, _seed[slot], reason: '$slot');
    }
  }
}

/// `NapThemes` caches its `ThemeData` per (kind, font family), and the
/// platform (page transitions, hence the iOS back swipe) is fixed when a
/// theme is built. The iOS tests use their own cache key so they never get
/// a theme built earlier for Android (fonts are not loaded in widget tests,
/// the family name only matters as a key).
const String _iosThemeKey = 'T23.7-ios';

/// Pumps with the platform set to iOS (reset after the test).
Future<DestinationHarness> _pumpIos(
  WidgetTester tester,
  FakeAddressClient client,
) {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  return _pump(tester, client, fontFamily: _iosThemeKey);
}

/// iOS edge swipe from the left edge across most of the screen.
Future<void> _edgeSwipe(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.dragFrom(
    Offset(2, size.height / 2),
    Offset(size.width * 0.8, 0),
  );
  await tester.pumpAndSettle();
}

/// Picks Ga Đồng Hới, then taps the "Phố Nguyễn Trãi" address row and
/// leaves its resolve unanswered: the selection is still the station.
Future<void> _stationThenSlowAddress(
  WidgetTester tester,
  FakeAddressClient client,
) async {
  await tester.enterText(find.byType(TextField), 'dong hoi');
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
  for (final c in client.completes) {
    if (!c.done.isCompleted) {
      c.done.complete(CompleteReply(gen: c.gen, status: AddressStatus.ok));
    }
  }
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text('Ga Đồng Hới').first);
  expect(find.text('Lưu vào Công ty'), findsOneWidget);

  await tester.enterText(find.byType(TextField), 'nguyen trai');
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
  client.completes.last.done.complete(
    CompleteReply(
      gen: client.completes.last.gen,
      status: AddressStatus.ok,
      items: const [
        AddressSuggestion(
          title: 'Phố Nguyễn Trãi',
          subtitle: 'Thanh Xuân, Hà Nội',
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final row = find.byKey(const ValueKey('address-0'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pump();
  expect(client.resolves.last.done.isCompleted, isFalse);
}

/// Answers the pending resolve with Phố Nguyễn Trãi's point.
void _resolveNguyenTrai(FakeAddressClient client) =>
    client.resolves.last.done.complete(
      const ResolveReply(
        status: AddressStatus.ok,
        point: MapPoint(21, 105.8),
        country: 'VN',
      ),
    );

void main() {
  for (final slot in SavedPlaceSlot.values) {
    final label = _slotLabel[slot]!;

    testWidgets('A ${slot.name}: long press > change > address > '
        'Lưu vào $label', (tester) async {
      final client = FakeAddressClient();
      final h = await _pump(tester, client);
      await _openChange(tester, h, slot);
      await _pickAddress(tester, client, label: 'Lưu vào $label');
      expect(find.text('Chọn Phố Nguyễn Trãi'), findsNothing);
      await tapVisible(tester, find.text('Lưu vào $label'));
      await _expectSaved(h, tester, slot, _address);
      await _expectOthersUnchanged(h, slot);
    });

    testWidgets('D1 ${slot.name}: Back > dialog > Lưu saves', (tester) async {
      final client = FakeAddressClient();
      final h = await _pump(tester, client);
      await _openChange(tester, h, slot);
      await _pickAddress(tester, client, label: 'Lưu vào $label');
      await _tapBack(tester);
      expect(find.text('Lưu vào $label?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('leave-save')));
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      await _expectSaved(h, tester, slot, _address);
      await _expectOthersUnchanged(h, slot);
    });

    testWidgets('B ${slot.name}: search > address > Lưu > slot > Back', (
      tester,
    ) async {
      final client = FakeAddressClient();
      final h = await _pump(tester, client);
      await tester.tap(find.text('Tìm ga, bến xe…'));
      await tester.pumpAndSettle();
      expect(h.app.location, AppRoutes.destination);
      await _pickAddress(tester, client, label: 'Chọn Phố Nguyễn Trãi');
      await tester.tap(find.byTooltip('Lưu điểm này'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('save-slot-${slot.name}')));
      await tester.pumpAndSettle();
      await _tapBack(tester);
      expect(_dialog, findsNothing);
      await _expectSaved(h, tester, slot, _address);
    });
  }

  testWidgets('A2 work: address tapped > Back asks, nothing saved yet', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _toDialog(tester, h, client);
    expect(find.text('Lưu vào Công ty?'), findsOneWidget);
    expect(find.text('Đã chọn: Phố Nguyễn Trãi'), findsOneWidget);
    expect(find.text('Lưu'), findsOneWidget);
    expect(find.text('Bỏ'), findsOneWidget);
    expect(h.app.location, AppRoutes.destination);
    final saved = await h.app
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.work);
    expect(saved?.destination, kBenXeMyDinh);
  });

  testWidgets('D2 Bỏ: back to Home, slot unchanged', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _toDialog(tester, h, client);
    await tester.tap(find.byKey(const ValueKey('leave-discard')));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    await _expectSaved(h, tester, SavedPlaceSlot.work, kBenXeMyDinh);
    await _expectOthersUnchanged(h, SavedPlaceSlot.work);
  });

  testWidgets('D3 barrier tap: stay, choice kept, the button still saves', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _toDialog(tester, h, client);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(h.app.location, AppRoutes.destination);
    expect(find.text('Lưu vào Công ty'), findsOneWidget);
    await tapVisible(tester, find.text('Lưu vào Công ty'));
    await _expectSaved(h, tester, SavedPlaceSlot.work, _address);
  });

  testWidgets('D3b system back on the dialog: stay on screen 2', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _toDialog(tester, h, client);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(h.app.location, AppRoutes.destination);
    expect(find.text('Lưu vào Công ty'), findsOneWidget);
  });

  testWidgets('D4 Android system back with a choice: dialog; Bỏ leaves', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);
    await _pickAddress(tester, client);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(h.app.location, AppRoutes.destination);
    await tester.tap(find.byKey(const ValueKey('leave-discard')));
    await tester.pumpAndSettle();
    await _expectSaved(h, tester, SavedPlaceSlot.work, kBenXeMyDinh);
  });

  testWidgets('D5 iOS edge swipe with a choice: no exit, no dialog', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pumpIos(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);
    await _pickAddress(tester, client);
    await _edgeSwipe(tester);
    expect(h.app.location, AppRoutes.destination);
    expect(_dialog, findsNothing);
    expect(find.text('Lưu vào Công ty'), findsOneWidget);
    final saved = await h.app
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.work);
    expect(saved?.destination, kBenXeMyDinh);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('D6 iOS edge swipe without a choice: back to Home', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pumpIos(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);
    await _edgeSwipe(tester);
    expect(_dialog, findsNothing);
    await _expectSaved(h, tester, SavedPlaceSlot.work, kBenXeMyDinh);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('D7 Back without a choice leaves at once (arrow, system)', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);
    await _tapBack(tester);
    expect(_dialog, findsNothing);
    await _expectSaved(h, tester, SavedPlaceSlot.work, kBenXeMyDinh);

    await _openChange(tester, h, SavedPlaceSlot.work);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    await _expectSaved(h, tester, SavedPlaceSlot.work, kBenXeMyDinh);
  });

  testWidgets('D8 hometown: station > Back > Lưu', (tester) async {
    final h = await _pump(tester, null);
    await _openChange(tester, h, SavedPlaceSlot.hometown);
    await selectDongHoi(tester);
    expect(find.text('Lưu vào Quê'), findsOneWidget);
    await _tapBack(tester);
    expect(find.text('Đã chọn: Ga Đồng Hới'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-save')));
    await tester.pumpAndSettle();
    await _expectSaved(
      h,
      tester,
      SavedPlaceSlot.hometown,
      TripDestination.fromStation(gaDongHoi),
    );
  });

  testWidgets('D9 home: pin > Back > Lưu', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.home);
    h.map.last.onLongPress(const MapPoint(16.5, 107.5));
    await tester.pumpAndSettle();
    expect(find.text('Lưu vào Nhà'), findsOneWidget);
    await _tapBack(tester);
    expect(_dialog, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-save')));
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.home);
    final saved = await h.app
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.home);
    expect(saved?.destination.kind, DestinationKind.pin);
    expect(saved?.destination.lat, 16.5);
    expect(saved?.destination.lng, 107.5);
  });

  testWidgets('D10 empty work slot: Thêm > address > Back > Lưu', (
    tester,
  ) async {
    final client = FakeAddressClient();
    final h = await _pump(
      tester,
      client,
      places: const {
        SavedPlaceSlot.home: kHomeAddress,
        SavedPlaceSlot.hometown: kHometown,
      },
    );
    await tester.tap(_tile(SavedPlaceSlot.work));
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.destination);
    await _pickAddress(tester, client);
    await _tapBack(tester);
    expect(find.text('Lưu vào Công ty?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-save')));
    await tester.pumpAndSettle();
    await _expectSaved(h, tester, SavedPlaceSlot.work, _address);
  });

  testWidgets('D11 two quick Backs: one dialog', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);
    await _pickAddress(tester, client);
    // Both presses land before the dialog is built: once the dialog shows,
    // its barrier takes any further tap.
    final back = tester.widget<NapIconButton>(
      find.ancestor(of: _back, matching: find.byType(NapIconButton)),
    );
    back.onPressed!();
    back.onPressed!();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(h.app.location, AppRoutes.destination);
  });

  testWidgets('C work: tap tile > screen 3 > Đổi > address > Chọn > Back x2: '
      'unchanged, no dialog', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await tester.tap(_tile(SavedPlaceSlot.work));
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
    await tapVisible(tester, find.text('Đổi'));
    expect(h.app.location, AppRoutes.destination);
    await _pickAddress(tester, client, label: 'Chọn Phố Nguyễn Trãi');
    await tapVisible(tester, find.text('Chọn Phố Nguyễn Trãi'));
    expect(h.app.location, AppRoutes.alarmSettings);
    h.app.router.pop();
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.destination);
    await _tapBack(tester);
    expect(_dialog, findsNothing);
    await _expectSaved(h, tester, SavedPlaceSlot.work, kBenXeMyDinh);
  });

  testWidgets('C2 normal screen 2 with a station: Back leaves at once', (
    tester,
  ) async {
    final h = await _pump(tester, null);
    await tester.tap(find.text('Tìm ga, bến xe…'));
    await tester.pumpAndSettle();
    await selectDongHoi(tester);
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
    await _tapBack(tester);
    expect(_dialog, findsNothing);
    expect(h.app.location, AppRoutes.home);
  });

  testWidgets('R2 unknown slot value: plain picker, Back does not ask', (
    tester,
  ) async {
    final h = await _pump(tester, null);
    final result = h.app.router.push<TripDestination>(
      '/destination?mode=pick&slot=xyz',
    );
    await tester.pumpAndSettle();
    await selectDongHoi(tester);
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
    expect(find.textContaining('Lưu vào'), findsNothing);
    await _tapBack(tester);
    expect(_dialog, findsNothing);
    expect(h.app.location, AppRoutes.home);
    expect(await result, isNull);
  });

  // Tester (review minor #1): an Apple address resolve still running when the
  // dialog opens must not make "Lưu" save a point other than the one the
  // dialog named.
  testWidgets('T1 resolve lands while the dialog is open: Lưu saves the '
      'named choice', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);

    // Station first (answer the address request "dong hoi" makes: nothing).
    await tester.enterText(find.byType(TextField), 'dong hoi');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    for (final c in client.completes) {
      if (!c.done.isCompleted) {
        c.done.complete(CompleteReply(gen: c.gen, status: AddressStatus.ok));
      }
    }
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    expect(find.text('Lưu vào Công ty'), findsOneWidget);

    // Then an address row whose resolve is slow.
    await tester.enterText(find.byType(TextField), 'nguyen trai');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    client.completes.last.done.complete(
      CompleteReply(
        gen: client.completes.last.gen,
        status: AddressStatus.ok,
        items: const [
          AddressSuggestion(
            title: 'Phố Nguyễn Trãi',
            subtitle: 'Thanh Xuân, Hà Nội',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('address-0'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    expect(client.resolves, hasLength(1));
    expect(client.resolves.last.done.isCompleted, isFalse);

    // Back at once: the dialog names the station (the pending choice).
    await tester.tap(_back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_dialog, findsOneWidget);
    expect(find.text('Đã chọn: Ga Đồng Hới'), findsOneWidget);

    // The resolve lands while the dialog is up.
    client.resolves.last.done.complete(
      const ResolveReply(
        status: AddressStatus.ok,
        point: MapPoint(21, 105.8),
        country: 'VN',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('leave-save')));
    await tester.pumpAndSettle();

    // Whatever the screen does next, the slot must never hold a point the
    // user did not just confirm: either the station (named in the dialog) or
    // nothing yet (still on screen 2, nothing written).
    final saved = await h.app
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.work);
    expect(
      saved?.destination,
      isNot(_address),
      reason: 'dialog said "Đã chọn: Ga Đồng Hới" but Lưu saved the address',
    );
    if (h.app.location == AppRoutes.home) {
      expect(saved?.destination, TripDestination.fromStation(gaDongHoi));
    } else {
      expect(saved?.destination, kBenXeMyDinh);
    }
  });

  // Round 2 pins the behaviour T1 leaves open (review vòng 2 nit #1): the
  // choice moved under the dialog, so "Lưu" stays on screen 2 and writes
  // nothing; the new choice is there with "Lưu vào Công ty".
  for (final via in ['button', 'back']) {
    testWidgets('T1b resolve lands while the dialog is open: Lưu stays on '
        'screen 2, slot unchanged; then $via saves the address', (
      tester,
    ) async {
      final client = FakeAddressClient();
      final h = await _pump(tester, client);
      await _openChange(tester, h, SavedPlaceSlot.work);
      await _stationThenSlowAddress(tester, client);

      await tester.tap(_back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Đã chọn: Ga Đồng Hới'), findsOneWidget);
      _resolveNguyenTrai(client);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('leave-save')));
      await tester.pumpAndSettle();

      final repo = h.app.read(savedPlacesRepositoryProvider);
      expect(h.app.location, AppRoutes.destination);
      expect(_dialog, findsNothing);
      expect((await repo.get(SavedPlaceSlot.work))?.destination, kBenXeMyDinh);
      expect(find.text('Lưu vào Công ty'), findsOneWidget);

      if (via == 'button') {
        await tapVisible(tester, find.text('Lưu vào Công ty'));
      } else {
        // The next Back names the new choice, so it is the selection now.
        await _tapBack(tester);
        expect(find.text('Đã chọn: Phố Nguyễn Trãi'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('leave-save')));
        await tester.pumpAndSettle();
      }
      await _expectSaved(h, tester, SavedPlaceSlot.work, _address);
      await _expectOthersUnchanged(h, SavedPlaceSlot.work);
    });
  }

  // A resolve that lands with the very point the dialog names builds a new
  // but equal Selection: Lưu must still save (value equality, not identity).
  testWidgets('T1c resolve of the same address lands while the dialog is '
      'open: Lưu saves it', (tester) async {
    final client = FakeAddressClient();
    final h = await _pump(tester, client);
    await _openChange(tester, h, SavedPlaceSlot.work);
    await _pickAddress(tester, client);
    expect(client.resolves, hasLength(1));

    // Tap the same (already chosen) row again: a second, slow resolve.
    final row = find.byKey(const ValueKey('address-0'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    expect(client.resolves, hasLength(2));
    expect(client.resolves.last.done.isCompleted, isFalse);

    await tester.tap(_back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Đã chọn: Phố Nguyễn Trãi'), findsOneWidget);
    _resolveNguyenTrai(client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('leave-save')));
    await tester.pumpAndSettle();

    await _expectSaved(h, tester, SavedPlaceSlot.work, _address);
    await _expectOthersUnchanged(h, SavedPlaceSlot.work);
  });

  testWidgets('L1 en: "Save to Work", dialog "Save to Work?"', (tester) async {
    final h = await _pump(tester, null, locale: const Locale('en'));
    unawaited(homeContext(tester).pickDestination(slot: SavedPlaceSlot.work));
    await tester.pumpAndSettle();
    await selectDongHoi(tester);
    expect(find.text('Save to Work'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Save to Work?'), findsOneWidget);
    expect(find.text('Selected: Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-discard')));
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.home);
  });
}
