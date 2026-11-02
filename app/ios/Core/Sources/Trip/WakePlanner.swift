// Wake-up time (T10 §4.15, T12 C13; T10.4: wakeGuardMs on c3/c4).
enum WakePlanner {
    /// T10.4 `wakeGuardMs`: predicted is a boundary rounded down to the ms (<= the instant the condition really holds), so a
    /// Tick exactly there would still see the condition false. Waking 1 s later lands >= 999 ms past the boundary. A constant,
    /// not an `EngineParams` field / Remote Config key.
    static let wakeGuardMs: Int64 = 1000

    static func wakeAt(_ s: EngineState, predicted: Int64?, now: Int64) -> Int64? {
        if s.phase == .ended { return nil }
        let p = s.params
        var c: [Int64?] = []
        if s.phase == .acquiring && !s.lostEmittedBeforeFirstFix {
            c.append(s.startedAtMs + TMath.ms(p.acquireTimeoutS))
        }
        if s.gps == .ok, let last = s.last { c.append(last.fixAtMs + TMath.ms(GpsMonitor.lostAfterS(s))) }
        if (s.phase == .acquiring || s.phase == .tracking), let pr = predicted {
            // c3: always (> now while active and not alarmed, so I13 holds); near-zone entry only while not yet crossed.
            c.append(pr + wakeGuardMs)
            if pr - now > TMath.ms(p.fallbackNearS) { c.append(pr - TMath.ms(p.fallbackNearS) + wakeGuardMs) }
        }
        if s.phase == .tracking, let pr = predicted {
            // c4: tier boundaries not yet crossed in this Step.
            for b in [p.denseEnterS, p.mediumEnterS] where pr - now > TMath.ms(b) {
                c.append(pr - TMath.ms(b) + wakeGuardMs)
            }
        }
        if s.phase == .snoozed { c.append(s.alarm.snoozeUntilMs) }
        if s.phase == .alarming || s.phase == .overshot, let l = s.alarm.lastRingAtMs {
            c.append(l + TMath.ms(p.alarmMaxActiveS))
        }
        if s.fallback.status == .failed, let em = s.fallback.emittedAtMs { c.append(em + TMath.ms(p.fallbackRetryS)) }
        if (s.phase == .acquiring || s.phase == .tracking), let t = s.fallback.targetAtMs {
            c.append(t - TMath.ms(p.fallbackQuietBeforeS + p.fallbackMinIntervalS))
        }
        return TMath.minOrNull(array: c.map { x in x.flatMap { $0 > now ? $0 : nil } })
    }
}
