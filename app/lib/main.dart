import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/design/fonts/font_licenses.dart';
import 'package:napstop/core/telemetry/telemetry_bootstrap.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/features/destination/data/station_license.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerStationDataLicense();
  registerFontLicenses();
  final flavor = AppFlavor.current;
  // In parallel (independent):
  // - T29 telemetry: no-op without Firebase options; never throws, at most
  //   ~3.5 s;
  // - first run (T21 D10): screen 0 until its main button was pressed. A
  //   read slower than 500 ms shows screen 0 too (T21 CQ1).
  final (telemetry, initialLocation) = await (
    bootstrapTelemetry(flavor: flavor),
    startupLocation(createOnboardingStore()),
  ).wait;
  runApp(
    // Automatic retry off (T22 D3): bridge and database errors do not go
    // away by themselves; screens offer an explicit "Thử lại".
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        startupLocationProvider.overrideWithValue(initialLocation),
        telemetryProvider.overrideWithValue(telemetry),
      ],
      child: NapStopApp(flavor: flavor),
    ),
  );
}
