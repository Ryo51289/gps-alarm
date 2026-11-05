/// Settings of screen 12 held in memory for the whole app (T28 §4.1, D7).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/preferences/trip_settings.dart';

@immutable
final class AppSettings {
  const new({
    required this.alarm,
    required this.tripDefaults,
    required this.display,
    required this.loaded,
  });

  final AlarmPreferences alarm;

  /// Defaults of screen 3 for new trips; always [TripSettings.normalized].
  final TripSettings tripDefaults;
  final DisplayPreferences display;

  /// False until the stored values were read once (screen 12 controls stay
  /// disabled meanwhile).
  final bool loaded;

  AppSettings copyWith({
    AlarmPreferences? alarm,
    TripSettings? tripDefaults,
    DisplayPreferences? display,
    bool? loaded,
  }) => AppSettings(
    alarm: alarm ?? this.alarm,
    tripDefaults: tripDefaults ?? this.tripDefaults,
    display: display ?? this.display,
    loaded: loaded ?? this.loaded,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.alarm == alarm &&
      other.tripDefaults == tripDefaults &&
      other.display == display &&
      other.loaded == loaded;

  @override
  int get hashCode => Object.hash(alarm, tripDefaults, display, loaded);

  @override
  String toString() => 'AppSettings($alarm, $tripDefaults, $display, $loaded)';
}

/// Language and theme read before `runApp` (D8); main() overrides it.
final initialDisplayPreferencesProvider = Provider<DisplayPreferences>(
  (ref) => DisplayPreferences.defaults,
);

final NotifierProvider<AppSettingsController, AppSettings> appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// Changes apply at once in memory, then go to disk through one serial queue
/// per group; each queued step writes the group's LATEST value, so the last
/// change wins on disk too. A failed write is logged (error type only); the
/// value stays in force for the session and the next change writes again.
final class AppSettingsController extends Notifier<AppSettings> {
  static final Logger _log = AppLog.named('settings');

  bool _alarmTouched = false;
  bool _tripTouched = false;
  bool _displayTouched = false;

  /// Groups with a queued write that has not started yet.
  final Set<_Group> _waiting = {};

  Future<void> _alarmQueue = Future<void>.value();
  Future<void> _tripQueue = Future<void>.value();
  Future<void> _displayQueue = Future<void>.value();

  PreferencesRepository get _repo => ref.read(preferencesRepositoryProvider);

  @override
  AppSettings build() {
    unawaited(_load());
    return AppSettings(
      alarm: AlarmPreferences.defaults,
      tripDefaults: TripSettings.defaults,
      display: ref.read(initialDisplayPreferencesProvider),
      loaded: false,
    );
  }

  /// Reading never throws (the repository falls back to defaults). A group
  /// changed during this session keeps the user's value.
  Future<void> _load() async {
    final repo = _repo;
    final (alarm, trip, display) = await (
      repo.loadAlarmPreferences(),
      repo.loadTripDefaults(),
      repo.loadDisplayPreferences(),
    ).wait;
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      alarm: _alarmTouched ? null : alarm,
      tripDefaults: _tripTouched ? null : trip,
      display: _displayTouched ? null : display,
      loaded: true,
    );
  }

  void setAlarm(AlarmPreferences p) {
    _alarmTouched = true;
    state = state.copyWith(alarm: p);
    _alarmQueue = _enqueue(_alarmQueue, _Group.alarm);
  }

  void setTripDefaults(TripSettings s) {
    _tripTouched = true;
    state = state.copyWith(tripDefaults: s.normalized());
    _tripQueue = _enqueue(_tripQueue, _Group.trip);
  }

  void setDisplay(DisplayPreferences d) {
    _displayTouched = true;
    state = state.copyWith(display: d);
    _displayQueue = _enqueue(_displayQueue, _Group.display);
  }

  /// Completes when every queued write has run.
  Future<void> flush() async {
    while (true) {
      final queues = (_alarmQueue, _tripQueue, _displayQueue);
      await Future.wait([queues.$1, queues.$2, queues.$3]);
      if (identical(queues.$1, _alarmQueue) &&
          identical(queues.$2, _tripQueue) &&
          identical(queues.$3, _displayQueue)) {
        return;
      }
    }
  }

  /// Queues one write of [group] unless one is already waiting to start
  /// (that one writes the latest value too: a slider drag costs one write).
  Future<void> _enqueue(Future<void> queue, _Group group) {
    if (!_waiting.add(group)) {
      return queue;
    }
    return queue.then((_) => _write(group));
  }

  Future<void> _write(_Group group) async {
    _waiting.remove(group);
    if (!ref.mounted) {
      return;
    }
    final repo = _repo;
    final s = state;
    try {
      await switch (group) {
        _Group.alarm => repo.saveAlarmPreferences(s.alarm),
        _Group.trip => repo.saveTripDefaults(s.tripDefaults),
        _Group.display => repo.saveDisplayPreferences(s.display),
      };
    } on Object catch (e) {
      _log.warning('save ${group.name} failed: ${e.runtimeType}');
    }
  }
}

enum _Group { alarm, trip, display }
