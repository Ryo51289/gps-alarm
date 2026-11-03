/// An error of ours whose `toString` is known to hold no user data (names
/// and enum values only), so `CrashReporter` may send its (redacted)
/// message. Pure Dart.
abstract interface class SafeDiagnostic;
