import 'dart:async';

/// Runs [call] without waiting and swallows every error, sync or async:
/// telemetry must never break or slow the app (T29 §7).
void fireAndForget(Future<void> Function() call) {
  try {
    unawaited(call().then<void>((_) {}, onError: (Object _) {}));
  } on Object {
    // A sink that throws synchronously is ignored too.
  }
}

/// Awaits [call], swallowing every error.
Future<void> safeAwait(Future<void> Function() call) async {
  try {
    await call();
  } on Object {
    // Ignored, see [fireAndForget].
  }
}
