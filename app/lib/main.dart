import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/design/fonts/font_licenses.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';
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
  //   read slower than 500 ms shows screen 0 too (T21 CQ1);
  // - language and theme of screen 12 (T28 D8), so the first frame is right;
  //   slower than 500 ms → defaults, the stored values follow when read.
  final (telemetry, initialLocation, display) = await (
    bootstrapTelemetry(flavor: flavor),
    startupLocation(createOnboardingStore()),
    loadInitialDisplayPreferences(),
  ).wait;
  runApp(
    // Automatic retry off (T22 D3): bridge and database errors do not go
    // away by themselves; screens offer an explicit "Thử lại".
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        startupLocationProvider.overrideWithValue(initialLocation),
        telemetryProvider.overrideWithValue(telemetry),
        initialDisplayPreferencesProvider.overrideWithValue(display),
      ],
      child: NapStopApp(flavor: flavor),
    ),
  );
}

/// T28 D8: at most [timeout]; any error → defaults (the repository never
/// throws, the platform channel might).
Future<DisplayPreferences> loadInitialDisplayPreferences({
  Duration timeout = const Duration(milliseconds: 500),
}) =>
    PreferencesRepository(SharedPreferencesKeyValueStore())
        .loadDisplayPreferences()
        .timeout(timeout, onTimeout: () => DisplayPreferences.defaults)
        .catchError((Object _) => DisplayPreferences.defaults);
