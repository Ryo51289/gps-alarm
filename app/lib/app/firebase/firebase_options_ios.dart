// Hand-written from ios/Runner/GoogleService-Info.plist (T29.2 D4), not by
// `flutterfire configure`. Keep in sync: test/app/firebase_options_test.dart
// (FU02) fails when the two differ. Firebase config is not secret
// (T29.2 D3, https://firebase.google.com/docs/projects/api-keys).
import 'package:firebase_core/firebase_core.dart';

/// The iOS app `app.napstop` of project `napstop-dev-10636`: one
/// configuration for every iOS build until T40.1 (PLAN-ios Q6).
const FirebaseOptions iosFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyALZo65-lxYb9HHHKQCjyXNYoQwgR4kS-o',
  appId: '1:1035126296024:ios:0eddbb04f34caa8997f6ad',
  messagingSenderId: '1035126296024',
  projectId: 'napstop-dev-10636',
  storageBucket: 'napstop-dev-10636.firebasestorage.app',
  iosBundleId: 'app.napstop',
);
