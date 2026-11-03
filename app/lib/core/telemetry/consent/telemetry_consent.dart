/// Consent rules of T29 §7. Pure Dart.
///
/// PO decision Q2 (01/11/2026): opt-in. Nothing is collected until the user
/// agrees; the dialog (T21) and the two switches of screen 12 (T28) write
/// through `TelemetryConsentController`.
library;

import 'package:meta/meta.dart';
import 'package:napstop/app/flavor.dart';

enum ConsentChoice { unknown, granted, denied }

@immutable
final class TelemetryConsent {
  const new({
    required this.crash,
    required this.analytics,
    required this.version,
  });

  final ConsentChoice crash;
  final ConsentChoice analytics;

  /// [kConsentTextVersion] of the dialog the user answered; 0 = never.
  final int version;

  static const TelemetryConsent initial = TelemetryConsent(
    crash: ConsentChoice.unknown,
    analytics: ConsentChoice.unknown,
    version: 0,
  );

  TelemetryConsent copyWith({
    ConsentChoice? crash,
    ConsentChoice? analytics,
    int? version,
  }) => TelemetryConsent(
    crash: crash ?? this.crash,
    analytics: analytics ?? this.analytics,
    version: version ?? this.version,
  );

  @override
  bool operator ==(Object other) =>
      other is TelemetryConsent &&
      other.crash == crash &&
      other.analytics == analytics &&
      other.version == version;

  @override
  int get hashCode => Object.hash(crash, analytics, version);

  @override
  String toString() =>
      'TelemetryConsent(${crash.name}, ${analytics.name}, v$version)';
}

/// Version of the consent text; raising it asks everyone again.
const int kConsentTextVersion = 1;

/// Q2 = opt-in: an unanswered (or outdated) consent collects nothing.
const bool kCollectWhenUnknown = false;

/// `--dart-define=NAPSTOP_TELEMETRY=auto|on|off` (default auto). `on` only
/// works in dev (payload checks, T29 §8); prod treats it as auto.
enum TelemetryOverride {
  auto,
  on,
  off;

  /// Unknown values → [auto].
  static TelemetryOverride parse(String? raw) => switch (raw) {
    'on' => on,
    'off' => off,
    _ => auto,
  };

  /// The value of this build.
  static final TelemetryOverride fromEnvironment = parse(
    const String.fromEnvironment('NAPSTOP_TELEMETRY'),
  );
}

/// What is actually collected right now.
@immutable
final class EffectiveCollection {
  const new({required this.crash, required this.analytics});

  final bool crash;
  final bool analytics;

  static const EffectiveCollection none = EffectiveCollection(
    crash: false,
    analytics: false,
  );

  @override
  bool operator ==(Object other) =>
      other is EffectiveCollection &&
      other.crash == crash &&
      other.analytics == analytics;

  @override
  int get hashCode => Object.hash(crash, analytics);

  @override
  String toString() => 'EffectiveCollection($crash, $analytics)';
}

bool _byChoice(ConsentChoice c, int version) => switch (c) {
  ConsentChoice.granted =>
    version >= kConsentTextVersion || kCollectWhenUnknown,
  ConsentChoice.denied => false,
  ConsentChoice.unknown => kCollectWhenUnknown,
};

/// In order: [TelemetryOverride.off] → nothing; `on` in dev → everything
/// (prod: `on` = auto); a debug build in auto → nothing; otherwise per kind:
/// granted with a current version → on, denied → off, unknown or an
/// outdated version → [kCollectWhenUnknown].
EffectiveCollection resolveCollection({
  required TelemetryConsent consent,
  required AppFlavor flavor,
  required bool isDebugBuild,
  required TelemetryOverride override,
}) {
  if (override == TelemetryOverride.off) {
    return EffectiveCollection.none;
  }
  if (override == TelemetryOverride.on && flavor == AppFlavor.dev) {
    return const EffectiveCollection(crash: true, analytics: true);
  }
  if (isDebugBuild) {
    return EffectiveCollection.none;
  }
  return EffectiveCollection(
    crash: _byChoice(consent.crash, consent.version),
    analytics: _byChoice(consent.analytics, consent.version),
  );
}

/// The consent dialog is due: a kind is unanswered or the text changed.
bool needsConsentPrompt(TelemetryConsent c) =>
    c.crash == ConsentChoice.unknown ||
    c.analytics == ConsentChoice.unknown ||
    c.version < kConsentTextVersion;
