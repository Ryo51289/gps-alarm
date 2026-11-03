import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent.dart';

/// Stored consent (T29 §7, review round 3 R3-2): ONE string key, so a
/// single `setString` replaces the whole answer at once and a crash in the
/// middle of a write can never leave a mix of old and new values.
///
/// Value: `crash=<c>;analytics=<a>;version=<n>` with `<c>`, `<a>` in
/// `granted` | `denied` | `unknown`. Earlier builds of T29 used three keys
/// ([crashKey], [analyticsKey], [versionKey]); they are read only while the
/// single key is absent, and the first successful [write] supersedes them
/// (the single key always wins).
final class TelemetryConsentStore {
  new(this._kv);

  final KeyValueStore _kv;

  static const String consentKey = 'telemetry.consent';

  /// Legacy keys (read-only).
  static const String crashKey = 'telemetry.crash';
  static const String analyticsKey = 'telemetry.analytics';
  static const String versionKey = 'telemetry.consent_version';

  static ConsentChoice _choiceOf(String? raw) => switch (raw) {
    'granted' => ConsentChoice.granted,
    'denied' => ConsentChoice.denied,
    _ => ConsentChoice.unknown,
  };

  static final RegExp _format = RegExp(
    '^crash=(granted|denied|unknown);analytics=(granted|denied|unknown);'
    r'version=(\d{1,9})$',
  );

  /// The stored form of [c].
  static String encode(TelemetryConsent c) =>
      'crash=${c.crash.name};analytics=${c.analytics.name};'
      'version=${c.version}';

  /// [raw] of the single key; a malformed value → [TelemetryConsent.initial]
  /// (collect nothing, ask again), never the legacy keys.
  static TelemetryConsent decode(String raw) {
    final m = _format.firstMatch(raw);
    if (m == null) {
      return TelemetryConsent.initial;
    }
    return TelemetryConsent(
      crash: _choiceOf(m[1]),
      analytics: _choiceOf(m[2]),
      version: int.parse(m[3]!),
    );
  }

  /// The single key; the legacy keys only when it is absent. Both reads
  /// start together, so a legacy-only store costs no extra round trip, and
  /// a present single key answers without waiting for the legacy keys.
  /// Unknown values → unknown; any read error → [TelemetryConsent.initial].
  Future<TelemetryConsent> read() async {
    try {
      // Not awaited when the single key answers: its error is ignored.
      final legacy = _readLegacy()..ignore();
      final single = await _kv.getString(consentKey);
      if (single != null) {
        return decode(single);
      }
      return await legacy;
    } on Object {
      return TelemetryConsent.initial;
    }
  }

  Future<TelemetryConsent> _readLegacy() async {
    final crash = await _kv.getString(crashKey);
    final analytics = await _kv.getString(analyticsKey);
    final version = await _kv.getInt(versionKey);
    return TelemetryConsent(
      crash: _choiceOf(crash),
      analytics: _choiceOf(analytics),
      version: version ?? 0,
    );
  }

  /// One atomic `setString` of the whole answer. Errors propagate.
  Future<void> write(TelemetryConsent c) =>
      _kv.setString(consentKey, encode(c));
}
