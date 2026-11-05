// Finished trip record (= FinishedTripMsg, T14 §3.1) and the few engine-state facts the runtime reads (§5.7, §5.8).
import Foundation
import Trip

public struct FinishedRecord: Sendable, Codable, Equatable {
    public let tripId: String
    /// TripOutcome JSON name (ON_TIME, …).
    public let outcome: String
    /// EndReason JSON name.
    public let endReason: String
    public let endedAtMs: Int64
    public let startedAtMs: Int64
    public let alarmAtMs: Int64?
    /// AlarmReason JSON name.
    public let alarmReason: String?
    public let dismissedAtMs: Int64?
    public let snoozeCount: Int
    public let travelledM: Int
    /// VehicleKind JSON name.
    public let vehicleGuess: String

    public init(tripId: String, outcome: String, endReason: String, endedAtMs: Int64, startedAtMs: Int64, alarmAtMs: Int64?,
                alarmReason: String?, dismissedAtMs: Int64?, snoozeCount: Int, travelledM: Int, vehicleGuess: String) {
        self.tripId = tripId
        self.outcome = outcome
        self.endReason = endReason
        self.endedAtMs = endedAtMs
        self.startedAtMs = startedAtMs
        self.alarmAtMs = alarmAtMs
        self.alarmReason = alarmReason
        self.dismissedAtMs = dismissedAtMs
        self.snoozeCount = snoozeCount
        self.travelledM = travelledM
        self.vehicleGuess = vehicleGuess
    }
}

/// The engine state fields the runtime needs (fallback target, phase, last alarm reason, ended summary). `EngineState`
/// keeps its fields internal to module `Trip` (T13 D3) and T17 does not change the engine, so they are read from the
/// snapshot JSON, whose format is the stable T10 §7.1 contract. Never logged (the snapshot has coordinates; these
/// fields do not).
public struct EngineFacts: Sendable, Equatable {
    public let tripId: String
    public let nowMs: Int64
    public let startedAtMs: Int64
    public let phase: TripPhase
    public let fallbackTargetAtMs: Int64?
    public let alarmAtMs: Int64?
    public let alarmReason: AlarmReason?
    public let alarmLastReason: AlarmReason?
    public let alarmRinging: Bool
    public let snoozeCount: Int
    public let dismissedAtMs: Int64?
    public let movingTimeS: Double
    public let movingDistM: Double
    public let vehicleHint: VehicleKind
    public let vehicleBusMaxAvgKmh: Int
    public let ended: (outcome: TripOutcome, endReason: EndReason, atMs: Int64)?
    /// alarm.lastRingAtMs (spec R2: alarmWall when no "now" is in the ledger, and the silenced-at floor).
    public var alarmLastRingAtMs: Int64? = nil

    public static func == (a: EngineFacts, b: EngineFacts) -> Bool {
        a.tripId == b.tripId && a.nowMs == b.nowMs && a.phase == b.phase && a.fallbackTargetAtMs == b.fallbackTargetAtMs
            && a.alarmLastReason == b.alarmLastReason && a.ended?.atMs == b.ended?.atMs
    }

    private struct Snap: Decodable {
        struct Config: Decodable { var tripId: String; var vehicleHint: String }
        struct Params: Decodable { var vehicleBusMaxAvgKmh: Int? }
        struct AlarmS: Decodable {
            var atMs: Int64?; var reason: String?; var lastReason: String?; var lastRingAtMs: Int64?; var ringing: Bool
            var snoozeCount: Int
            var dismissedAtMs: Int64?
        }
        struct Fallback: Decodable { var targetAtMs: Int64? }
        struct Ended: Decodable { var outcome: String; var endReason: String; var atMs: Int64 }
        var params: Params
        var config: Config
        var nowMs: Int64
        var startedAtMs: Int64
        var phase: String
        var movingTimeS: Double
        var movingDistM: Double
        var alarm: AlarmS
        var fallback: Fallback
        var ended: Ended?
    }

