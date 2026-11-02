// Overshoot, passed-closest net, arrival (T10 §4.11).
enum OvershootDetector {
    static func updateMinDLast3(_ s: inout EngineState) {
        guard let d = s.dSmooth else { return }
        s.minD = s.minD == nil ? d : TMath.min(s.minD!, d)
        var l = s.last3
        l.append(d)
        if l.count > 3 { l.removeFirst(l.count - 3) }
        s.last3 = l
    }

    static func recentSpeed(_ s: EngineState) -> Double {
        TMath.medianHi(s.recent.map { $0.groundSample }) ?? s.ground ?? 0.0
    }

    static func increasing(_ s: EngineState) -> Bool {
        s.last3.count == 3 && s.last3[0] < s.last3[1] && s.last3[1] < s.last3[2]
    }

    static func fast(_ s: EngineState) -> Bool { recentSpeed(s) * 3.6 > Double(s.params.overshootMinSpeedKmh) }

    static func isOvershoot(_ s: EngineState) -> Bool {
        guard s.overshootAtMs == nil, s.phase == .tracking || s.phase == .alarming || s.phase == .snoozed,
              let minD = s.minD, let d = s.dSmooth else { return false }
        let p = s.params
        let nearRadius = TMath.max(p.overshootNearMinM, s.config.mode == .distance ? (s.config.distanceThresholdM ?? 0) : 0)
        return minD < Double(nearRadius) && d - minD >= Double(p.overshootOpenM) && increasing(s) && fast(s)
    }

    static func isPassedClosest(_ s: EngineState, _ e: Estimate?) -> Bool {
        guard let e, s.phase == .acquiring || s.phase == .tracking, s.alarm.atMs == nil, s.gps == .ok,
              let minD = s.minD, let d = s.dSmooth, let dStart = s.dStartM else { return false }
        let p = s.params
        let reachM: Double
        switch s.config.mode {
        case .distance: reachM = Double(s.config.distanceThresholdM ?? 0)
        case .time: reachM = e.closingV * Double(ModeRules.thrS(s.config))
        case .smart: reachM = TMath.max(ModeRules.slowDistM(p), e.closingV * Double(p.smartTargetS))
        }
        let passedRadius = TMath.max(Double(p.passedClosestMinRadiusM), p.passedClosestReachFactor * reachM)
        let openNeedM = TMath.max(Double(p.passedClosestOpenMinM), p.passedClosestOpenFrac * minD)
        return minD < passedRadius && dStart - minD >= Double(p.passedClosestOpenMinM) && d - minD >= openNeedM
            && increasing(s) && fast(s)
    }
}
