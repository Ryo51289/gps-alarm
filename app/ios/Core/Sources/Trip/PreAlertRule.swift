// Pre-alert zone and rule (T10 §4.6).

enum PreAlertRule {
    static func inZone(_ s: EngineState, _ e: Estimate?) -> Bool {
        guard let e else { return false }
        let p = s.params
        switch s.config.mode {
        case .distance:
            let thr = s.config.distanceThresholdM ?? 0
            return e.dNow <= Double(TMath.max(p.preAlertDistanceFactor * thr, p.preAlertMinDistanceM))
        case .time:
            guard let eta = e.etaS else { return false }
            return eta <= Double(p.preAlertLeadS) && p.preAlertLeadS - ModeRules.thrS(s.config) >= p.preAlertMinGapS
        case .smart:
            guard let eta = e.etaS else { return false }
            return eta <= Double(p.preAlertLeadS)
        }
    }

    static func shouldPreAlert(_ s: EngineState, _ e: Estimate?) -> Bool {
        s.config.preAlertEnabled && s.preAlertArmed && !s.preAlertFired && s.phase == .tracking && inZone(s, e)
    }
}