    public static func read(_ state: EngineState) -> EngineFacts? { read(snapshot: TripEngine.encodeSnapshot(state)) }

    public static func read(snapshot: String) -> EngineFacts? {
        guard let s = try? JSONDecoder().decode(Snap.self, from: Data(snapshot.utf8)),
              let phase = TripPhase(jsonName: s.phase) else { return nil }
        var ended: (TripOutcome, EndReason, Int64)?
        if let e = s.ended, let o = TripOutcome(jsonName: e.outcome), let r = EndReason(jsonName: e.endReason) {
            ended = (o, r, e.atMs)
        }
        return EngineFacts(
            tripId: s.config.tripId, nowMs: s.nowMs, startedAtMs: s.startedAtMs, phase: phase,
            fallbackTargetAtMs: s.fallback.targetAtMs, alarmAtMs: s.alarm.atMs,
            alarmReason: s.alarm.reason.flatMap(AlarmReason.init(jsonName:)),
            alarmLastReason: s.alarm.lastReason.flatMap(AlarmReason.init(jsonName:)), alarmRinging: s.alarm.ringing,
            snoozeCount: s.alarm.snoozeCount, dismissedAtMs: s.alarm.dismissedAtMs, movingTimeS: s.movingTimeS,
            movingDistM: s.movingDistM, vehicleHint: VehicleKind(jsonName: s.config.vehicleHint) ?? .unknown,
            vehicleBusMaxAvgKmh: s.params.vehicleBusMaxAvgKmh ?? EngineParams.defaults.vehicleBusMaxAvgKmh, ended: ended,
            alarmLastRingAtMs: s.alarm.lastRingAtMs)
    }
}

public enum FinishedRecordBuilder {
    public static func fromEvent(tripId: String, _ e: TripEvent.TripEnded) -> FinishedRecord {
        FinishedRecord(tripId: tripId, outcome: e.outcome.jsonName, endReason: e.endReason.jsonName, endedAtMs: e.atMs,
                       startedAtMs: e.summary.startedAtMs, alarmAtMs: e.summary.alarmAtMs,
                       alarmReason: e.summary.alarmReason?.jsonName, dismissedAtMs: e.summary.dismissedAtMs,
                       snoozeCount: e.summary.snoozeCount, travelledM: e.summary.travelledM,
                       vehicleGuess: e.summary.vehicleGuess.jsonName)
    }

    /// = T15 FinishedRecordBuilder.fromEnded: same values as the engine's TripEnded.summary (T10 §4.14); nil unless ENDED.
    public static func fromEnded(_ s: EngineState) -> FinishedRecord? {
        guard let f = EngineFacts.read(s) else { return nil }
        return fromEnded(f)
    }

    public static func fromEnded(_ f: EngineFacts) -> FinishedRecord? {
        guard let ended = f.ended, f.phase == .ended else { return nil }
        return FinishedRecord(
            tripId: f.tripId, outcome: ended.outcome.jsonName, endReason: ended.endReason.jsonName, endedAtMs: ended.atMs,
            startedAtMs: f.startedAtMs, alarmAtMs: f.alarmAtMs, alarmReason: f.alarmReason?.jsonName,
            dismissedAtMs: ended.endReason == .dismissed ? f.dismissedAtMs : nil, snoozeCount: f.snoozeCount,
            travelledM: Int((f.movingDistM + 0.5).rounded(.down)),
            vehicleGuess: vehicleGuess(f.movingTimeS, f.movingDistM, f.vehicleHint, f.vehicleBusMaxAvgKmh).jsonName)
    }

    /// Copy of the engine's internal vehicleGuess (ViewBuilder, T10 §4.14); IU21 compares both.
    static func vehicleGuess(_ movingTimeS: Double, _ movingDistM: Double, _ hint: VehicleKind, _ busMaxKmh: Int) -> VehicleKind {
        if movingTimeS > 0.0 && movingDistM / movingTimeS * 3.6 < Double(busMaxKmh) { return .bus }
        if hint == .train || hint == .coach { return hint }
        return .unknown
    }
}
