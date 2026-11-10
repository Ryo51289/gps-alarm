// T23.5 AS-I01..AS-I03 (docs/specs/T23.5.md): the address search channel on the
// iOS Simulator, real app, real channel. Debug build (NAPSTOP_DIAG): `diagFake`
// of Runner/Map/AddressSearchChannel.swift swaps MapKit for a fixed list, and
// `diagState` of the map view reads the pin. AS-I03 talks to the real MapKit
// and judges only that the answer decodes (the Simulator may have no network).
// Skipped on Android. Logs no typed text, no address and no coordinate.
// By hand on a Mac:
//   flutter test integration_test/address_search_ios_test.dart -d <udid>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_view.dart';
import 'package:napstop/features/destination/data/address_search_client.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

final bool _notIos = !Platform.isIOS;

const MethodChannel _search = MethodChannel(kAddressSearchChannel);

/// The widget tree is removed first, then the container is disposed (a tree
/// left mounted on a disposed container breaks the next file of the CI group).
ProviderContainer _newContainer(WidgetTester tester, String initialLocation) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [startupLocationProvider.overrideWithValue(initialLocation)],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  return container;
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      return false;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

Future<void> _wait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

NapMapViewState _map(WidgetTester tester) =>
    tester.state<NapMapViewState>(find.byType(NapMapView));

Future<Map<Object?, Object?>> _diagState(WidgetTester tester) async {
  final channel = MethodChannel(napMapChannelName(_map(tester).viewId!));
  final r = await channel.invokeMethod<Object?>('diagState');
  return r! as Map<Object?, Object?>;
}

Future<void> _fake(List<Map<String, Object?>>? items) => _search
    .invokeMethod<void>('diagFake', items == null ? null : {'items': items});

Future<void> _openScreen2(WidgetTester tester) async {
  final container = _newContainer(tester, AppRoutes.destination);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NapStopApp(flavor: AppFlavor.dev),
    ),
  );
  expect(
    await _pumpUntil(
      tester,
      () => find.byType(NapMapView).evaluate().isNotEmpty,
    ),
    isTrue,
    reason: 'no NapMapView',
  );
}

Future<void> _type(WidgetTester tester, String text) async {
  final field = find.byType(TextField);
  await tester.tap(field);
  await _wait(tester, const Duration(milliseconds: 500));
  await tester.enterText(field, text);
}

/// What the address section shows now, as plain flags for a failure reason
/// (public UI strings only, no typed text).
AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(DestinationScreen)));

String _flags(WidgetTester tester) {
  final l = _l(tester);
  bool has(String s) => find.text(s).evaluate().isNotEmpty;
  return 'header=${has(l.destinationAddressHeader)} '
      'loading=${has(l.destinationAddressLoading)} '
      'empty=${has(l.destinationAddressEmpty)} '
      'offline=${has(l.destinationAddressOffline)} '
      'unavailable=${has(l.destinationAddressUnavailable)} '
      'throttled=${has(l.destinationAddressThrottled)} '
      'resolving=${has(l.destinationAddressResolving)}';
}

/// Waits for the address row [index] (a fake item of the real channel).
Future<void> _expectRow(WidgetTester tester, int index) async {
  final row = find.byKey(ValueKey('address-$index'));
  expect(
    await _pumpUntil(
      tester,
      () => row.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    ),
    isTrue,
    reason: 'no address row $index: ${_flags(tester)}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    // Back to the real MapKit for whatever test runs next.
    await _fake(null);
  });

  // Titles carry the token "zzq" so that no station of the offline dataset
  // matches the same text.
  testWidgets('AS-I01 fake suggestions come through the real channel', (
    tester,
  ) async {
    await _fake([
      {
        't': 'Zzq Giáp Bát',
        's': 'Hà Nội',
        'lat': 20.9806,
        'lng': 105.8412,
        'country': 'VN',
      },
      {
        't': 'Zzq Thành',
        's': 'TP HCM',
        'lat': 10.7725,
        'lng': 106.698,
        'country': 'VN',
      },
      {'t': 'Khác', 's': '', 'lat': 10, 'lng': 106, 'country': 'VN'},
    ]);
    await _openScreen2(tester);
    await _type(tester, 'zzq');
    await _expectRow(tester, 1);
    expect(find.text(_l(tester).destinationAddressHeader), findsOneWidget);
    expect(find.text('Khác'), findsNothing);
    final row = find.byKey(const ValueKey('address-1'));
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(row);
    await _wait(tester, const Duration(seconds: 3));
    final s = await _diagState(tester);
    expect(s['annotations'], 1, reason: _flags(tester));
    final pin = s['pin']! as List;
    expect((pin[0]! as num).toDouble(), closeTo(10.7725, 1e-4));
    expect((pin[1]! as num).toDouble(), closeTo(106.698, 1e-4));
  }, skip: _notIos);

  testWidgets('AS-I02 a point outside the supported area is refused', (
    tester,
  ) async {
    await _fake([
      {'t': 'Zzq xa', 's': '', 'lat': 16.5, 'lng': 111.6, 'country': null},
    ]);
    await _openScreen2(tester);
    await _type(tester, 'zzq');
    await _expectRow(tester, 0);
    final row = find.byKey(const ValueKey('address-0'));
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(row);
    expect(
      await _pumpUntil(
        tester,
        () => find
            .text(_l(tester).destinationAddressOutsideArea)
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 8),
      ),
      isTrue,
      reason: 'no snack bar: ${_flags(tester)}',
    );
    final s = await _diagState(tester);
    expect(s['annotations'], 0);
  }, skip: _notIos);

  testWidgets('AS-I03 real MapKit answers in a decodable way', (tester) async {
    await _fake(null);
    const client = MethodChannelAddressSearchClient();
    final reply = await client.complete(gen: 1, query: 'Hà Nội');
    // No claim about the content: the Simulator may have no network.
    expect(reply.gen, 1);
    expect(
      reply.status,
      isIn([
        AddressStatus.ok,
        AddressStatus.network,
        AddressStatus.failed,
        AddressStatus.timeout,
      ]),
    );
    expect(reply.items.length, lessThanOrEqualTo(kMaxAddressItems));
  }, skip: _notIos);
}
