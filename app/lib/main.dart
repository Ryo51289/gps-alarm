import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/design/fonts/font_licenses.dart';
import 'package:napstop/features/destination/data/station_license.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerStationDataLicense();
  registerFontLicenses();
  // First run (T21 D10): screen 0 until its main button was pressed. A read
  // slower than 500 ms shows screen 0 too (T21 CQ1).
  final initialLocation = await startupLocation(createOnboardingStore());
  runApp(
    // Automatic retry off (T22 D3): bridge and database errors do not go
    // away by themselves; screens offer an explicit "Thử lại".
    // T29 adds its telemetry override to this same ProviderScope.
    ProviderScope(
      retry: (_, _) => null,
      overrides: [startupLocationProvider.overrideWithValue(initialLocation)],
      child: NapStopApp(flavor: AppFlavor.current),
    ),
  );
}
