// Alarm conditions of the three modes, alarm reason priority, predicted alarm time (T10 §4.5) and §4.13.

/// §4.5 predicted alarm time (`noBattery`, `withBattery` = predictedAlarmAt) and, T10.5, the wake-up bases of §4.15:
/// `wakeBasis` (`wakeBasisAt`) and `wakeBattery` (`wakeBatteryAt`). The wake-up bases never feed the view or the snapshot.
struct Predicted: Sendable, Equatable {
    let noBattery: Int64?
    let withBattery: Int64?
    let wakeBasis: Int64?
    let wakeBattery: Int64?

    static let none = Predicted(noBattery: nil, withBattery: nil, wakeBasis: nil, wakeBattery: nil)
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
        guard s.phase == .acquiring || s.phase == .tracking, s.alarm.atMs == nil else { return .none }
        let p = s.params
        let deadlineAt = s.startedAtMs + TMath.ms(s.maxTripDurationS)
        guard let e else { return Predicted(noBattery: deadlineAt, withBattery: deadlineAt, wakeBasis: deadlineAt, wakeBattery: nil) }
        let mAt = modeAt(s, e, now: now, atDist: { atDist($0, e, now: now) }, atTime: { atTime($0, e, now: now) })
        let lostAt = s.gps == .lost ? atTime(p.gpsLostAlarmEtaS, e, now: now) : nil
        let noBattery = TMath.minOrNull(mAt, lostAt, deadlineAt)
        let battery = batteryAt(s, now: now)
        // T10.5: GPS OK and stopped means dNow = dSmooth (§4.4), so modeAt = now + constant slides with now: not a wake-up basis.
        let wakeBasis = slides(s, e) ? deadlineAt : noBattery
        return Predicted(noBattery: noBattery, withBattery: TMath.minOrNull(noBattery, battery), wakeBasis: wakeBasis,
                         wakeBattery: battery)
    }

    /// §4.5 `batteryAt`: nil without a level, while charging, when not armed or with a zero rate.
    static func batteryAt(_ s: EngineState, now: Int64) -> Int64? {
        let b = s.battery
        guard let level = b.levelPct, !b.charging, b.armed else { return nil }
        let rate = BatteryRule.rate(s, now: now)
        guard rate > 0 else { return nil }
        let eff = BatteryRule.alarmPctEff(s)
        return now + TMath.floorMs(Double(TMath.max(0, level - eff)) / rate * 3600.0)
    }

    /// T10.5 §4.5 `slides`: the estimate is frozen at dSmooth (GPS OK, stop in progress), the same test as `Estimator.estimate`.
    static func slides(_ s: EngineState, _ e: Estimate?) -> Bool { e != nil && s.gps == .ok && s.stopStartMs != nil }

    /// T10.5 §4.5 `wakeBasisAt` alone (U106 g); the engine reads it from `predictedAlarmAt`.
    static func wakeBasisAt(_ s: EngineState, _ e: Estimate?, now: Int64) -> Int64? { predictedAlarmAt(s, e, now: now).wakeBasis }

    /// §4.13 at the Step that accepted the first fix.
    static func maxTripDurationFromFirstFix(_ e: Estimate?, _ p: EngineParams) -> Int {
        guard let eta = e?.etaS else { return p.maxTripMinS }
        return TMath.clamp(TMath.roundHalfUp(2.0 * eta), p.maxTripMinS, p.maxTripCapS)
    }
}
