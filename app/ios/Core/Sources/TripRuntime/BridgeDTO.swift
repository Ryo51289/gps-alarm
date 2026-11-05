// Engine/runtime → Pigeon, the half with logic (docs/specs/T17.md §4.6, D20). Same rules as Android MsgMapper.kt (L34).
// Runner/MsgMapper.swift only copies these into the Pigeon classes (Pigeon Swift imports Flutter: not buildable on Linux).
import Trip

public enum BatteryChoiceDTO: Sendable, Equatable { case maxSaving, alarmAt5, alarmEarlier }

/// Fields of TripStateMsg (T14 §3.1).
public struct TripStateDTO: Sendable, Equatable {
    public let tripId: String
    public let atMs: Int64
    public let phase: TripPhase
    public let gps: GpsStatus
    public let locationCause: AvailabilityCause
    public let distanceM: Int64?
    public let routeDistanceEstM: Int64?
    public let distanceErrorM: Int64?
    public let isEstimated: Bool
    public let etaS: Int64?
    public let etaMinS: Int64?
    public let etaMaxS: Int64?
    public let speedKmh: Double?
    public let progress: Double?
    public let alarmMarkerProgress: Double?
    public let predictedAlarmAtMs: Int64?
    public let samplingTier: SamplingTier?
    public let fallbackAtMs: Int64?
    /// `.notSet` ↔ FallbackStatusMsg.notSet.
    public let fallbackStatus: FallbackStatus
    public let batteryPct: Int64?
    public let batteryRisk: Bool
    public let batteryChoice: BatteryChoiceDTO?
    public let preAlertFired: Bool
    public let alarmAtMs: Int64?
    public let alarmReason: AlarmReason?
    public let alarmRinging: Bool
    public let snoozeCount: Int64
    public let snoozeUntilMs: Int64?
    public let overshootPastM: Int64?
    public let outcome: TripOutcome?
    public let vehicleGuess: VehicleKind
    public let travelledM: Int64
}

/// = FinishedTripMsg.
public struct FinishedTripDTO: Sendable, Equatable {
    public let tripId: String
    public let outcome: TripOutcome
    public let endReason: EndReason
    public let endedAtMs: Int64
    public let startedAtMs: Int64
    public let alarmAtMs: Int64?
    public let alarmReason: AlarmReason?
    public let dismissedAtMs: Int64?
    public let snoozeCount: Int64
    public let travelledM: Int64
    public let vehicleGuess: VehicleKind
}

/// 1–1 with the subclasses of TripUpdateMsg.
public enum TripUpdateDTO: Sendable, Equatable {
    case state(TripStateDTO)
    case preAlert(tripId: String, atMs: Int64, distanceM: Int64, etaS: Int64?)
    case alarm(tripId: String, atMs: Int64, reason: AlarmReason, ringNow: Bool, snoozeAllowed: Bool, distanceM: Int64?,
               etaS: Int64?, batteryPct: Int64?)
    case snoozed(tripId: String, atMs: Int64, untilMs: Int64)
    case gpsLost(tripId: String, atMs: Int64, cause: GpsLostCause, lastFixAgeS: Int64?)
    case gpsRecovered(tripId: String, atMs: Int64, lostForS: Int64)
    case lowBatteryRisk(tripId: String, atMs: Int64, levelPct: Int64, availableMin: Int64, neededMin: Int64)
    case overshoot(tripId: String, atMs: Int64, pastM: Int64)
    case arrived(tripId: String, atMs: Int64, distanceM: Int64)
    case tripEnded(atMs: Int64, trip: FinishedTripDTO)
}

public enum BridgeMapper {
    public static func batteryChoice(_ k: UserActionKind?) -> BatteryChoiceDTO? {
        switch k {
        case .batteryMaxSaving: .maxSaving
        case .batteryAlarmAt5: .alarmAt5
        case .batteryAlarmEarlier: .alarmEarlier
        default: nil
        }
    }

    public static func batteryAction(_ c: BatteryChoiceDTO) -> UserActionKind {
        switch c {
        case .maxSaving: .batteryMaxSaving
        case .alarmAt5: .batteryAlarmAt5
        case .alarmEarlier: .batteryAlarmEarlier
        }
    }

    private static func l(_ v: Int?) -> Int64? { v.map { Int64($0) } }

