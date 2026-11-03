// Tester T23 (adversarial): "cách X" near the 1 km display boundary with the
// values the native side can return after rounding (review T23 #3: 10 m
// steps under 1 km, 100 m from 1 km), and the bridge input cap (≤ 20
// stations = ≤ 40 numbers, native rejects > 100).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

import '../../../helpers/fake_core_bridge.dart';
import 'destination_harness.dart';

FakeCoreBridge _bridge(List<double> Function(int n) values) => FakeCoreBridge(
  mapsConfig: MapsConfigMsg(apiKey: 'k'),
  distances: (pairs) => values(pairs.length ~/ 2),
);

void main() {
  testWidgets('D1 boundary values render like formatDistanceShort', (
    tester,
  ) async {
    const shown = [0.0, 990.0, 1000.0, 1100.0, 402000.0];
    await pumpDestination(
      tester,
      bridge: _bridge((n) => [for (var i = 0; i < n; i++) shown[i % 5]]),
    );
    await typeQuery(tester, 'vinh');
    for (final text in [
      'cách 0 m',
      'cách 990 m',
      'cách 1 km',
      'cách 1,1 km',
      'cách 402 km',
    ]) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    // Never a 4-digit metre value.
    expect(find.textContaining(RegExp(r'cách \d{4} m')), findsNothing);
  });

  testWidgets('D2 English boundary values', (tester) async {
    await pumpDestination(
      tester,
      locale: const Locale('en'),
      bridge: _bridge(
        (n) => [
          for (var i = 0; i < n; i++)
            if (i.isEven) 1000.0 else 990.0,
        ],
      ),
    );
    await typeQuery(tester, 'vinh');
    expect(find.textContaining('· 1 km away'), findsWidgets);
    expect(find.textContaining('· 990 m away'), findsWidgets);
  });

  testWidgets('D3 every call ≤ 20 stations, even length, across chips', (
    tester,
  ) async {
    final h = await pumpDestination(
      tester,
      bridge: _bridge((n) => [for (var i = 0; i < n; i++) 5000]),
    );
    for (final q in ['ben xe', 'ga', 'vinh', 'ha noi', 'nha trang']) {
      await typeQuery(tester, q);
    }
    await tapVisible(tester, find.text('Ga tàu'));
    await typeQuery(tester, 'ga s');
    await tapVisible(tester, find.text('Bến xe'));
    await typeQuery(tester, 'ben xe d');
    expect(h.bridge.distancesCalls, isNotEmpty);
    for (final c in h.bridge.distancesCalls) {
      expect(c.pairs.length.isEven, isTrue);
      expect(c.pairs.length, inInclusiveRange(2, 2 * kDisplayLimit));
      expect(c.maxAgeMs, kLastKnownMaxAgeMs);
    }
  });
}
