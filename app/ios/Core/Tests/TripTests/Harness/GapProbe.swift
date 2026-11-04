@testable import Trip

/// U116 / U117 (T10.5 round 3, 3b–3f; Kotlin `harness/GapProbe.kt`): the GPS-gap chord seen from outside the engine. For a Step on
/// a LocationFix that moved `last`: whether it is a gap fix (round 3f: no IMPLAUSIBLE reject since L), the chord parameter u and
/// distance, `dChord` (only for 0 < u < 1, as in `chordClosest`), and whether the `notCloser` term of the overshoot rule holds on
/// the state after the Step (before any alarm, minDChord, minD < nearRadius, dSmooth − minD ≥ overshootOpenM). `dFixM`: raw
/// distance of the new fix to the destination (U116 a2, T11.3: `d_f − dChord ≥ overshootOpenM`).
struct GapProbe: Sendable {
    let atMs: Int64
    let recovered: Bool
    let gapFix: Bool
    let u: Double?
    let chordM: Double?
    let dChord: Double?
    let standingTerm: Bool
    let dFixM: Double

    static func of(_ s0: EngineState, _ input: LocationFix, _ s1: Step) -> GapProbe? {
        guard let l = s0.last, let f = s1.state.last, f != l, f.fixAtMs == input.fixAtMs else { return nil }
        let recovered = s1.events.contains { if case .gpsRecovered = $0 { return true } else { return false } }
        let gap = s0.rejects.isEmpty && OvershootDetector.isGapFix(s0, l: l, f: f)
        let ch = OvershootDetector.chordProjection(l.lat, l.lng, f.lat, f.lng, s0.config)
        var dChord: Double? = nil
        if gap, let ch, ch.u > 0.0 && ch.u < 1.0 { dChord = ch.distM }
        let dFix = Geo.distanceM(f.lat, f.lng, s0.config.destLat, s0.config.destLng)
        return GapProbe(atMs: input.atMs, recovered: recovered, gapFix: gap, u: ch?.u, chordM: ch?.distM, dChord: dChord,
                        standingTerm: standingTerm(s0, s1), dFixM: dFix)
    }

    /// `notCloser` term of the overshoot rule (rounds 3c–3e), with the phase/alarm before the Step and minD/dSmooth after.
    static func standingTerm(_ s0: EngineState, _ s1: Step) -> Bool {
        let st = s1.state
        let p = st.params
        guard let minD = st.minD, let ds = st.dSmooth else { return false }
        let l3 = st.last3
        let notCloser = st.stopStartMs != nil
            || (l3.count == 3 && l3[2] >= l3[0] && TMath.min(l3[0], TMath.min(l3[1], l3[2])) - minD >= Double(p.overshootOpenM))
        let nearRadius = Double(TMath.max(p.overshootNearMinM, st.config.mode == .distance ? (st.config.distanceThresholdM ?? 0) : 0))
        return s0.overshootAtMs == nil && (s0.phase == .acquiring || s0.phase == .tracking) && s0.alarm.atMs == nil
            && st.minDChord && notCloser && minD < nearRadius && ds - minD >= Double(p.overshootOpenM)
    }
}
