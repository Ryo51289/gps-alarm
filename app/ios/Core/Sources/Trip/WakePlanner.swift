// Wake-up time (T10 §4.15, T12 C13; T10.4: wakeGuardMs on c3/c4; T10.5: c3/c4 from wakeBasisAt / wakeBatteryAt so a sliding
// forecast never asks for a wake-up storm).
enum WakePlanner {
    /// T10.4 `wakeGuardMs`: predicted is a boundary rounded down to the ms (<= the instant the condition really holds), so a
    /// Tick exactly there would still see the condition false. Waking 1 s later lands >= 999 ms past the boundary. A constant,
    /// not an `EngineParams` field / Remote Config key.
    static let wakeGuardMs: Int64 = 1000

    /// `s` is the state at the end of the Step; `wakeBasis` / `wakeBattery` are the Step's `wakeBasisAt` / `wakeBatteryAt`
    /// (T10.5 §4.5, `Predicted`). Without a sliding estimate and without a battery forecast, wakeBasis equals predictedAlarmAt
    /// and every candidate is the T10.4 one.
    static func wakeAt(_ s: EngineState, wakeBasis: Int64?, wakeBattery: Int64?, now: Int64) -> Int64? {
        if s.phase == .ended { return nil }
        let p = s.params
        var c: [Int64?] = []
        if s.phase == .acquiring && !s.lostEmittedBeforeFirstFix {
            c.append(s.startedAtMs + TMath.ms(p.acquireTimeoutS))
        }
        if s.gps == .ok, let last = s.last { c.append(last.fixAtMs + TMath.ms(GpsMonitor.lostAfterS(s))) }
        if (s.phase == .acquiring || s.phase == .tracking), let wb = wakeBasis {
            // c3: always (> now while active and not alarmed, so I13 holds); the battery forecast only here (T10.5: it slides
            // slowly between two samples). Near-zone entry only while not yet crossed, from wakeBasis only.
            c.append(TMath.min(wb, wakeBattery ?? wb) + wakeGuardMs)
            if wb - now > TMath.ms(p.fallbackNearS) { c.append(wb - TMath.ms(p.fallbackNearS) + wakeGuardMs) }
        }
        if s.phase == .tracking, let wb = wakeBasis {
            // c4: tier boundaries not yet crossed in this Step, from wakeBasis only (T10.5).
            for b in [p.denseEnterS, p.mediumEnterS] where wb - now > TMath.ms(b) {
                c.append(wb - TMath.ms(b) + wakeGuardMs)
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
