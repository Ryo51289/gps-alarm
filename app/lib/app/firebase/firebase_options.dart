import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:napstop/app/firebase/firebase_options_ios.dart' as ios;
import 'package:napstop/app/flavor.dart';

/// Firebase options of this build, or null when it has no Firebase
/// configuration: telemetry then runs as a no-op (T29 §1.2).
///
/// iOS (T29.2 §3): one configuration (`app.napstop`, hand-written in
/// `firebase_options_ios.dart`) for every flavor until T40.1 (PLAN-ios Q6):
/// an iOS build has no flavor, so `AppFlavor.current` is dev there.
/// Android: null until T29 step B. [platform] defaults to
/// [defaultTargetPlatform] (tests pass it explicitly).
FirebaseOptions? firebaseOptionsFor(
  AppFlavor flavor, {
  TargetPlatform? platform,
}) {
  if (kIsWeb) {
    return null;
  }
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS => ios.iosFirebaseOptions,
    _ => null,
  };
}
