@testable import Trip

/// OS simulator (T10 §8.1-4, T12 §8.4, README §6.2–§6.6). Value type so I8 can copy it.
struct OsSim: Sendable, Equatable {
    enum Ringing: Sendable, Equatable { case none, engine, fallback }

    var enabled: Bool
    var osRingMaxS: Int?
    var osDismissOffsetS: Int?
    var fbOs: Int64? = nil
    var ringing: Ringing = .none
    var ringStartMs: Int64? = nil
    var osFallbackFiredT: Int? = nil
    var osFallbackFiredAtMs: Int64? = nil
    var osDismissedAtMs: Int64? = nil
    var queue: [EngineInput] = []
    var violations: [String] = []

    init(enabled: Bool, osRingMaxS: Int?, osDismissOffsetS: Int?) {
        self.enabled = enabled
        self.osRingMaxS = osRingMaxS
        self.osDismissOffsetS = osDismissOffsetS
    }

    /// Inputs due at tick t, in order a (osDismiss) → b (osRingMaxS) → c (fallback rings).
    mutating func tick(t: Int, nowMs: Int64, alive: Bool) -> [EngineInput] {
        guard enabled else { return [] }
        var out: [EngineInput] = []
        if let off = osDismissOffsetS, !alive, let firedT = osFallbackFiredT, t == firedT + off {
            ringing = .none
            osDismissedAtMs = nowMs
        }
        if let maxS = osRingMaxS, ringing != .none, let start = ringStartMs, nowMs >= start + Int64(maxS) * 1000 {
            let s = start + Int64(maxS) * 1000
            ringing = .none
            if alive { out.append(.alarmSilenced(atMs: nowMs, silencedAtMs: s)) }
        }
        if let fb = fbOs, nowMs >= fb {
            ringing = .fallback
            ringStartMs = fb
            fbOs = nil
            if alive {
                out.append(.fallbackFired(atMs: nowMs, firedAtMs: fb))
            } else if osFallbackFiredT == nil {
                osFallbackFiredT = t
                osFallbackFiredAtMs = fb
            }
        }
        return out
    }

    /// Reacts to the events of a Step; immediate inputs go to `queue`.
    mutating func react(_ events: [TripEvent], nowMs: Int64, t: Int) {
        guard enabled else { return }
        for e in events {
            switch e {
            case let .alarm(a) where a.ringNow:
                if ringing == .engine { violations.append("P07(i) t=\(t): Alarm(ringNow=true) while engine alarm rings") }
                if ringing == .fallback {
                    queue.append(.fallbackFired(atMs: nowMs, firedAtMs: ringStartMs ?? nowMs))
                } else {
                    ringing = .engine
                    ringStartMs = nowMs
                    fbOs = nil
                }
            case .snoozed, .tripEnded:
                ringing = .none
            case let .fallbackAlarmChanged(f):
                fbOs = f.fallbackAtMs
                if let x = f.fallbackAtMs { queue.append(.fallbackScheduled(atMs: nowMs, fallbackAtMs: x, ok: true)) }
            default:
                break
            }
        }
    }

    mutating func onUserStop() { if enabled { ringing = .none } }

    mutating func onKill() { if ringing == .engine { ringing = .none } }

    /// MISSING relaunch: the OS lost the alarm.
    mutating func dropForMissing() {
        guard enabled else { return }
        fbOs = nil
        if ringing == .fallback { ringing = .none }
    }
}
