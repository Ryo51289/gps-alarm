// Speed sample, stop hysteresis, EMA and lost-GPS speed guard (T10 §4.4, T10.1).

enum MotionClass: Sendable, Equatable { case stationary, moving, unknown }

struct SpeedSample: Sendable, Equatable {
    let raw: MotionClass
    let groundSample: Double?
    let closingSample: Double?
    let dt: Double
}

enum SpeedEstimator {
    /// Speed sample of `f` against `last` (f.d is the raw distance to the destination).
    static func speedSample(last: FixRec, f: FixRec, speedMps: Double?, _ p: EngineParams) -> SpeedSample {
        let dt = TMath.toS(f.fixAtMs - last.fixAtMs)
        let disp = Geo.distanceM(f.lat, f.lng, last.lat, last.lng)
        if dt > Double(p.maxSpeedSampleGapS) {
            return SpeedSample(raw: .unknown, groundSample: nil, closingSample: nil, dt: dt)
        }
        let goodPair = f.accM <= p.speedSampleMaxAccM && last.accM <= p.speedSampleMaxAccM
        let coarseOk = (f.accM + last.accM) <= 0.2 * disp
        var raw: MotionClass
        var ground: Double?
        if let spd = speedMps, f.accM <= p.speedSampleMaxAccM {
            ground = spd
            raw = spd < p.stationarySpeedMps ? .stationary : .moving
        } else if goodPair && disp <= p.motionAccFactor * (f.accM + last.accM) {
            ground = nil
            raw = .stationary
        } else if goodPair || coarseOk {
            let g = disp / dt
            ground = g
            raw = g < p.stationarySpeedMps ? .stationary : .moving
        } else {
            ground = nil
            raw = .unknown
        }
        let closing: Double? = (goodPair || coarseOk) ? (last.d - f.d) / dt : nil
        return SpeedSample(raw: raw, groundSample: ground, closingSample: closing, dt: dt)
    }

    /// closingVOf(g, c) = g / (c == nil ? prior : c > 0 ? clamp(g / c, min, max) : max).
    static func closingVOf(_ g: Double, _ c: Double?, _ p: EngineParams) -> Double {
        let k: Double
        if let c {
            k = c > 0 ? TMath.clamp(g / c, p.routeFactorMin, p.routeFactorMax) : p.routeFactorMax
        } else {
            k = p.routeFactorPrior
        }
        return g / k
    }

    /// Stop hysteresis + EMA update for an ACCEPTed fix `f` (with `last` = previous fix).
    static func applyMotion(_ s: inout EngineState, last: FixRec, f: FixRec, sample: SpeedSample) {
        let p = s.params
        switch sample.raw {
        case .unknown:
            return
        case .stationary:
            if s.stopStartMs == nil {
                s.stopStartMs = f.fixAtMs
                s.stopAnchor = f
            }
        case .moving:
            let inStop = s.stopStartMs != nil
            if inStop, let anchor = s.stopAnchor {
                let exitM = TMath.max(Double(p.stopExitMinM), f.accM + anchor.accM)
                if Geo.distanceM(f.lat, f.lng, anchor.lat, anchor.lng) <= exitM { return }
            }
            // T10.1 guard: record closingV before any blend of this fix.
            let estBefore = s.movingTimeS >= Double(p.speedEstablishedMovingS)
                && s.movingSamples >= p.speedEstablishedSamples
            if p.lostSpeedGuardUpdates > 0 && estBefore, let g = s.ground {
                var cv = s.cvGuard
                cv.append(closingVOf(g, s.closing, p))
                if cv.count > p.lostSpeedGuardUpdates { cv.removeFirst(cv.count - p.lostSpeedGuardUpdates) }
                s.cvGuard = cv
            }
            if inStop, let stopStart = s.stopStartMs {
                let stopS = TMath.toS(last.fixAtMs - stopStart)
                if stopS <= Double(p.shortStopIncludeS) {
                    if let g = s.ground { s.ground = TMath.blend(g, 0.0, stopS, tauS: p.speedEmaTauS) }
                    if let c = s.closing { s.closing = TMath.blend(c, 0.0, stopS, tauS: p.speedEmaTauS) }
                }
                s.stopStartMs = nil
                s.stopAnchor = nil
            }
            guard let gs = sample.groundSample else { return }
            s.ground = TMath.blend(s.ground, gs, sample.dt, tauS: p.speedEmaTauS)
            if let cs = sample.closingSample { s.closing = TMath.blend(s.closing, cs, sample.dt, tauS: p.speedEmaTauS) }
            s.movingTimeS += sample.dt
            s.movingSamples += 1
            s.movingDistM += gs * sample.dt
        }
    }
}
