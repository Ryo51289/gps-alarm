import Foundation
import Trip
import TripRuntime

/// BridgeDTO (NapStopCore, tested on Linux) → Pigeon classes (spec T17 §4.6, D20). Copy only: every rule
/// (enum names, rounding, samplingTier, batteryChoice, update order) lives in `BridgeMapper`.
enum MsgMapper {
  static func updates(tripId: String, view: TripView, batteryChoice: UserActionKind?, events: [TripEvent])
    -> [TripUpdateMsg]
  {
    BridgeMapper.updates(tripId: tripId, view: view, batteryChoice: batteryChoice, events: events).map(msg)
  }

  static func msg(_ u: TripUpdateDTO) -> TripUpdateMsg {
    switch u {
    case .state(let s):
      return TripStateUpdateMsg(state: state(s))
    case .preAlert(let tripId, let atMs, let distanceM, let etaS):
      return PreAlertMsg(tripId: tripId, atMs: atMs, distanceM: distanceM, etaS: etaS)
    case .alarm(let tripId, let atMs, let reason, let ringNow, let snoozeAllowed, let distanceM, let etaS, let batteryPct):
      return AlarmMsg(
        tripId: tripId, atMs: atMs, reason: self.reason(reason), ringNow: ringNow, snoozeAllowed: snoozeAllowed,
        distanceM: distanceM, etaS: etaS, batteryPct: batteryPct)
    case .snoozed(let tripId, let atMs, let untilMs):
      return SnoozedMsg(tripId: tripId, atMs: atMs, untilMs: untilMs)
    case .gpsLost(let tripId, let atMs, let cause, let lastFixAgeS):
      return GpsLostMsg(tripId: tripId, atMs: atMs, cause: gpsLostCause(cause), lastFixAgeS: lastFixAgeS)
    case .gpsRecovered(let tripId, let atMs, let lostForS):
      return GpsRecoveredMsg(tripId: tripId, atMs: atMs, lostForS: lostForS)
    case .lowBatteryRisk(let tripId, let atMs, let levelPct, let availableMin, let neededMin):
      return LowBatteryRiskMsg(
        tripId: tripId, atMs: atMs, levelPct: levelPct, availableMin: availableMin, neededMin: neededMin)
    case .overshoot(let tripId, let atMs, let pastM):
      return OvershootMsg(tripId: tripId, atMs: atMs, pastM: pastM)
    case .arrived(let tripId, let atMs, let distanceM):
      return ArrivedMsg(tripId: tripId, atMs: atMs, distanceM: distanceM)
    case .tripEnded(let atMs, let trip):
      return TripEndedMsg(atMs: atMs, trip: finished(trip))
    }
  }

  static func state(_ s: TripStateDTO) -> TripStateMsg {
    TripStateMsg(
      tripId: s.tripId, atMs: s.atMs, phase: phase(s.phase), gps: gps(s.gps), locationCause: cause(s.locationCause),
      distanceM: s.distanceM, routeDistanceEstM: s.routeDistanceEstM, distanceErrorM: s.distanceErrorM,
      isEstimated: s.isEstimated, etaS: s.etaS, etaMinS: s.etaMinS, etaMaxS: s.etaMaxS, speedKmh: s.speedKmh,
      progress: s.progress, alarmMarkerProgress: s.alarmMarkerProgress, predictedAlarmAtMs: s.predictedAlarmAtMs,
      samplingTier: s.samplingTier.map(tier), fallbackAtMs: s.fallbackAtMs, fallbackStatus: fallback(s.fallbackStatus),
      batteryPct: s.batteryPct, batteryRisk: s.batteryRisk, batteryChoice: s.batteryChoice.map(choice),
      preAlertFired: s.preAlertFired, alarmAtMs: s.alarmAtMs, alarmReason: s.alarmReason.map(reason),
      alarmRinging: s.alarmRinging, snoozeCount: s.snoozeCount, snoozeUntilMs: s.snoozeUntilMs,
      overshootPastM: s.overshootPastM, outcome: s.outcome.map(outcome), vehicleGuess: vehicle(s.vehicleGuess),
      travelledM: s.travelledM)
  }

  static func finished(_ f: FinishedTripDTO) -> FinishedTripMsg {
    FinishedTripMsg(
      tripId: f.tripId, outcome: outcome(f.outcome), endReason: endReason(f.endReason), endedAtMs: f.endedAtMs,
      startedAtMs: f.startedAtMs, alarmAtMs: f.alarmAtMs, alarmReason: f.alarmReason.map(reason),
      dismissedAtMs: f.dismissedAtMs, snoozeCount: f.snoozeCount, travelledM: f.travelledM,
      vehicleGuess: vehicle(f.vehicleGuess))
  }

  /// TripConfigMsg → coordinate-free runtime meta (validated first by TripConfigValidator).
  static func meta(_ c: TripConfigMsg) -> TripMeta {
    TripMeta(
      tripId: c.tripId, destinationName: c.destinationName, mode: mode(c.mode),
      distanceThresholdM: c.distanceThresholdM.map { Int(clamping: $0) },
      timeThresholdMin: c.timeThresholdMin.map { Int(clamping: $0) }, preAlertEnabled: c.preAlertEnabled,
      vehicleHint: vehicleKind(c.vehicleHint),
      alarm: RingSettings(
        soundId: c.alarm.soundId, volume: c.alarm.volume, rampUp: c.alarm.rampUp,
        vibration: vibrationName(c.alarm.vibration), flash: c.alarm.flash,
        preferHeadphones: c.alarm.preferHeadphones, dismissMethod: dismissName(c.alarm.dismissMethod)),
      engineParamsJson: c.engineParamsJson)
  }

