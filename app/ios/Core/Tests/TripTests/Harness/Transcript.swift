@testable import Trip

/// Recorded input of a Step (T12 §9.2 `in`).
enum InRecord: Sendable, Equatable {
    case start
    case restore(nowMs: Int64, status: FallbackRestoreStatus, firedAtMs: Int64?, dismissedAtMs: Int64?)
    case input(EngineInput, fixIndex: Int?)
    case kill
}

struct StepRecord: Sendable {
    let t: Int
    let input: InRecord
    let events: [TripEvent]
    let view: TripView
    let v: String
}

/// P05 transcript writer, byte-exact T12 §9.2 (hand-built strings, fixed key order).
enum Transcript {
    static func rel(_ x: Int64, _ startMs: Int64) -> String { String(x - startMs) }
    static func relOpt(_ x: Int64?, _ startMs: Int64) -> String { x.map { String($0 - startMs) } ?? "null" }
    static func intOpt(_ x: Int?) -> String { x.map(String.init) ?? "null" }
    static func q(_ s: String) -> String { "\"" + s + "\"" }
    static func qOpt(_ s: String?) -> String { s.map(q) ?? "null" }

    static func policy(_ p: SamplingPolicy) -> String {
        "{\"tier\":\(q(p.tier.jsonName)),\"intervalS\":\(p.intervalS),\"minIntervalS\":\(p.minIntervalS),\"accuracy\":\(q(p.accuracy.jsonName))}"
    }

    static func input(_ r: InRecord, _ s: Int64) -> String {
        switch r {
        case .start: return "[\"START\"]"
        case .kill: return "[\"KILL\"]"
        case let .restore(now, status, fired, dismissed):
            return "[\"RESTORE\",\(rel(now, s)),\(q(status.jsonName)),\(relOpt(fired, s)),\(relOpt(dismissed, s))]"
        case let .input(x, idx):
            switch x {
            case let .locationFix(f): return "[\"FIX\",\(rel(f.atMs, s)),\(idx ?? -1)]"
            case let .tick(a): return "[\"TICK\",\(rel(a, s))]"
            case let .batterySample(a, l, c): return "[\"BATTERY\",\(rel(a, s)),\(l),\(c)]"
            case let .locationAvailability(a, c): return "[\"AVAIL\",\(rel(a, s)),\(q(c.jsonName))]"
            case let .fallbackScheduled(a, f, ok): return "[\"FB_SCHEDULED\",\(rel(a, s)),\(rel(f, s)),\(ok)]"
            case let .fallbackFired(a, f): return "[\"FB_FIRED\",\(rel(a, s)),\(rel(f, s))]"
            case let .alarmSilenced(a, x): return "[\"SILENCED\",\(rel(a, s)),\(rel(x, s))]"
            case let .userAction(a, k): return "[\"USER\",\(rel(a, s)),\(q(k.jsonName))]"
            }
        }
    }

    static func event(_ e: TripEvent, _ s: Int64) -> String {
        switch e {
        case let .preAlert(x):
            return "{\"e\":\"preAlert\",\"atMs\":\(rel(x.atMs, s)),\"distanceM\":\(x.distanceM),\"etaS\":\(intOpt(x.etaS))}"
        case let .alarm(x):
            return "{\"e\":\"alarm\",\"atMs\":\(rel(x.atMs, s)),\"reason\":\(q(x.reason.jsonName)),\"ringNow\":\(x.ringNow),"
                + "\"snoozeAllowed\":\(x.snoozeAllowed),\"distanceM\":\(intOpt(x.distanceM)),\"etaS\":\(intOpt(x.etaS)),"
                + "\"batteryPct\":\(intOpt(x.batteryPct))}"
        case let .snoozed(x):
            return "{\"e\":\"snoozed\",\"atMs\":\(rel(x.atMs, s)),\"untilMs\":\(rel(x.untilMs, s))}"
        case let .gpsLost(x):
            return "{\"e\":\"gpsLost\",\"atMs\":\(rel(x.atMs, s)),\"cause\":\(q(x.cause.jsonName)),\"lastFixAgeS\":\(intOpt(x.lastFixAgeS))}"
        case let .gpsRecovered(x):
            return "{\"e\":\"gpsRecovered\",\"atMs\":\(rel(x.atMs, s)),\"lostForS\":\(x.lostForS)}"
        case let .lowBatteryRisk(x):
            return "{\"e\":\"lowBatteryRisk\",\"atMs\":\(rel(x.atMs, s)),\"levelPct\":\(x.levelPct),\"availableMin\":\(x.availableMin),"
                + "\"neededMin\":\(x.neededMin)}"
        case let .overshoot(x):
            return "{\"e\":\"overshoot\",\"atMs\":\(rel(x.atMs, s)),\"pastM\":\(x.pastM)}"
        case let .arrived(x):
            return "{\"e\":\"arrived\",\"atMs\":\(rel(x.atMs, s)),\"distanceM\":\(x.distanceM)}"
        case let .fallbackAlarmChanged(x):
            return "{\"e\":\"fallbackAlarmChanged\",\"atMs\":\(rel(x.atMs, s)),\"fallbackAtMs\":\(relOpt(x.fallbackAtMs, s)),"
                + "\"cause\":\(q(x.cause.jsonName))}"
        case let .samplingPolicyChanged(x):
            return "{\"e\":\"samplingPolicyChanged\",\"atMs\":\(rel(x.atMs, s)),\"policy\":\(policy(x.policy))}"
        case let .tripEnded(x):
            let m = x.summary
            return "{\"e\":\"tripEnded\",\"atMs\":\(rel(x.atMs, s)),\"outcome\":\(q(x.outcome.jsonName)),"
                + "\"endReason\":\(q(x.endReason.jsonName)),\"summary\":{\"startedAtMs\":\(rel(m.startedAtMs, s)),"
                + "\"alarmAtMs\":\(relOpt(m.alarmAtMs, s)),\"alarmReason\":\(qOpt(m.alarmReason?.jsonName)),"
                + "\"dismissedAtMs\":\(relOpt(m.dismissedAtMs, s)),\"snoozeCount\":\(m.snoozeCount),\"travelledM\":\(m.travelledM),"
                + "\"vehicleGuess\":\(q(m.vehicleGuess.jsonName))}}"
        }
    }

