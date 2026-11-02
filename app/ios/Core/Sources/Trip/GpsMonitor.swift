// GPS status machine (T10 §4.8, T12 C5).

enum GpsMonitor {
    static func lostAfterS(_ s: EngineState) -> Int {
        let p = s.params
        return TMath.max(p.gpsLostMinS, p.gpsLostIntervalFactor * TMath.max(s.policyIntervalAtLastFixS, s.policy?.intervalS ?? 0))
    }

    static func lastFixAgeS(_ s: EngineState, now: Int64) -> Int? {
        guard let last = s.last else { return nil }
        return TMath.roundHalfUp(TMath.toS(now - last.fixAtMs))
    }

    /// A fix was ACCEPTed/REANCHORed.
    static func onFixReceived(_ s: inout EngineState, now: Int64, events: inout [TripEvent]) {
        // As Kotlin (C17): GpsRecovered only when recovering and gpsLostAtMs is set; then gpsLostAtMs = nil.
        let recovering = s.gps == .lost || (s.gps == .noFixYet && s.lostEmittedBeforeFirstFix)
        if recovering, let lostAt = s.gpsLostAtMs {
            events.append(.gpsRecovered(.init(atMs: now, lostForS: TMath.roundHalfUp(TMath.toS(now - lostAt)))))
            s.gpsLostAtMs = nil
        }
        s.gps = .ok
        s.locationCause = .available
    }

    static func onAvailability(_ s: inout EngineState, now: Int64, cause: AvailabilityCause, events: inout [TripEvent]) {
        guard cause != .available else {
            s.locationCause = .available
            return
        }
        let lostCause: GpsLostCause = cause == .permissionRevoked ? .permissionRevoked : .servicesOff
        switch s.gps {
        case .ok:
            events.append(.gpsLost(.init(atMs: now, cause: lostCause, lastFixAgeS: lastFixAgeS(s, now: now))))
            s.gps = .lost
            s.gpsLostAtMs = now
        case .noFixYet:
            if !s.lostEmittedBeforeFirstFix {
                events.append(.gpsLost(.init(atMs: now, cause: lostCause, lastFixAgeS: nil)))
                s.lostEmittedBeforeFirstFix = true
                s.gpsLostAtMs = now
            }
        case .lost:
            break
        }
        s.locationCause = cause
    }

    /// Step 4: acquire timeout and lost timeout.
    static func onTime(_ s: inout EngineState, now: Int64, events: inout [TripEvent]) {
        let p = s.params
        switch s.gps {
        case .noFixYet:
            if !s.lostEmittedBeforeFirstFix && now - s.startedAtMs >= TMath.ms(p.acquireTimeoutS) {
                events.append(.gpsLost(.init(atMs: now, cause: .neverAcquired, lastFixAgeS: nil)))
                s.lostEmittedBeforeFirstFix = true
                s.gpsLostAtMs = now
            }
        case .ok:
            if let last = s.last, now - last.fixAtMs >= TMath.ms(lostAfterS(s)) {
                events.append(.gpsLost(.init(atMs: now, cause: .noFixTimeout, lastFixAgeS: lastFixAgeS(s, now: now))))
                s.gps = .lost
                s.gpsLostAtMs = now
            }
        case .lost:
            break
        }
    }
}
