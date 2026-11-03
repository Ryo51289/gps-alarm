import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/safe_call.dart';

/// First wait before retrying a failed consent write; doubles up to
/// [kConsentRetryMaxBackoff].
const Duration kConsentRetryBackoff = Duration(seconds: 5);
const Duration kConsentRetryMaxBackoff = Duration(minutes: 10);

/// Holds the consent and applies it to the SDKs (T29 §7). Used by the
/// consent dialog (T21) and the switches of screen 12 (T28); listeners are
/// notified after each [update].
///
/// Ordering (test report Lần 2 #2, review round 3 R3-1): an answer changes
/// [current]/[effective] synchronously; then two serial queues bring the
/// SDKs and the store to the LATEST state at the time each step runs. So
/// however calls interleave, the last answer wins in the SDKs and on disk,
/// and an SDK switch never waits for a slow disk write.
///
/// Changing consent never rebuilds a provider: the object stays the same
/// for the whole session (T25 review R2-2).
final class TelemetryConsentController extends ChangeNotifier {
  new({
    required this._store,
    required TelemetryConsent consent,
    required this._crashSink,
    required this._analyticsSink,
    required this.flavor,
    required this.isDebugBuild,
    required this.override,
    this._loaded = true,
    int Function()? nowMs,
  }) : _consent = consent,
       _nowMs = nowMs ?? _wallClockMs {
    _effective = _resolve(consent);
    // Until [applyInitial]: the SDKs are assumed to match (manifest
    // defaults are off; bootstrap applies the real state before use).
    _appliedCrash = _effective.crash;
    _appliedAnalytics = _effective.analytics;
  }

  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  static final Logger _logger = AppLog.named('telemetry.consent');

  final TelemetryConsentStore _store;
  final CrashSink _crashSink;
  final AnalyticsSink _analyticsSink;
  final AppFlavor flavor;
  final bool isDebugBuild;
  final TelemetryOverride override;
  final int Function() _nowMs;

  TelemetryConsent _consent;
  late EffectiveCollection _effective;
  bool _loaded;
  bool _answered = false;

  /// What each SDK was last set to.
  late bool _appliedCrash;
  late bool _appliedAnalytics;

  /// A first crash decline whose pending reports are still to delete (O1).
  bool _deletePending = false;

  /// Answer revision, and the last one stored successfully.
  int _revision = 0;
  int _savedRevision = 0;

  /// Retry state after a failed write.
  Duration _backoff = kConsentRetryBackoff;
  int _nextRetryAtMs = 0;

  Future<void> _sdkQueue = Future<void>.value();
  Future<void> _saveQueue = Future<void>.value();

  TelemetryConsent get current => _consent;

  EffectiveCollection get effective => _effective;

  /// False while the stored consent is still being read (a slow read at
  /// startup, see [adoptLoaded]); [current] is then `initial`.
  bool get isLoaded => _loaded;

  /// The consent dialog is due. Never before the stored value is known: a
  /// user who declined must not be asked again because of a slow read.
  bool get needsPrompt => _loaded && needsConsentPrompt(_consent);

  /// An answer of this session is not on disk yet (a write failed).
  bool get hasUnsavedAnswer => _savedRevision < _revision;

  EffectiveCollection _resolve(TelemetryConsent c) => resolveCollection(
    consent: c,
    flavor: flavor,
    isDebugBuild: isDebugBuild,
    override: override,
  );

  /// Once at bootstrap. Collection flags follow [effective]; reports kept
  /// while crash consent was unknown are sent once it is on, deleted if it
  /// was denied, and kept otherwise.
  Future<void> applyInitial() => _enqueueSdk(() => _sync(absolute: true));

  /// Records the user's answer (version = [kConsentTextVersion]) and puts it
  /// in force AT ONCE (§7 "Thu hồi đồng ý: tắt ngay"; granting uses the same
  /// path): [current] and [effective] change before this returns its future.
  /// The returned future completes once the SDKs and the store caught up.
  ///
  /// SDK steps (what changed since the last applied state): on → enable
  /// (+ send pending crash reports); off → disable (+ delete pending crash
  /// reports / reset Analytics data). An explicit crash `denied` that
  /// changes the answer also deletes pending reports when collection was
  /// already off (first decline from unknown, test report O1).
  ///
  /// A failed write is retried once at once, then on each [retryUnsaved]
  /// (app resume) with a growing backoff and on the next [update], for the
  /// whole session; the error is logged by type only. The answer stays in
  /// force meanwhile and is never undone by a write failure.
  Future<void> update({ConsentChoice? crash, ConsentChoice? analytics}) {
    _answered = true;
    _loaded = true;
    final previous = _consent;
    _consent = _consent.copyWith(
      crash: crash,
      analytics: analytics,
      version: kConsentTextVersion,
    );
    _effective = _resolve(_consent);
    if (crash == ConsentChoice.denied &&
        previous.crash != ConsentChoice.denied) {
      _deletePending = true;
    }
    _revision++;
    final sdk = _enqueueSdk(() => _sync(absolute: false));
    final save = _enqueueSave(force: true);
    return Future.wait([sdk, save]).then((_) => notifyListeners());
  }