  /// Inverse of `meta` (currentTrip echoes what startTrip received, T14 review M4).
  static func config(_ m: TripMeta) -> TripConfigMsg {
    TripConfigMsg(
      tripId: m.tripId, destinationName: m.destinationName, mode: alarmMode(m.mode),
      distanceThresholdM: m.distanceThresholdM.map { Int64($0) }, timeThresholdMin: m.timeThresholdMin.map { Int64($0) },
      preAlertEnabled: m.preAlertEnabled, vehicleHint: vehicle(m.vehicleHint),
      alarm: AlarmSettingsMsg(
        soundId: m.alarm.soundId, volume: m.alarm.volume, rampUp: m.alarm.rampUp,
        vibration: vibration(m.alarm.vibration), flash: m.alarm.flash, preferHeadphones: m.alarm.preferHeadphones,
        dismissMethod: dismiss(m.alarm.dismissMethod)),
      engineParamsJson: m.engineParamsJson)
  }

  static func phase(_ p: TripPhase) -> TripPhaseMsg {
    switch p {
    case .acquiring: return .acquiring
    case .tracking: return .tracking
    case .alarming: return .alarming
    case .snoozed: return .snoozed
    case .overshot: return .overshot
    case .ended: return .ended
    }
  }

  static func gps(_ g: GpsStatus) -> GpsStatusMsg {
    switch g {
    case .noFixYet: return .noFixYet
    case .ok: return .ok
    case .lost: return .lost
    }
  }

  static func cause(_ c: AvailabilityCause) -> AvailabilityCauseMsg {
    switch c {
    case .available: return .available
    case .permissionRevoked: return .permissionRevoked
    case .servicesOff: return .servicesOff
    }
  }

  static func tier(_ t: SamplingTier) -> SamplingTierMsg {
    switch t {
    case .sparse: return .sparse
    case .medium: return .medium
    case .dense: return .dense
    }
  }

  static func fallback(_ f: FallbackStatus) -> FallbackStatusMsg {
    switch f {
    case .notSet: return .notSet
    case .requested: return .requested
    case .confirmed: return .confirmed
    case .failed: return .failed
    }
  }

  static func choice(_ c: BatteryChoiceDTO) -> BatteryChoiceMsg {
    switch c {
    case .maxSaving: return .maxSaving
    case .alarmAt5: return .alarmAt5
    case .alarmEarlier: return .alarmEarlier
    }
  }

  static func choiceDTO(_ c: BatteryChoiceMsg) -> BatteryChoiceDTO {
    switch c {
    case .maxSaving: return .maxSaving
    case .alarmAt5: return .alarmAt5
    case .alarmEarlier: return .alarmEarlier
    }
  }

  static func reason(_ r: AlarmReason) -> AlarmReasonMsg {
    switch r {
    case .distance: return .distance
    case .time: return .time
    case .smartTime: return .smartTime
    case .smartDistance: return .smartDistance
    case .smartSlowDistance: return .smartSlowDistance
    case .gpsLost: return .gpsLost
    case .lowBattery: return .lowBattery
    case .passedClosest: return .passedClosest
    case .overshoot: return .overshoot
    case .snoozeEnd: return .snoozeEnd
    case .timeout: return .timeout
    case .fallback: return .fallback
    case .fallbackMissed: return .fallbackMissed
    }
  }

  static func gpsLostCause(_ c: GpsLostCause) -> GpsLostCauseMsg {
    switch c {
    case .noFixTimeout: return .noFixTimeout
    case .neverAcquired: return .neverAcquired
    case .permissionRevoked: return .permissionRevoked
    case .servicesOff: return .servicesOff
    }
  }

  static func outcome(_ o: TripOutcome) -> TripOutcomeMsg {
    switch o {
    case .onTime: return .onTime
    case .snoozed: return .snoozed
    case .missed: return .missed
    case .cancelled: return .cancelled
    }
  }

  static func endReason(_ e: EndReason) -> EndReasonMsg {
    switch e {
    case .dismissed: return .dismissed
    case .userStop: return .userStop
    case .alarmUnanswered: return .alarmUnanswered
    }
  }

  static func vehicle(_ v: VehicleKind) -> VehicleKindMsg {
    switch v {
    case .train: return .train
    case .coach: return .coach
    case .bus: return .bus
    case .unknown: return .unknown
    }
  }

  static func vehicleKind(_ v: VehicleKindMsg) -> VehicleKind {
    switch v {
    case .train: return .train
    case .coach: return .coach
    case .bus: return .bus
    case .unknown: return .unknown
    }
  }

  static func mode(_ m: AlarmModeMsg) -> AlarmMode {
    switch m {
    case .distance: return .distance
    case .time: return .time
    case .smart: return .smart
    }
  }

  static func alarmMode(_ m: AlarmMode) -> AlarmModeMsg {
    switch m {
    case .distance: return .distance
    case .time: return .time
    case .smart: return .smart
    }
  }

  static func vibrationName(_ v: VibrationMsg) -> String {
    switch v {
    case .off: return "off"
    case .light: return "light"
    case .medium: return "medium"
    case .strong: return "strong"
    }
  }

  static func vibration(_ s: String) -> VibrationMsg {
    switch s {
    case "off": return .off
    case "light": return .light
    case "strong": return .strong
    default: return .medium
    }
  }

  static func dismissName(_ d: DismissMethodMsg) -> String {
    switch d {
    case .swipe: return "swipe"
    case .shake: return "shake"
    case .math: return "math"
    }
  }

  static func dismiss(_ s: String) -> DismissMethodMsg {
    switch s {
    case "shake": return .shake
    case "math": return .math
    default: return .swipe
    }
  }
}
