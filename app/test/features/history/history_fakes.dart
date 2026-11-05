// Fakes of the T28 history tests. Not a test file.
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/fake_key_value_store.dart';

/// A [Telemetry] whose Analytics and Crashlytics go to recording sinks,
/// collection on (like a consented release build).
Telemetry recordingTelemetry(RecordingAnalyticsSink a, RecordingCrashSink c) {
  final crash = CrashReporter(c);
  final controller = TelemetryConsentController(
    store: TelemetryConsentStore(FakeKeyValueStore()),
    consent: TelemetryConsent.initial,
    crashSink: c,
    analyticsSink: a,
    flavor: AppFlavor.dev,
    isDebugBuild: false,
    override: TelemetryOverride.on,
  );
  return Telemetry(
    analytics: AppAnalytics(
      sink: a,
      crash: crash,
      isEnabled: () => controller.effective.analytics,
    ),
    crash: crash,
    engineParams: EngineParamsSource(
      FakeRemoteConfigClient(),
      flavor: AppFlavor.dev,
    ),
    consent: controller,
  );
}

/// [TripsRepository] with scripted [applyFinished] answers by trip id; calls
/// are appended to [log].
class ScriptedTripsRepository implements TripsRepository {
  new(this.log);

  final List<String> log;

  /// Answer of [applyFinished] per trip id; missing → noRow.
  final Map<String, ApplyFinishedResult> results = {};

  /// Thrown by [applyFinished] for these ids.
  final Map<String, Object> errors = {};

  /// Record returned with `applied`.
  final Map<String, TripRecord> records = {};

  /// Arguments of [markUnfinishedAsUnknown].
  final List<({String? except, int before, int ended})> marks = [];
  Object? markError;

  @override
  Future<({ApplyFinishedResult result, TripRecord? record})> applyFinished(
    FinishedTripMsg f,
  ) async {
    log.add('apply:${f.tripId}');
    final e = errors[f.tripId];
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    final r = results[f.tripId] ?? ApplyFinishedResult.noRow;
    return (
      result: r,
      record: r == ApplyFinishedResult.applied ? records[f.tripId] : null,
    );
  }

  @override
  Future<int> markUnfinishedAsUnknown({
    required String? exceptTripId,
    required int startedBeforeMs,
    required int endedAtMs,
  }) async {
    log.add('mark');
    final e = markError;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    marks.add((
      except: exceptTripId,
      before: startedBeforeMs,
      ended: endedAtMs,
    ));
    return 0;
  }

  @override
  Future<void> insertStarted(TripRecord record) async {}

  @override
  Future<void> delete(String tripId) async {}

  @override
  Future<TripRecord?> byId(String tripId) async => records[tripId];

  @override
  Stream<List<TripRecord>> watchRecentDestinations({
    int limit = kRecentTripsLimit,
  }) => const Stream.empty();

  @override
  Stream<List<TripRecord>> watchHistory({int limit = kHistoryLimit}) =>
      const Stream.empty();

  @override
  Stream<List<TripRecord>> watchRealTripsSince(int sinceMs) =>
      const Stream.empty();
}
