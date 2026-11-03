// Fakes for screen 3 tests (T25). Not a test file.
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

/// Counts [current] calls.
class FakeEngineParamsReader implements EngineParamsReader {
  new([this.value = EngineParamsOverride.defaults]);

  EngineParamsOverride value;
  int calls = 0;

  @override
  EngineParamsOverride current() {
    calls++;
    return value;
  }
}

/// Records every event.
class RecordingReporter implements TripStartReporter {
  final List<TripStartFacts> startedFacts = [];
  final List<(TripStartBlockReason, bool)> blockedEvents = [];
  final List<String> rejected = [];
  final List<Object> historyErrors = [];

  @override
  void started(TripStartFacts facts) => startedFacts.add(facts);

  @override
  void blocked(TripStartBlockReason reason, {required bool simulated}) =>
      blockedEvents.add((reason, simulated));

  @override
  void configRejected(String rule) => rejected.add(rule);

  @override
  void historyWriteFailed(Object error, StackTrace stack) =>
      historyErrors.add(error);
}

/// In-memory [TripsRepository]; appends 'insertStarted' / 'delete' to [log]
/// (usually `FakeCoreBridge.calls`, to check the order).
class FakeTripsRepository implements TripsRepository {
  new(this.log);

  final List<String> log;
  final Map<String, TripRecord> rows = {};
  Object? insertError;
  Object? deleteError;

  @override
  Future<void> insertStarted(TripRecord record) {
    log.add('insertStarted');
    final e = insertError;
    if (e != null) {
      return Future.error(e);
    }
    rows[record.id] = record;
    return Future.value();
  }

  @override
  Future<void> delete(String tripId) {
    log.add('delete');
    final e = deleteError;
    if (e != null) {
      return Future.error(e);
    }
    rows.remove(tripId);
    return Future.value();
  }

  @override
  Future<TripRecord?> byId(String tripId) async => rows[tripId];

  @override
  Stream<List<TripRecord>> watchRecentDestinations({
    int limit = kRecentTripsLimit,
  }) => Stream.value(rows.values.toList());
}
