// Alarm conditions of the three modes, alarm reason priority, predicted alarm time (T10 §4.5) and §4.13.

struct Predicted: Sendable, Equatable {
    let noBattery: Int64?
    let withBattery: Int64?
}

enum ModeRules {
    static func slowDistM(_ p: EngineParams) -> Double {
        TMath.max(Double(p.smartTargetS * p.smartSlowSpeedKmh) / 3.6, Double(p.smartFloorM))
    }

    static func thrS(_ c: TripConfig) -> Int { (c.timeThresholdMin ?? 0) * 60 }

    static func modeReason(_ s: EngineState, _ e: Estimate) -> AlarmReason? {
        let p = s.params
        switch s.config.mode {
        case .distance:
            return e.dNow <= Double(s.config.distanceThresholdM ?? 0) * p.distanceModeFactor ? .distance : nil
        case .time:
            if let eta = e.etaS, eta <= Double(thrS(s.config)) { return .time }
            return e.dNow <= Double(p.arrivedRadiusM) ? .time : nil
        case .smart:
            if s.slow { return e.dNow <= slowDistM(p) ? .smartSlowDistance : nil }
            if let eta = e.etaS, eta <= Double(p.smartTargetS) { return .smartTime }
            return e.dNow <= Double(p.smartFloorM) ? .smartDistance : nil
        }
    }

    /// Only called in ACQUIRING/TRACKING before the first alarm.
    static func alarmReason(_ s: EngineState, _ e: Estimate?, now: Int64, passedClosest: Bool) -> AlarmReason? {
        if let e {
            let m = modeReason(s, e)
            if s.gps == .lost {
                if m != nil { return .gpsLost }
                if let eta = e.etaS, eta < Double(s.params.gpsLostAlarmEtaS) { return .gpsLost }
            } else if let m {
                return m
            }
        }
        if BatteryRule.lowBatteryCond(s) { return .lowBattery }
        if passedClosest { return .passedClosest }
        if now - s.startedAtMs >= TMath.ms(s.maxTripDurationS) { return .timeout }
        return nil
    }

    static func atDist(_ x: Double, _ e: Estimate, now: Int64) -> Int64? {
        e.cvDr > 0 ? now + TMath.floorMs(TMath.max(0.0, e.dNow - x) / e.cvDr) : nil
    }

    static func atTime(_ sec: Int, _ e: Estimate, now: Int64) -> Int64? {
        guard let eta = e.etaS else { return nil }
        return now + TMath.floorMs(TMath.max(0.0, eta - Double(sec)))
    }

    static func modeAt(_ s: EngineState, _ e: Estimate, now: Int64,
                       atDist: (Double) -> Int64?, atTime: (Int) -> Int64?) -> Int64? {
        let p = s.params
        switch s.config.mode {
        case .distance:
            return atDist(Double(s.config.distanceThresholdM ?? 0) * p.distanceModeFactor)
        case .time:
            return TMath.minOrNull(atTime(thrS(s.config)), atDist(Double(p.arrivedRadiusM)))
        case .smart:
            if s.slow { return atDist(slowDistM(p)) }
            return TMath.minOrNull(atTime(p.smartTargetS), atDist(Double(p.smartFloorM)))
        }
    }

    /// §4.5 predicted alarm time, computed once per Step after step 8 (T12 C7).
    static func predictedAlarmAt(_ s: EngineState, _ e: Estimate?, now: Int64) -> Predicted {
        guard s.phase == .acquiring || s.phase == .tracking, s.alarm.atMs == nil else {
            return Predicted(noBattery: nil, withBattery: nil)
        }
        let p = s.params
        let deadlineAt = s.startedAtMs + TMath.ms(s.maxTripDurationS)
        guard let e else { return Predicted(noBattery: deadlineAt, withBattery: deadlineAt) }
        let mAt = modeAt(s, e, now: now, atDist: { atDist($0, e, now: now) }, atTime: { atTime($0, e, now: now) })
        let lostAt = s.gps == .lost ? atTime(p.gpsLostAlarmEtaS, e, now: now) : nil
        let noBattery = TMath.minOrNull(mAt, lostAt, deadlineAt)
        var batteryAt: Int64? = nil
        let b = s.battery
        if let level = b.levelPct, !b.charging, b.armed {
            let rate = BatteryRule.rate(s, now: now)
            if rate > 0 {
                let eff = BatteryRule.alarmPctEff(s)
                batteryAt = now + TMath.floorMs(Double(TMath.max(0, level - eff)) / rate * 3600.0)
            }
        }
        return Predicted(noBattery: noBattery, withBattery: TMath.minOrNull(noBattery, batteryAt))
    }

    /// §4.13 at the Step that accepted the first fix.
    static func maxTripDurationFromFirstFix(_ e: Estimate?, _ p: EngineParams) -> Int {
        guard let eta = e?.etaS else { return p.maxTripMinS }
        return TMath.clamp(TMath.roundHalfUp(2.0 * eta), p.maxTripMinS, p.maxTripCapS)
    }
}
