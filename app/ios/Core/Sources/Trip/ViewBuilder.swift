// View formulas (T10 §4.16) and history fields (§4.14).

enum ViewBuilder {
    static func vehicleGuess(_ s: EngineState) -> VehicleKind {
        if s.movingTimeS > 0 && s.movingDistM / s.movingTimeS * 3.6 < Double(s.params.vehicleBusMaxAvgKmh) { return .bus }
        switch s.config.vehicleHint {
        case .train: return .train
        case .coach: return .coach
        default: return .unknown
        }
    }

    static func travelledM(_ s: EngineState) -> Int { TMath.roundHalfUp(s.movingDistM) }

    static func summary(_ s: EngineState) -> TripSummary {
        TripSummary(startedAtMs: s.startedAtMs, alarmAtMs: s.alarm.atMs, alarmReason: s.alarm.reason,
                    dismissedAtMs: s.alarm.dismissedAtMs, snoozeCount: s.alarm.snoozeCount, travelledM: travelledM(s),
                    vehicleGuess: vehicleGuess(s))
    }

    static func markerD(_ s: EngineState, _ e: Estimate) -> Double {
        let p = s.params
        switch s.config.mode {
        case .distance:
            return Double(s.config.distanceThresholdM ?? 0) * p.distanceModeFactor
        case .time:
            return TMath.max(Double(p.arrivedRadiusM), e.cvDr * Double(TMath.max(0, ModeRules.thrS(s.config) - p.etaStopPenaltyS)))
        case .smart:
            if s.slow { return ModeRules.slowDistM(p) }
            return TMath.max(Double(p.smartFloorM), e.cvDr * Double(TMath.max(0, p.smartTargetS - p.etaStopPenaltyS)))
        }
    }

    static func buildView(_ s: EngineState, _ e: Estimate?, predicted: Int64?, risk: Bool, wakeAtMs: Int64?) -> TripView {
        var progress: Double? = nil
        var marker: Double? = nil
        if let e {
            let dStart = s.dStartM ?? 0.0
            if dStart <= 0 {
                progress = 1.0
                marker = 1.0
            } else {
                progress = TMath.clamp(1.0 - e.dNow / dStart, 0.0, 1.0)
                marker = TMath.clamp(1.0 - markerD(s, e) / dStart, 0.0, 1.0)
            }
        }
        return TripView(
            tripId: s.config.tripId, atMs: s.nowMs, phase: s.phase, gps: s.gps, locationCause: s.locationCause,
            distanceM: e.map { TMath.roundHalfUp($0.dNow) },
            routeDistanceEstM: e.map { TMath.roundHalfUp($0.dNow * $0.k) },
            distanceErrorM: e.map { TMath.roundHalfUp($0.errM) },
            isEstimated: s.gps == .lost && s.last != nil,
            etaS: e?.etaS.map { TMath.roundHalfUp($0) },
            etaMinS: e?.etaMinS.map { TMath.roundHalfUp($0) },
            etaMaxS: e?.etaMaxS.map { TMath.roundHalfUp($0) },
            speedKmh: s.ground.map { $0 * 3.6 },
            progress: progress, alarmMarkerProgress: marker,
            predictedAlarmAtMs: predicted, samplingPolicy: s.policy,
            fallbackAtMs: s.fallback.targetAtMs, fallbackStatus: s.fallback.status,
            batteryPct: s.battery.levelPct, batteryRisk: risk,
            preAlertFired: s.preAlertFired, alarmAtMs: s.alarm.atMs, alarmReason: s.alarm.lastReason,
            alarmRinging: s.alarm.ringing, snoozeCount: s.alarm.snoozeCount, snoozeUntilMs: s.alarm.snoozeUntilMs,
            overshootPastM: s.overshootPastM, outcome: s.ended?.outcome, vehicleGuess: vehicleGuess(s),
            travelledM: travelledM(s), droppedFixes: s.droppedFixes, wakeAtMs: wakeAtMs)
    }
}
