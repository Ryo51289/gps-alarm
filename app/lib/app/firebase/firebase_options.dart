import 'package:firebase_core/firebase_core.dart';
import 'package:napstop/app/flavor.dart';

/// Firebase options of [flavor] (T29 §1.2), or null when this build has no
/// Firebase configuration: telemetry then runs as a no-op.
///
/// Step A (no Firebase project files in the repo yet): always null. Step B
/// switches on the flavor over the FlutterFire CLI output
/// (`firebase_options_dev.dart` / `firebase_options_prod.dart`, imported
/// with the prefixes `dev.` / `prod.`); on iOS before T29 §5 it throws
/// [UnsupportedError], which `bootstrapTelemetry` also treats as no-op.
FirebaseOptions? firebaseOptionsFor(AppFlavor flavor) => null;
