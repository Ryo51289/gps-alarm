import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';

/// Thin adapter: the only file importing `package:firebase_analytics`
/// (TC22). Gets events that already passed the guard; never sets a user id
/// or a user property, no navigator observer.
final class FirebaseAnalyticsSink implements AnalyticsSink {
  new([this._injected]);

  final FirebaseAnalytics? _injected;

  FirebaseAnalytics get _a => _injected ?? FirebaseAnalytics.instance;

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) =>
      _a.logEvent(name: name, parameters: parameters);

  @override
  Future<void> setCollectionEnabled({required bool enabled}) =>
      _a.setAnalyticsCollectionEnabled(enabled);

  @override
  Future<void> resetData() => _a.resetAnalyticsData();
}
