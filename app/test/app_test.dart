import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';

void main() {
  group('NapStopApp', () {
    for (final flavor in AppFlavor.values) {
      testWidgets('shows the brand name once ($flavor)', (tester) async {
        await tester.pumpWidget(NapStopApp(flavor: flavor));
        await tester.pumpAndSettle();

        expect(find.text(kAppName), findsOneWidget);
        expect(find.text('NapStop'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
