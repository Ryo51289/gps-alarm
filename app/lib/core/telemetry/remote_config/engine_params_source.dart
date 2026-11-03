/// Remote Config `trip_engine_params` → engine (T29 §6). The value is read
/// with [EngineParamsSource.current] once per trip setup and frozen in the
/// trip (T10 §5); fetching never changes a running trip.
///
/// PRIVACY: the value is never logged or reported, only its id.
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';

/// T29 §6: 1 h in prod (changes apply within the hour during beta), 5 min
/// in dev. The SDK default is 12 h.
Duration minimumFetchIntervalFor(AppFlavor flavor) => switch (flavor) {
  AppFlavor.prod => const Duration(hours: 1),
  AppFlavor.dev => const Duration(minutes: 5),
};

/// SDK fetch timeout, and the longest [EngineParamsSource.refresh] waits.
const Duration kRemoteConfigFetchTimeout = Duration(seconds: 10);

/// In-app default: empty → engine defaults (`fromOverrides(null)`).
const Map<String, Object> kRemoteConfigDefaults = {kTripEngineParamsKey: ''};

/// Reported once per session when the active value is not usable.
final class RemoteConfigInvalid implements SafeDiagnostic {
  const new();

  @override
  String toString() => 'RemoteConfigInvalid($kTripEngineParamsKey)';
}

final class EngineParamsSource implements EngineParamsReader {
  new(
    this._client, {
    required this.flavor,
    this._crash,
    this.fetchTimeout = kRemoteConfigFetchTimeout,
  });

  final RemoteConfigClient _client;
  final AppFlavor flavor;
  final CrashReporter? _crash;
  final Duration fetchTimeout;

  /// The running SDK call (errors swallowed), until it completes.
  Future<void>? _inFlight;
  bool _reportedInvalid = false;

  static final Logger _logger = AppLog.named('telemetry.remote_config');

  /// Settings and defaults; local only. Never throws.
  Future<void> initialize() async {
    try {
      await _client.configure(
        fetchTimeout: fetchTimeout,
        minimumFetchInterval: minimumFetchIntervalFor(flavor),
        defaults: kRemoteConfigDefaults,
      );
    } on Object {
      _logger.fine('configure failed');
    }
  }

  /// `fetchAndActivate`, waiting at most [fetchTimeout]. Never throws;
  /// failures keep the active value. While an SDK call is still running
  /// (even past the timeout), a new refresh waits for that call instead of
  /// starting another one.
  Future<void> refresh() {
    var call = _inFlight;
    if (call == null) {
      final started = Future<bool>.sync(
        _client.fetchAndActivate,
      ).then<void>((_) {}, onError: (Object _) => _logger.fine('fetch failed'));
      _inFlight = call = started;
      unawaited(
        started.whenComplete(() {
          if (identical(_inFlight, started)) {
            _inFlight = null;
          }
        }),
      );
    }
    return call.timeout(
      fetchTimeout,
      onTimeout: () => _logger.fine('fetch timed out'),
    );
  }

  /// The active value, parsed. Synchronous; never throws. An invalid value
  /// gives [EngineParamsOverride.invalid] (engine defaults) and one
  /// `remoteConfigInvalid` non-fatal per session, without the value.
  @override
  EngineParamsOverride current() {
    String raw;
    try {
      raw = _client.getString(kTripEngineParamsKey);
    } on Object {
      raw = '';
    }
    final parsed = parseEngineParamsOverride(raw);
    if (parsed == EngineParamsOverride.invalid && !_reportedInvalid) {
      _reportedInvalid = true;
      _crash?.recordNonFatal(
        const RemoteConfigInvalid(),
        null,
        NonFatalReason.remoteConfigInvalid,
      );
    }
    return parsed;
  }
}
