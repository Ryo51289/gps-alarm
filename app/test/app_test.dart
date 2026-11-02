// W19: the real NapStopApp under a ProviderScope (fake bridge, in-memory
// database), both flavors.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/db/db_providers.dart';

import 'helpers/app_harness.dart';
import 'helpers/fake_core_bridge.dart';

void main() {
  group('NapStopApp', () {
    for (final flavor in AppFlavor.values) {
      testWidgets('starts on Home ($flavor)', (tester) async {
        tester.platformDispatcher.localesTestValue = const [Locale('vi')];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final db = memoryDatabase();
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
              appDatabaseProvider.overrideWith((ref) {
                ref.onDispose(db.close);
                return db;
              }),
            ],
            child: NapStopApp(flavor: flavor),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
        expect(kAppName, 'NapStop');
        expect(tester.takeException(), isNull);
        // Unmount inside the test: disposing the scope closes the drift
        // query streams with short timers that must fire before the end.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}
