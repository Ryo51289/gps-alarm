/// Remote Config boundary (T29 §6). `FirebaseRemoteConfigClient` is the only
/// implementation that talks to Firebase.
abstract interface class RemoteConfigClient {
  /// `setConfigSettings` + `setDefaults`. Local only, no network.
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  });

  /// Fetches (unless the cache is younger than the minimum interval) and
  /// activates. True when new values were activated.
  Future<bool> fetchAndActivate();

  /// The ACTIVE value of [key].
  String getString(String key);
}

/// No Firebase: every key is empty, so the engine uses its defaults.
final class NoopRemoteConfigClient implements RemoteConfigClient {
  const new();

  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) async {}

  @override
  Future<bool> fetchAndActivate() async => false;

  @override
  String getString(String key) => '';
}