    /// `v`: the unstarred view fields of T10 §4.16 except tripId and atMs.
    static func view(_ v: TripView, _ s: Int64) -> String {
        var o = "{\"phase\":\(q(v.phase.jsonName)),\"gps\":\(q(v.gps.jsonName)),\"locationCause\":\(q(v.locationCause.jsonName)),"
        o += "\"distanceM\":\(intOpt(v.distanceM)),\"isEstimated\":\(v.isEstimated),\"etaS\":\(intOpt(v.etaS)),"
        o += "\"predictedAlarmAtMs\":\(relOpt(v.predictedAlarmAtMs, s)),"
        o += "\"samplingPolicy\":\(v.samplingPolicy.map(policy) ?? "null"),\"fallbackAtMs\":\(relOpt(v.fallbackAtMs, s)),"
        o += "\"fallbackStatus\":\(q(v.fallbackStatus.jsonName)),\"batteryPct\":\(intOpt(v.batteryPct)),"
        o += "\"batteryRisk\":\(v.batteryRisk),\"preAlertFired\":\(v.preAlertFired),\"alarmAtMs\":\(relOpt(v.alarmAtMs, s)),"
        o += "\"alarmReason\":\(qOpt(v.alarmReason?.jsonName)),\"alarmRinging\":\(v.alarmRinging),\"snoozeCount\":\(v.snoozeCount),"
        o += "\"snoozeUntilMs\":\(relOpt(v.snoozeUntilMs, s)),\"overshootPastM\":\(intOpt(v.overshootPastM)),"
        o += "\"outcome\":\(qOpt(v.outcome?.jsonName)),\"vehicleGuess\":\(q(v.vehicleGuess.jsonName)),"
        o += "\"travelledM\":\(v.travelledM),\"droppedFixes\":\(v.droppedFixes),\"wakeAtMs\":\(relOpt(v.wakeAtMs, s))}"
        return o
    }

    /// Full transcript text (header + one line per recorded Step / KILL marker).
    static func render(run: String, records: [StepRecord], startMs: Int64) -> String {
        var out = "{\"p05\":1,\"run\":\(q(run))}\n"
        var lastV: String? = nil
        for r in records {
            if case .kill = r.input {
                out += "{\"t\":\(r.t),\"in\":[\"KILL\"]}\n"
                continue
            }
            out += "{\"t\":\(r.t),\"in\":\(input(r.input, startMs))"
            if !r.events.isEmpty { out += ",\"ev\":[" + r.events.map { event($0, startMs) }.joined(separator: ",") + "]" }
            if r.v != lastV {
                out += ",\"v\":" + r.v
                lastV = r.v
            }
            out += "}\n"
        }
        return out
    }

    static func lineCount(_ s: String) -> Int {
        var n = 0
        for b in s.utf8 where b == 0x0A { n += 1 }
        return n
    }

    static func hex(_ x: Double) -> String { Bits.hex(x) }

    /// `.diag.jsonl` (T12 §9.5): one line per Step line of the transcript; Doubles as raw-bit hex.
    static func renderDiag(records: [StepRecord], states: [EngineState?]) -> String {
        var out = ""
        for (i, r) in records.enumerated() {
            if case .kill = r.input { continue }
            guard let s = states[i] else { continue }
            func d(_ x: Double?) -> String { x.map { q(hex($0)) } ?? "null" }
            let v = r.view
            out += "{\"t\":\(r.t),\"s\":{\"dSmooth\":\(d(s.dSmooth)),\"dStartM\":\(d(s.dStartM)),\"minD\":\(d(s.minD)),"
            out += "\"ground\":\(d(s.ground)),\"closing\":\(d(s.closing)),\"movingTimeS\":\(d(s.movingTimeS)),"
            out += "\"movingDistM\":\(d(s.movingDistM)),\"cvGuard\":[" + s.cvGuard.map { q(hex($0)) }.joined(separator: ",") + "],"
            out += "\"speedKmh\":\(d(v.speedKmh)),\"progress\":\(d(v.progress)),\"alarmMarkerProgress\":\(d(v.alarmMarkerProgress)),"
            out += "\"routeDistanceEstM\":\(intOpt(v.routeDistanceEstM)),\"distanceErrorM\":\(intOpt(v.distanceErrorM)),"
            out += "\"etaMinS\":\(intOpt(v.etaMinS)),\"etaMaxS\":\(intOpt(v.etaMaxS))}}\n"
        }
        return out
    }
}
