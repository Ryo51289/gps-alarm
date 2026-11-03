// ETA-based fallback alarm (T10 §4.10, T10.2; T12 C1).

enum FallbackPlanner {
    /// T10.2: predicted alarm time "if the vehicle is faster than estimated" (far zone only).
    static func fallbackPredictedAt(_ s: EngineState, _ e: Estimate?, predicted: Int64?, now: Int64) -> Int64? {
        guard let predicted else { return nil }
        guard let e else { return predicted }
        let p = s.params
        let cvHint = p.fallbackHintSpeedFactor * Estimator.expectedSpeedMps(s.config.vehicleHint, p) / p.routeFactorPrior
        let cvFb = TMath.max(e.cvDr, cvHint)
        if !(cvFb > e.cvDr) { return predicted }
        let etaFb = e.dNow / cvFb + Double(p.etaStopPenaltyS)
        let atDistFb: (Double) -> Int64? = { x in now + TMath.floorMs(TMath.max(0.0, e.dNow - x) / cvFb) }
        let atTimeFb: (Int) -> Int64? = { sec in now + TMath.floorMs(TMath.max(0.0, etaFb - Double(sec))) }
        let modeAtFb = ModeRules.modeAt(s, e, now: now, atDist: atDistFb, atTime: atTimeFb)
        let lostAtFb = s.gps == .lost ? atTimeFb(p.gpsLostAlarmEtaS) : nil
        return TMath.minOrNull(predicted, modeAtFb, lostAtFb)
    }

    static func fallbackTarget(now: Int64, predicted: Int64?, predictedFb: Int64?, _ p: EngineParams) -> Int64? {
        guard let predicted else { return nil }
        let t = TMath.max(0.0, TMath.toS(predicted - now))
        if t <= Double(p.fallbackNearS) {
            return TMath.max(now + TMath.ms(p.fallbackMinLeadS), TMath.max(predicted, now) + TMath.ms(p.fallbackLagS))
        }
        let pFb = predictedFb ?? predicted
        let tf = TMath.max(0.0, TMath.toS(pFb - now))
        let earlyMs = TMath.floorMs(TMath.min(Double(p.fallbackEarlyMaxS), p.fallbackEarlyFrac * TMath.max(0.0, tf - Double(p.fallbackNearS))))
        return TMath.max(now + TMath.ms(p.fallbackNearS), pFb + TMath.ms(p.fallbackLagS) - earlyMs)
    }

    static func nextFallbackAt(_ fb: FallbackState, target: Int64?, predicted: Int64?, now: Int64, _ p: EngineParams) -> Int64? {
        guard let target, let predicted else { return nil }
        if fb.status == .failed {
            guard let em = fb.emittedAtMs else { return target }   // as Kotlin: no emission time → retry now
            return now - em >= TMath.ms(p.fallbackRetryS) ? target : nil
        }
        guard let cur = fb.targetAtMs else { return target }
        let quietMs = TMath.ms(p.fallbackQuietBeforeS)
        if now >= TMath.min(cur, predicted) - quietMs {
            // S3/K4 #6 quiet window. T10.5 "urgent later shift": the OS alarm already set is about to ring but the NEW predicted
            // time is far: the engine is not about to ring "now" (K1), >= fallbackMinLeadS left to set the new one before
            // cancelling the old (K2), and only a significant later shift. Skips min-interval and the near-zone hold band.
            let urgent = now < predicted - quietMs && cur - now >= TMath.ms(p.fallbackMinLeadS)
                && target - cur >= TMath.ms(p.fallbackMinShiftS)
            return urgent ? target : nil
        }
        let emitted = fb.emittedAtMs ?? now
        if TMath.toS(predicted - now) <= Double(p.fallbackNearS) {
            let slackMs = TMath.ms(p.fallbackNearSlackS)
            if cur < target { return fb.near ? target + TMath.i64(p.fallbackNearSlackS) * 500 : target }
            if cur - (target + slackMs) >= TMath.ms(p.fallbackMinShiftS)
                && now - emitted >= TMath.ms(p.fallbackMinIntervalS) {
                return target + slackMs
            }
            return nil
        }
        let diff = target - cur
        if (diff < 0 ? -diff : diff) < TMath.ms(p.fallbackMinShiftS) { return nil }
        if target < cur { return target }
        // Far zone, later: at most once a minute, unless the alarm already set is within the c8 range (<= Q + minInterval, T10.5
        // round 2): then the last emission was not a far-zone one (restore, near zone) and no Step before the quiet window is left.
        let soon = cur - now <= TMath.ms(p.fallbackQuietBeforeS + p.fallbackMinIntervalS)
        return now - emitted >= TMath.ms(p.fallbackMinIntervalS) || soon ? target : nil
    }

    /// Step 9 FallbackPlanner. Only call when active (ACQUIRING/TRACKING, not alarmed).
    static func planFallback(_ s: inout EngineState, _ e: Estimate?, predicted: Int64?, now: Int64,
                             events: inout [TripEvent]) {
        let p = s.params
        let pFb = fallbackPredictedAt(s, e, predicted: predicted, now: now)
        let target = fallbackTarget(now: now, predicted: predicted, predictedFb: pFb, p)
        guard let at = nextFallbackAt(s.fallback, target: target, predicted: predicted, now: now, p),
              let predicted else { return }
        let cause: FallbackCause = s.fallback.targetAtMs == nil && s.fallback.resync ? .resync : .eta
        events.append(.fallbackAlarmChanged(.init(atMs: now, fallbackAtMs: at, cause: cause)))
        s.fallback = FallbackState(targetAtMs: at, emittedAtMs: now, status: .requested, confirmedAtMs: nil, resync: false,
                                   near: TMath.toS(predicted - now) <= Double(p.fallbackNearS))
    }
}