  /// The stored consent arrived after bootstrap gave up waiting: adopt it
  /// and apply it like at bootstrap, then notify. Ignored once loaded or
  /// once the user answered in this session (that answer is newer).
  Future<void> adoptLoaded(TelemetryConsent stored) {
    if (_loaded || _answered) {
      return Future<void>.value();
    }
    _consent = stored;
    _effective = _resolve(stored);
    _loaded = true;
    return _enqueueSdk(() => _sync(absolute: true))
        .then((_) => notifyListeners());
  }

  /// Retries an unsaved answer if its backoff has passed (app resume).
  Future<void> retryUnsaved() {
    if (!hasUnsavedAnswer || _nowMs() < _nextRetryAtMs) {
      return Future<void>.value();
    }
    return _enqueueSave(force: false);
  }

  Future<void> _enqueueSdk(Future<void> Function() step) {
    final next = _sdkQueue.then((_) => safeAwait(step));
    _sdkQueue = next;
    return next;
  }

  Future<void> _enqueueSave({required bool force}) {
    final next = _saveQueue.then((_) => safeAwait(() => _save(force: force)));
    _saveQueue = next;
    return next;
  }

  /// Brings each SDK to the LATEST [effective], read right before that
  /// SDK's calls (so a step that started for an older answer never enables
  /// anything a newer answer turned off; the newer answer's own step,
  /// queued behind, reconciles the rest). [absolute] (bootstrap, late read)
  /// sets both flags even if unchanged.
  ///
  /// Crashlytics: on → enable + send pending reports; off → disable +
  /// delete pending reports when it changed, at bootstrap when declined, or
  /// on a first decline (O1). Analytics: on → enable; off → disable + reset
  /// data when it changed.
  Future<void> _sync({required bool absolute}) async {
    final crash = _effective.crash;
    final crashChanged = crash != _appliedCrash;
    if (absolute || crashChanged) {
      _appliedCrash = crash;
      await safeAwait(() => _crashSink.setCollectionEnabled(enabled: crash));
      if (crash) {
        _deletePending = false;
        await _sendIfStillOn();
      } else if (crashChanged ||
          _deletePending ||
          _consent.crash == ConsentChoice.denied) {
        _deletePending = false;
        await _deleteIfStillOff();
      }
    } else if (crash) {
      _deletePending = false;
    } else if (_deletePending) {
      _deletePending = false;
      await _deleteIfStillOff();
    }

    final analytics = _effective.analytics;
    final analyticsChanged = analytics != _appliedAnalytics;
    if (absolute || analyticsChanged) {
      _appliedAnalytics = analytics;
      await safeAwait(
        () => _analyticsSink.setCollectionEnabled(enabled: analytics),
      );
      if (analyticsChanged && !analytics && !_effective.analytics) {
        await safeAwait(_analyticsSink.resetData);
      }
    }
  }

  /// Pending reports go out only if no newer answer turned crash reports
  /// off while the switch was in flight (and are deleted only if none
  /// turned them back on): the next queued step handles the newer answer.
  Future<void> _sendIfStillOn() async {
    if (_effective.crash) {
      await safeAwait(_crashSink.sendUnsentReports);
    }
  }

  Future<void> _deleteIfStillOff() async {
    if (!_effective.crash) {
      await safeAwait(_crashSink.deleteUnsentReports);
    }
  }

  /// Writes the LATEST answer unless it is already stored. Two attempts;
  /// a failure schedules the next try (backoff) and logs the type only.
  Future<void> _save({required bool force}) async {
    final revision = _revision;
    if (_savedRevision >= revision) {
      return;
    }
    if (!force && _nowMs() < _nextRetryAtMs) {
      return;
    }
    final snapshot = _consent;
    Object? failure;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _store.write(snapshot);
        failure = null;
        break;
      } on Object catch (error) {
        failure = error;
      }
    }
    if (failure == null) {
      if (revision > _savedRevision) {
        _savedRevision = revision;
      }
      _backoff = kConsentRetryBackoff;
      _nextRetryAtMs = 0;
      return;
    }
    _logger.warning('consent write failed: ${failure.runtimeType}');
    _nextRetryAtMs = _nowMs() + _backoff.inMilliseconds;
    final doubled = _backoff * 2;
    _backoff = doubled > kConsentRetryMaxBackoff
        ? kConsentRetryMaxBackoff
        : doubled;
  }
}
