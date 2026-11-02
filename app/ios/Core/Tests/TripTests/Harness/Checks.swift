@testable import Trip

/// Per-run checks (T12 §8.5): expectations, forbids, invariants I1–I7, I10–I12, P02, P07, finite state.
enum Checks {
    static func matches(_ e: TripEvent, _ f: EventFilter) -> Bool {
        guard e.fixtureName == f.event else { return false }
        switch e {
        case let .alarm(a):
            if let r = f.reason, r != a.reason.jsonName { return false }
            if let rn = f.ringNow, rn != a.ringNow { return false }
            if f.cause != nil { return false }
        case let .gpsLost(g):
            if f.reason != nil || f.ringNow != nil { return false }
            if let c = f.cause, c != g.cause.jsonName { return false }
        case let .fallbackAlarmChanged(x):
            if f.reason != nil || f.ringNow != nil { return false }
            if let c = f.cause, c != x.cause.jsonName { return false }
        default:
            if f.reason != nil || f.ringNow != nil || f.cause != nil { return false }
        }
        return true
    }

    /// (t, event) in record order, KILL markers excluded.
    static func flat(_ r: Runner) -> [(t: Int, e: TripEvent)] {
        var out: [(Int, TripEvent)] = []
        for rec in r.records { for e in rec.events { out.append((rec.t, e)) } }
        return out
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// Returns failure messages (empty = pass). Includes configuration errors.
    static func run(_ r: Runner) -> [String] {
        let tag = "[\(r.run) j=\(r.j)]"
        var f: [String] = r.configErrors.map { "\(tag) \($0)" }
        if !r.configErrors.isEmpty { return f }
        f += r.violations.map { "\(tag) \($0)" }
        f += r.os.violations.map { "\(tag) \($0)" }
        let ev = flat(r)
        let spec = r.spec

        for x in spec.expect {
            if let hit = ev.first(where: { matches($0.e, x.filter) }) {
                if !(hit.t >= x.notBefore && hit.t <= x.notAfter) {
                    f.append("\(tag) expect \(x.filter) at t=\(hit.t) not in [\(x.notBefore), \(x.notAfter)]")
                }
            } else {
                f.append("\(tag) expect \(x.filter): no such event")
            }
        }
        for x in spec.expectAfter {
            guard let b = r.resolve(x.after) else {
                f.append("\(tag) config error: expectAfter anchor \(x.after.anchor ?? "") never occurred")
                continue
            }
            if let hit = ev.first(where: { $0.t >= b && matches($0.e, x.filter) }) {
                let d = hit.t - b
                if !(d >= x.lo && d <= x.hi) {
                    f.append("\(tag) expectAfter \(x.filter): t=\(hit.t) − B=\(b) = \(d) not in [\(x.lo), \(x.hi)]")
                }
            } else {
                f.append("\(tag) expectAfter \(x.filter): no event at t ≥ \(b)")
            }
        }
        if let x = spec.expectFallback {
            let last = ev.last { pair in
                if case .fallbackAlarmChanged = pair.e { return pair.t <= x.asOfT } else { return false }
            }
            if let last, case let .fallbackAlarmChanged(fac) = last.e, let at = fac.fallbackAtMs {
                let rel = floorDiv(at - r.startMs, 1000)
                if !(rel >= Int64(x.notBefore) && rel <= Int64(x.notAfter)) {
                    f.append("\(tag) expectFallback \(rel) not in [\(x.notBefore), \(x.notAfter)]")
                }
            } else {
                f.append("\(tag) expectFallback: no fallbackAlarmChanged with fallbackAtMs ≠ null at t ≤ \(x.asOfT)")
            }
        }
        let firstEnded = ev.first { if case .tripEnded = $0.e { return true } else { return false } }
        if let o = spec.expectOutcome {
            if let fe = firstEnded, case let .tripEnded(te) = fe.e {
                if te.outcome.jsonName != o { f.append("\(tag) expectOutcome \(o), got \(te.outcome.jsonName)") }
            } else {
                f.append("\(tag) expectOutcome \(o): no tripEnded")
            }
        }
        if let vg = spec.expectSummary {
            if let fe = firstEnded, case let .tripEnded(te) = fe.e {
                if te.summary.vehicleGuess.jsonName != vg {
                    f.append("\(tag) expectSummary \(vg), got \(te.summary.vehicleGuess.jsonName)")
                }
            } else {
                f.append("\(tag) expectSummary: no tripEnded")
            }
        }
        for name in spec.forbid {
            if let hit = ev.first(where: { $0.e.fixtureName == name }) { f.append("\(tag) forbid \(name) at t=\(hit.t)") }
        }
        for m in spec.forbidMatch {
            if let hit = ev.first(where: { matches($0.e, m) }) { f.append("\(tag) forbidMatch \(m) at t=\(hit.t)") }
        }
        for m in spec.forbidAfter {
            guard let b = r.resolve(m.after) else {
                f.append("\(tag) config error: forbidAfter anchor never occurred")
                continue
            }
            if let hit = ev.first(where: { $0.t > b && matches($0.e, m.filter) }) {
                f.append("\(tag) forbidAfter \(m.filter) at t=\(hit.t) > \(b)")
            }
        }
        f += invariants(r).map { "\(tag) \($0)" }
        // P02: no kill → first alarm rings now (T10.3: except cases declaring allowFallbackFirst).
        if spec.config.kill == nil && !spec.allowFallbackFirst {
            if let a = ev.first(where: { if case .alarm = $0.e { return true } else { return false } }),
               case let .alarm(al) = a.e, !al.ringNow {
                f.append("\(tag) P02: first alarm at t=\(a.t) has ringNow=false")
            }
        }
        return f
    }

    /// I1–I7, I10–I12 (T10 §3; I4 as T12 §8.5).
    static func invariants(_ r: Runner) -> [String] {
        var f: [String] = []
        var seenAlarm = false
        var releasedSinceAlarm = false
        var ended = false
        var preAlerts = 0, overshoots = 0
        var lastGps: String? = nil
        var prevView: TripView? = nil
        let quietMs = Int64(r.params.fallbackQuietBeforeS) * 1000
        for rec in r.records {
            if case .kill = rec.input { continue }
            if case let .input(x, _) = rec.input, case .alarmSilenced = x { releasedSinceAlarm = true }
            var alarms = 0, facs = 0
            for e in rec.events {
                switch e {
                case let .alarm(a):
                    alarms += 1
                    if ended { f.append("I2: alarm after tripEnded at t=\(rec.t)") }
                    if a.ringNow && seenAlarm && !releasedSinceAlarm {
                        f.append("I1: Alarm(ringNow=true) at t=\(rec.t) without Snoozed/AlarmSilenced since previous alarm")
                    }
                    seenAlarm = true
                    releasedSinceAlarm = false
                case .snoozed:
                    releasedSinceAlarm = true
                case let .fallbackAlarmChanged(x):
                    facs += 1
                    if seenAlarm, x.fallbackAtMs != nil, x.cause != .snooze && x.cause != .resync {
                        f.append("I3: fallbackAlarmChanged(\(x.cause.jsonName)) with time after first alarm at t=\(rec.t)")
                    }
                    if x.cause == .eta, let pv = prevView, let prevT = pv.fallbackAtMs, pv.fallbackStatus != .failed,
                       let pred = rec.view.predictedAlarmAtMs {
                        let now = r.nowMs(rec.t)
                        if now >= TMath.min(prevT, pred) - quietMs { f.append("I4: ETA emission in quiet window at t=\(rec.t)") }
                    }
                case .preAlert:
                    preAlerts += 1
                    if seenAlarm { f.append("I5: preAlert after alarm at t=\(rec.t)") }
                case .overshoot:
                    overshoots += 1
                case .gpsLost:
                    if lastGps == "gpsLost" { f.append("I7: gpsLost twice at t=\(rec.t)") }
                    lastGps = "gpsLost"
                case .gpsRecovered:
                    if lastGps != "gpsLost" { f.append("I7: gpsRecovered without gpsLost at t=\(rec.t)") }
                    lastGps = "gpsRecovered"
                case let .tripEnded(te):
                    if te.endReason != .userStop && !seenAlarm { f.append("I10: tripEnded(\(te.endReason.jsonName)) without alarm") }
                    ended = true
                default:
                    break
                }
            }
            if alarms > 1 { f.append("I11: \(alarms) alarms in one Step at t=\(rec.t)") }
            if (rec.view.snoozeUntilMs != nil) != (rec.view.phase == .snoozed) {
                f.append("C16: snoozeUntilMs \(rec.view.snoozeUntilMs == nil ? "null" : "set") in phase \(rec.view.phase.jsonName) at t=\(rec.t)")
            }
            if facs > 1 { f.append("I12: \(facs) fallbackAlarmChanged in one Step at t=\(rec.t)") }
            prevView = rec.view
        }
        if preAlerts > 1 { f.append("I5: \(preAlerts) preAlerts") }
        if overshoots > 1 { f.append("I6: \(overshoots) overshoots") }
        return f
    }
}
