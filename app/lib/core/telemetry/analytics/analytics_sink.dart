/// Analytics SDK boundary (T29 §3). `FirebaseAnalyticsSink` is the only
/// implementation that talks to Firebase.
abstract interface class AnalyticsSink {
  Future<void> logEvent(String name, Map<String, Object> parameters);

  Future<void> setCollectionEnabled({required bool enabled});

  /// `FirebaseAnalytics.resetAnalyticsData()`: new app-instance id, local
  /// data cleared.
  Future<void> resetData();
}

/// No Firebase (not configured, init failed, tests).
final class NoopAnalyticsSink implements AnalyticsSink {
  const new();

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {}

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async {}

  @override
  Future<void> resetData() async {}
}
