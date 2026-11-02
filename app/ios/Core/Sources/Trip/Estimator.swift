// "Estimate at now" (T10 §4.4) and the `slow` flag of SMART mode.

struct Estimate: Sendable, Equatable {
    let established: Bool
    let v: Double
    let k: Double
    let closingV: Double
    let guardV: Double?
    let lift: Bool
    let vDr: Double
    let cvDr: Double
    let elapsedS: Double
    let dNow: Double
    let etaS: Double?
    let errM: Double
    let etaMinS: Double?
    let etaMaxS: Double?
}

enum Estimator {
    static func expectedSpeedKmh(_ h: VehicleKind, _ p: EngineParams) -> Int {
        switch h {
        case .train: p.expectedSpeedKmhTrain
        case .coach: p.expectedSpeedKmhCoach
        case .bus: p.expectedSpeedKmhBus
        case .unknown: p.expectedSpeedKmhUnknown
        }
    }

    static func expectedSpeedMps(_ h: VehicleKind, _ p: EngineParams) -> Double { Double(expectedSpeedKmh(h, p)) / 3.6 }

    static func isEstablished(_ s: EngineState) -> Bool {
        s.movingTimeS >= Double(s.params.speedEstablishedMovingS) && s.movingSamples >= s.params.speedEstablishedSamples
    }

    /// nil when there is no fix yet.
    static func estimate(_ s: EngineState, now: Int64) -> Estimate? {
        guard let last = s.last, let dSmooth = s.dSmooth else { return nil }
        let p = s.params
        let established = isEstablished(s) && s.ground != nil
        let v = established ? s.ground! : expectedSpeedMps(s.config.vehicleHint, p)
        let k: Double
        if !established || s.closing == nil {
            k = p.routeFactorPrior
        } else {
            let c = s.closing!
            k = c > 0 ? TMath.clamp(s.ground! / c, p.routeFactorMin, p.routeFactorMax) : p.routeFactorMax
        }
        let closingV = v / k
        var guardV: Double? = nil
        if s.gps == .lost && !s.cvGuard.isEmpty {
            var m = s.cvGuard[0]
            for x in s.cvGuard.dropFirst() { m = TMath.max(m, x) }
            guardV = m
        }
        let lift = guardV != nil && guardV! > closingV
        let vDr = lift ? guardV! * k : v
        let cvDr = lift ? guardV! : closingV
        let elapsedS = TMath.toS(now - last.fixAtMs)
        let inStop = s.stopStartMs != nil
        let dNow = (s.gps == .ok && inStop) ? dSmooth : TMath.max(0.0, dSmooth - cvDr * elapsedS)
        let penalty = Double(p.etaStopPenaltyS)
        let etaS: Double? = vDr >= p.minSpeedForEtaMps ? dNow * k / vDr + penalty : nil
        let errM = s.gps == .lost ? last.accM + p.lostErrFrac * cvDr * elapsedS : last.accM
        var etaMinS: Double? = nil
        var etaMaxS: Double? = nil
        if etaS != nil {
            etaMinS = TMath.max(0.0, (dNow - errM) * k / vDr) * (1.0 - p.etaUncertaintyFrac) + penalty
            etaMaxS = ((dNow + errM) * k / vDr) * (1.0 + p.etaUncertaintyFrac) + penalty
        }
        return Estimate(established: established, v: v, k: k, closingV: closingV, guardV: guardV, lift: lift, vDr: vDr,
                        cvDr: cvDr, elapsedS: elapsedS, dNow: dNow, etaS: etaS, errM: errM, etaMinS: etaMinS,
                        etaMaxS: etaMaxS)
    }

    /// §4.4 `slow`, at each Step that accepted a fix.
    static func updateSlow(_ s: inout EngineState) {
        let p = s.params
        if !isEstablished(s) || s.ground == nil {
            s.slow = expectedSpeedKmh(s.config.vehicleHint, p) < p.smartSlowSpeedKmh
            return
        }
        let kmh = s.ground! * 3.6
        if !s.slow {
            s.slow = kmh < Double(p.smartSlowSpeedKmh)
        } else if kmh > Double(p.smartSlowSpeedKmh + p.smartSlowHysteresisKmh) {
            s.slow = false
        }
    }
}