    public static func state(view v: TripView, batteryChoice: UserActionKind?) -> TripStateDTO {
        TripStateDTO(
            tripId: v.tripId, atMs: v.atMs, phase: v.phase, gps: v.gps, locationCause: v.locationCause,
            distanceM: l(v.distanceM), routeDistanceEstM: l(v.routeDistanceEstM), distanceErrorM: l(v.distanceErrorM),
            isEstimated: v.isEstimated, etaS: l(v.etaS), etaMinS: l(v.etaMinS), etaMaxS: l(v.etaMaxS), speedKmh: v.speedKmh,
            progress: v.progress, alarmMarkerProgress: v.alarmMarkerProgress, predictedAlarmAtMs: v.predictedAlarmAtMs,
            samplingTier: v.samplingPolicy?.tier, fallbackAtMs: v.fallbackAtMs, fallbackStatus: v.fallbackStatus,
            batteryPct: l(v.batteryPct), batteryRisk: v.batteryRisk, batteryChoice: Self.batteryChoice(batteryChoice),
            preAlertFired: v.preAlertFired, alarmAtMs: v.alarmAtMs, alarmReason: v.alarmReason, alarmRinging: v.alarmRinging,
            snoozeCount: Int64(v.snoozeCount), snoozeUntilMs: v.snoozeUntilMs, overshootPastM: l(v.overshootPastM),
            outcome: v.outcome, vehicleGuess: v.vehicleGuess, travelledM: Int64(v.travelledM))
    }

    /// One Step: `.state` first, then the events in engine order minus SamplingPolicyChanged/FallbackAlarmChanged.
    public static func updates(tripId: String, view: TripView, batteryChoice: UserActionKind?, events: [TripEvent])
        -> [TripUpdateDTO] {
        var out: [TripUpdateDTO] = [.state(state(view: view, batteryChoice: batteryChoice))]
        for e in events { if let u = event(tripId: tripId, e) { out.append(u) } }
        return out
    }

    public static func event(tripId: String, _ e: TripEvent) -> TripUpdateDTO? {
        switch e {
        case let .preAlert(x): .preAlert(tripId: tripId, atMs: x.atMs, distanceM: Int64(x.distanceM), etaS: l(x.etaS))
        case let .alarm(x):
            .alarm(tripId: tripId, atMs: x.atMs, reason: x.reason, ringNow: x.ringNow, snoozeAllowed: x.snoozeAllowed,
                   distanceM: l(x.distanceM), etaS: l(x.etaS), batteryPct: l(x.batteryPct))
        case let .snoozed(x): .snoozed(tripId: tripId, atMs: x.atMs, untilMs: x.untilMs)
        case let .gpsLost(x): .gpsLost(tripId: tripId, atMs: x.atMs, cause: x.cause, lastFixAgeS: l(x.lastFixAgeS))
        case let .gpsRecovered(x): .gpsRecovered(tripId: tripId, atMs: x.atMs, lostForS: Int64(x.lostForS))
        case let .lowBatteryRisk(x):
            .lowBatteryRisk(tripId: tripId, atMs: x.atMs, levelPct: Int64(x.levelPct), availableMin: Int64(x.availableMin),
                            neededMin: Int64(x.neededMin))
        case let .overshoot(x): .overshoot(tripId: tripId, atMs: x.atMs, pastM: Int64(x.pastM))
        case let .arrived(x): .arrived(tripId: tripId, atMs: x.atMs, distanceM: Int64(x.distanceM))
        case let .tripEnded(x):
            .tripEnded(atMs: x.atMs, trip: FinishedTripDTO(
                tripId: tripId, outcome: x.outcome, endReason: x.endReason, endedAtMs: x.atMs,
                startedAtMs: x.summary.startedAtMs, alarmAtMs: x.summary.alarmAtMs, alarmReason: x.summary.alarmReason,
                dismissedAtMs: x.summary.dismissedAtMs, snoozeCount: Int64(x.summary.snoozeCount),
                travelledM: Int64(x.summary.travelledM), vehicleGuess: x.summary.vehicleGuess))
        case .samplingPolicyChanged, .fallbackAlarmChanged: nil
        }
    }

    public static func finished(_ r: FinishedRecord) -> FinishedTripDTO? {
        guard let o = TripOutcome(jsonName: r.outcome), let e = EndReason(jsonName: r.endReason) else { return nil }
        return FinishedTripDTO(tripId: r.tripId, outcome: o, endReason: e, endedAtMs: r.endedAtMs, startedAtMs: r.startedAtMs,
                               alarmAtMs: r.alarmAtMs, alarmReason: r.alarmReason.flatMap(AlarmReason.init(jsonName:)),
                               dismissedAtMs: r.dismissedAtMs, snoozeCount: Int64(r.snoozeCount),
                               travelledM: Int64(r.travelledM),
                               vehicleGuess: VehicleKind(jsonName: r.vehicleGuess) ?? .unknown)
    }
}
