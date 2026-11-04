@testable import Trip

/// T10.6 test support (port of Kotlin `support/LongLoss.kt`): U126 statistics, the C29 counters and the late-case classes.
enum LongLoss {
    /// T10.6 off (C29): the T12.2 behaviour (`preV` has no switch of its own besides lostSpeedGuardUpdates).
    static let offParams: EngineParams = KW.params("{\"gpsLostLongS\": 0, \"passedClosestSlowRiseM\": 0}")

    /// U126: what the estimate says at the Step of a GPS_LOST alarm (`s` = the state after it). `longLostOnly`: the "long loss"
    /// term W holds and neither the mode condition nor `etaS < gpsLostAlarmEtaS` does (the alarm is due to W alone). `preV`: dead
    /// reckoning lifted by the speed measured before `established` (C26).
    struct LostAlarmInfo {
        let longLostOnly: Bool
        let cvDr: Double?
        let preV: Bool
        let elapsedS: Double?
        let lostLongAtS: Double?
    }

    static func lostAlarmInfo(_ s: EngineState) -> LostAlarmInfo {
        guard let e = Estimator.estimate(s, now: s.nowMs) else {
            return LostAlarmInfo(longLostOnly: false, cvDr: nil, preV: false, elapsedS: nil, lostLongAtS: nil)
        }
        let lla = e.lostLongAtS
        let longLost = s.gps == .lost && lla != nil && e.elapsedS >= lla!
        let m = ModeRules.modeReason(s, e)
        let etaRule = e.etaS != nil && e.etaS! < Double(s.params.gpsLostAlarmEtaS)
        let preV = e.lift && !e.established && s.cvGuard.isEmpty
        return LostAlarmInfo(longLostOnly: longLost && m == nil && !etaRule, cvDr: e.cvDr, preV: preV, elapsedS: e.elapsedS,
                             lostLongAtS: lla)
    }

    /// C25 parts (thS, earlyS, cvH) of the state's W mark, recomputed test-side (C29 report, U126 classes); nil when W does not apply.
    static func lostLongParts(_ s: EngineState) -> (thS: Double, earlyS: Double, cvH: Double)? {
        guard let e = Estimator.estimate(s, now: s.nowMs), e.lostLongAtS != nil else { return nil }
        let p = s.params
        let cvHintL = p.gpsLostLongHintFactor * Estimator.expectedSpeedMps(s.config.vehicleHint, p) / p.routeFactorPrior
        let cvH = e.cvDr >= cvHintL ? e.cvDr : cvHintL
        let thS = s.dSmooth! / cvH + Double(p.etaStopPenaltyS) - Double(p.gpsLostAlarmEtaS)
        let early = p.fallbackEarlyFrac * (thS - Double(p.fallbackNearS) >= 0.0 ? thS - Double(p.fallbackNearS) : 0.0)
        return (thS, Double(p.fallbackEarlyMaxS) <= early ? Double(p.fallbackEarlyMaxS) : early, cvH)
    }

    /// U126 (T10 "T10.6 — sau số đo T12.3"): one DISTANCE case rung more than 1 800 s after the truth crossed the threshold,
    /// classified dead → short → fast → ?. `st` = the state of the last Step before `crossMs`; `dTruthAtMs` = true distance at a
    /// time (ms). Same text as Kotlin `lateCaseLine`.
    static func lateCaseLine(tag: String, hint: VehicleKind, lateS: Double, first: String, dead: Bool, crossMs: Int64, thrM: Double,
                             st: EngineState?, dTruthAtMs: (Int64) -> Double) -> String {
        let lastFix = st?.last?.fixAtMs
        let noFix = lastFix.map { Double(crossMs - $0) / 1000.0 }
        let vTruth = lastFix.map { (dTruthAtMs($0) - thrM) / (Double(crossMs - $0) / 1000.0) }
        let cvH = st.flatMap { lostLongParts($0)?.cvH }
        let lost = st?.gps == .lost
        let gpsLostLongS = Double((st?.params ?? .defaults).gpsLostLongS)
        let cls: String
        if dead {
            cls = "dead"
        } else if !lost || noFix == nil || noFix! < gpsLostLongS {
            cls = "short"
        } else if let cvH, let vTruth, vTruth > cvH {
            cls = "fast"
        } else {
            cls = "?"
        }
        func f1(_ x: Double?) -> String { x.map { KW.jf($0, 1) } ?? "null" }
        func f2(_ x: Double?) -> String { x.map { KW.jf($0, 2) } ?? "null" }
        return "late>1800 \(tag) hint=\(hint.jsonName) late=\(f1(lateS)) first=\(first) dead=\(dead) noFix=\(f1(noFix)) "
            + "vTruth=\(f2(vTruth)) cvH=\(f2(cvH)) class=\(cls)"
    }

    /// "n, p50, p90, max" of `xs` (or "n 0").
    static func quantiles(_ xs: [Double]) -> String {
        if xs.isEmpty { return "n 0" }
        let l = xs.sorted()
        func q(_ f: Double) -> Double { l[min(l.count - 1, KW.ki(f * Double(l.count)))] }
        func f(_ x: Double) -> String { KW.jf(x, 1) }
        return "n \(l.count), p50 \(f(q(0.5))), p90 \(f(q(0.9))), max \(f(l[l.count - 1]))"
    }
}

/// T10.6 C29 counters of one harness run: Steps with a `preV` lift, GPS_LOST alarms due to W alone, PASSED_CLOSEST alarms from
/// slowAway (Kotlin `T106Counters`).
struct T106Counters: Sendable {
    var preVLiftSteps = 0
    var longLostAlarms: [String] = []
    var slowAwayAlarms: [String] = []

    /// Kotlin `CaseRun.t106Probe`: counters on the state after the Step.
    mutating func probe(_ t: Int, _ step: Step) {
        let s = step.state
        let e = Estimator.estimate(s, now: s.nowMs)
        if let e, s.gps == .lost, e.lift, !e.established, s.cvGuard.isEmpty { preVLiftSteps += 1 }
        for ev in step.events {
            guard case let .alarm(a) = ev else { continue }
            if a.reason == .gpsLost && LongLoss.lostAlarmInfo(s).longLostOnly {
                let parts = LongLoss.lostLongParts(s)
                longLostAlarms.append("t=\(t) elapsedS=\(KW.kdOpt(e?.elapsedS)) thS=\(KW.kdOpt(parts?.thS)) "
                                      + "earlyS=\(KW.kdOpt(parts?.earlyS))")
            }
            if a.reason == .passedClosest && !OvershootDetector.fast(s) { slowAwayAlarms.append("t=\(t)") }
        }
    }
}
