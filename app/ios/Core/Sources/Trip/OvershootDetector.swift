// Overshoot, passed-closest net, arrival (T10 §4.11). Only evaluated on a Step with an accepted fix.
// T10.5 round 3/3b: destination passed inside a GPS gap (the chord between the fix before the gap and the first fix after it
// lowers minD; no immediate chord alarm, round 3b). Round 3c–3f: the `notCloser` overshoot term, gated by `minDChord`.
// T10.7: also after an alarm (ALARMING/SNOOZED), so a chime that stopped by itself re-rings OVERSHOOT by the usual rule
// (increasing && fast) when the vehicle passed the destination inside the gap (RK24).
// T10.7 round 2 (C31): after the alarm the chord only proves "came near" (alarmedChordD → nearD), never "moved away 1 km".

/// Projection of the destination on the chord L → f in a local plane around it: parameter u and distance (m).
struct Chord: Sendable, Equatable {
    let u: Double
    let distM: Double
}

enum OvershootDetector {
    /// ACCEPT: minD and the last 3 dSmooth values.
    static func updateMinDLast3(_ s: inout EngineState) {
        guard let d = s.dSmooth else { return }
        if s.minD == nil || d < s.minD! {
            s.minD = d
            s.minDChord = false   // T10.5 round 3e: an observed fix closer than the chord (equal keeps the flag)
        }
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

    static func nearRadiusM(_ s: EngineState) -> Double {
        Double(TMath.max(s.params.overshootNearMinM, s.config.mode == .distance ? (s.config.distanceThresholdM ?? 0) : 0))
    }

    /// T10.7 round 2 (C31): "came near" distance — minD, or min(minD, alarmedChordD) when a chord was taken after the first alarm
    /// (exactly minD, no call to min, when alarmedChordD is nil).
    static func nearD(_ s: EngineState) -> Double? {
        guard let m = s.minD else { return nil }
        guard let a = s.alarmedChordD else { return m }
        return TMath.min(m, a)
    }

    static func isOvershoot(_ s: EngineState) -> Bool {
        guard s.overshootAtMs == nil, s.phase == .tracking || s.phase == .alarming || s.phase == .snoozed,
              let minD = s.minD, let d = s.dSmooth else { return false }
        let p = s.params
        // T10.5 round 3b/3c: or, before any alarm, the vehicle is not getting closer: a stop in progress, or dSmooth not below its
        // value 2 fixes earlier (lag-2, also true for repeated or alternating coordinates of a parked vehicle with poor fixes).
        // Round 3d: the 3 smoothed distances are all >= minD + overshootOpenM, so one accepted outlier fix cannot fake minD.
        // Round 3e: only while minD comes from the GPS-gap chord (minDChord); normal tracking is the T12.1 rule.
        let l3 = s.last3
        let notCloser = s.stopStartMs != nil
            || (l3.count == 3 && l3[2] >= l3[0] && TMath.min(l3[0], TMath.min(l3[1], l3[2])) - minD >= Double(p.overshootOpenM))
        let notYet = (s.phase == .acquiring || s.phase == .tracking) && s.alarm.atMs == nil
        // T10.7 round 2 (C31): (1) came near uses nearD (may come from a chord after the alarm); (2) moved away > 1 km uses minD
        // (observed fixes, or a chord before any alarm), never alarmedChordD.
        let nd = nearD(s)!
        return nd < nearRadiusM(s) && d - minD >= Double(p.overshootOpenM)
            && ((increasing(s) && fast(s)) || (notYet && s.minDChord && notCloser))
    }

    /// T10.5 round 3 `chordClosest` without the `0 < u < 1` test (diagnostics, U116). Local plane around the destination with
    /// cosDeg(destLat) (D1: only + − × ÷ sqrt, same operation order as Kotlin); nil when a longitude is more than 180° away or the
    /// chord has zero length.
    static func chordProjection(_ lLat: Double, _ lLng: Double, _ fLat: Double, _ fLng: Double, _ cfg: TripConfig) -> Chord? {
        if (lLng - cfg.destLng).magnitude > 180.0 || (fLng - cfg.destLng).magnitude > 180.0 { return nil }
        let m = Geo.kEarthRadiusM * Geo.kDegToRad
        let c = Geo.cosDeg(cfg.destLat)
        let ax = (lLng - cfg.destLng) * c * m
        let ay = (lLat - cfg.destLat) * m
        let ex = (fLng - cfg.destLng) * c * m - ax
        let ey = (fLat - cfg.destLat) * m - ay
        let len2 = ex * ex + ey * ey
        if len2 == 0.0 { return nil }
        let u = -(ax * ex + ay * ey) / len2
        let px = ax + u * ex
        let py = ay + u * ey
        return Chord(u: u, distM: (px * px + py * py).squareRoot())
    }

    /// T10 §4.11 (T10.5 round 3) `chordClosest`: distance from the destination to the chord L → f, only when 0 < u < 1.
    static func chordClosest(_ l: FixRec, _ f: FixRec, _ cfg: TripConfig) -> Double? {
        guard let ch = chordProjection(l.lat, l.lng, f.lat, f.lng, cfg) else { return nil }
        return ch.u > 0.0 && ch.u < 1.0 ? ch.distM : nil
    }

    /// T10.5 round 3 `gapFix`: first accepted fix after a GPS gap. `s` is the state before step 2 changed phase / gps /
    /// policyIntervalAtLastFixS / policy; `l` is `last` before this fix. (Round 3f's `rejects` test is the caller's.)
    /// T10.7 (C30, RK24): also after an alarm (ALARMING/SNOOZED); there the chord only sets alarmedChordD (round 2, C31).
    static func isGapFix(_ s: EngineState, l: FixRec?, f: FixRec) -> Bool {
        guard let l, s.phase == .acquiring || s.phase == .tracking || s.phase == .alarming || s.phase == .snoozed,
              s.overshootAtMs == nil else { return false }
        return s.gps == .lost || f.fixAtMs - l.fixAtMs >= TMath.ms(GpsMonitor.lostAfterS(s))
    }

    static func passedRadiusM(_ s: EngineState, _ e: Estimate) -> Double {
        let p = s.params
        let reachM: Double
        switch s.config.mode {
        case .distance: reachM = Double(s.config.distanceThresholdM ?? 0)
        case .time: reachM = e.closingV * Double(ModeRules.thrS(s.config))
        case .smart: reachM = TMath.max(ModeRules.slowDistM(p), e.closingV * Double(p.smartTargetS))
        }
        return TMath.max(Double(p.passedClosestMinRadiusM), p.passedClosestReachFactor * reachM)
    }

    static func openNeedM(_ p: EngineParams, _ minD: Double) -> Double {
        TMath.max(Double(p.passedClosestOpenMinM), p.passedClosestOpenFrac * minD)
    }

    static func isPassedClosest(_ s: EngineState, _ e: Estimate?) -> Bool {
        guard let e, s.phase == .acquiring || s.phase == .tracking, s.alarm.atMs == nil, s.gps == .ok,
              let minD = s.minD, let d = s.dSmooth, let dStart = s.dStartM else { return false }
        let p = s.params
        let passedRadius = passedRadiusM(s, e)
        return minD < passedRadius && dStart - minD >= Double(p.passedClosestOpenMinM) && d - minD >= openNeedM(p, minD)
            && increasing(s) && (fast(s) || slowAway(s))
    }

    /// T10.6 (3), C27: on every Step with an accepted fix (ACCEPT/REANCHOR), after step 7 and before alarmReason, in every phase.
    /// The mark is the smoothed distance measured once the gap to minD is already open, from good (GNSS) fixes only, going down
    /// only; it is cleared whenever the geometric terms of passedClosest stop holding.
    static func updatePassAnchor(_ s: inout EngineState, _ e: Estimate?) {
        let p = s.params
        var passOpen = false
        if p.passedClosestSlowRiseM > 0, let e, let minD = s.minD, let ds = s.dSmooth, let dStart = s.dStartM, s.last != nil,
           s.phase == .acquiring || s.phase == .tracking, s.alarm.atMs == nil, s.gps == .ok {
            passOpen = minD < passedRadiusM(s, e) && dStart - minD >= Double(p.passedClosestOpenMinM)
                && ds - minD >= openNeedM(p, minD)
        }
        if !passOpen {
            s.passAnchorD = nil
            return
        }
        if !isGoodFix(s) { return }
        let ds = s.dSmooth!
        if let a = s.passAnchorD {
            s.passAnchorD = TMath.min(a, ds)
        } else {
            s.passAnchorD = ds
        }
    }

    static func isGoodFix(_ s: EngineState) -> Bool {
        guard let f = s.last else { return false }
        return f.accM <= s.params.speedSampleMaxAccM
    }

    /// T10.6 (3), C27: two smoothed distances in a row at least passedClosestSlowRiseM above the mark (read after the update).
    static func slowAway(_ s: EngineState) -> Bool {
        guard let a = s.passAnchorD else { return false }
        let l3 = s.last3
        return isGoodFix(s) && l3.count == 3 && l3[1] - a >= Double(s.params.passedClosestSlowRiseM)
    }
}
