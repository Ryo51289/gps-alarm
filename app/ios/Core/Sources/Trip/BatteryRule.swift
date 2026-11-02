// Battery rule (T10 §4.9, T12 C8).
enum BatteryRule {
    static func alarmPctEff(_ s: EngineState) -> Int {
        s.battery.choice == .batteryAlarmEarlier ? (s.battery.choicePct ?? s.params.lowBatteryEarlierPct) : s.params.lowBatteryAlarmPct
    }

    static func onBattery(_ s: inout EngineState, atMs: Int64, levelPct: Int, charging: Bool) {
        s.battery.levelPct = levelPct
        s.battery.charging = charging
        if charging {
            s.battery.segT0 = nil
            s.battery.segL0 = nil
        } else if s.battery.segT0 == nil {
            s.battery.segT0 = atMs
            s.battery.segL0 = levelPct
        }
        if !charging && levelPct > alarmPctEff(s) { s.battery.armed = true }
    }

    static func onChoice(_ s: inout EngineState, _ action: UserActionKind) {
        let p = s.params
        s.battery.choice = action
        if action == .batteryAlarmEarlier {
            if let level = s.battery.levelPct {
                s.battery.choicePct = TMath.max(p.lowBatteryAlarmPct, TMath.min(p.lowBatteryEarlierPct, level - 1))
            } else {
                s.battery.choicePct = p.lowBatteryEarlierPct
            }
        }
    }

    static func observedRate(_ s: EngineState, now: Int64) -> Double? {
        let b = s.battery
        guard let t0 = b.segT0, let l0 = b.segL0, let level = b.levelPct else { return nil }
        guard now - t0 >= TMath.ms(s.params.batteryMinRateWindowS), l0 - level >= 1 else { return nil }
        return Double(l0 - level) / (Double(now - t0) / 3600000.0)
    }

    static func rate(_ s: EngineState, now: Int64) -> Double {
        TMath.max(s.params.batteryMinRatePctPerH, observedRate(s, now: now) ?? s.params.batteryPriorDrainPctPerH)
    }

    struct Risk: Sendable, Equatable {
        let risk: Bool
        let availableS: Double
        let neededS: Double
    }

    static func riskOf(_ s: EngineState, predictedNoBattery: Int64?, now: Int64) -> Risk {
        let b = s.battery
        guard let level = b.levelPct, let pNoBat = predictedNoBattery, !b.charging else {
            return Risk(risk: false, availableS: 0, neededS: 0)
        }
        let availableS = Double(level - alarmPctEff(s)) / rate(s, now: now) * 3600.0
        let neededS = TMath.max(0.0, TMath.toS(pNoBat - now)) + Double(s.params.batteryReserveAfterAlarmS)
        return Risk(risk: availableS < neededS, availableS: availableS, neededS: neededS)
    }

    static func lowBatteryCond(_ s: EngineState) -> Bool {
        guard s.phase == .acquiring || s.phase == .tracking, s.alarm.atMs == nil else { return false }
        let b = s.battery
        guard let level = b.levelPct, !b.charging, b.armed else { return false }
        return level <= alarmPctEff(s)
    }
}
