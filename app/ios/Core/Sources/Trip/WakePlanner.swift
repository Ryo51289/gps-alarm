// Wake-up time (T10 §4.15, T12 C13).
enum WakePlanner {
    static func wakeAt(_ s: EngineState, predicted: Int64?, now: Int64) -> Int64? {
        if s.phase == .ended { return nil }
        let p = s.params
        var c: [Int64?] = []
        if s.phase == .acquiring && !s.lostEmittedBeforeFirstFix {
            c.append(s.startedAtMs + TMath.ms(p.acquireTimeoutS))
        }
        if s.gps == .ok, let last = s.last { c.append(last.fixAtMs + TMath.ms(GpsMonitor.lostAfterS(s))) }
        if (s.phase == .acquiring || s.phase == .tracking), let pr = predicted {
            c.append(pr)
            c.append(pr - TMath.ms(p.fallbackNearS))
        }
        if s.phase == .tracking, let pr = predicted {
            c.append(pr - TMath.ms(p.denseEnterS))
            c.append(pr - TMath.ms(p.mediumEnterS))
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
