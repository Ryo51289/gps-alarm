// Fix filter (T10 §4.2) and distance smoother (§4.3).

enum FixVerdict: Sendable, Equatable {
    case drop
    case reanchor(Double)
    case accept(Double)
}

enum FixFilter {
    /// T12 §6: (distanceM(a,b) − (a.accM + b.accM)) <= maxPlausibleSpeedMps · toS(b.fixAtMs − a.fixAtMs).
    static func plausible(_ a: FixRec, _ b: FixRec, _ p: EngineParams) -> Bool {
        (Geo.distanceM(a.lat, a.lng, b.lat, b.lng) - (a.accM + b.accM))
            <= p.maxPlausibleSpeedMps * TMath.toS(b.fixAtMs - a.fixAtMs)
    }

    /// Classifies `fix` (a FixRec with `d` = 0 placeholder) against `state`; updates `rejects` as §4.2 requires.
    /// Returns the verdict; for DROP the caller increments `droppedFixes`.
    static func classifyFix(_ s: inout EngineState, atMs: Int64, fix f: inout FixRec) -> FixVerdict {
        let p = s.params
        if atMs - f.fixAtMs > TMath.ms(p.fixMaxAgeS) { return .drop }
        if let last = s.last, f.fixAtMs <= last.fixAtMs { return .drop }
        if !(f.accM.isFinite && f.accM > 0) || !f.lat.isFinite || !f.lng.isFinite
            || !(f.lat >= -90.0 && f.lat <= 90.0) || !(f.lng >= -180.0 && f.lng < 180.0) {
            return .drop
        }
        let d = Geo.distanceM(f.lat, f.lng, s.config.destLat, s.config.destLng)
        f.d = d
        if f.accM > TMath.min(p.accHardMaxM, TMath.max(p.accAbsMaxM, p.accRelMax * d)) { return .drop }
        if let last = s.last, !plausible(last, f, p) {
            var r = s.rejects
            r.append(f)
            if r.count > 3 { r.removeFirst(r.count - 3) }
            s.rejects = r
            if r.count == 3 && r[2].fixAtMs - r[0].fixAtMs >= TMath.ms(p.outlierResetSpanS)
                && plausible(r[0], r[1], p) && plausible(r[1], r[2], p) {
                return .reanchor(d)
            }
            return .drop
        }
        s.rejects = []
        return .accept(d)
    }

    /// §4.3: keep fixes within smoothWindowS of `f`, append `f`, keep the newest 3; dSmooth = medianHi(d).
    static func updateRecent(_ s: inout EngineState, _ f: FixRec) {
        let cutoff = f.fixAtMs - TMath.ms(s.params.smoothWindowS)
        var r: [FixRec] = []
        for x in s.recent where x.fixAtMs >= cutoff { r.append(x) }
        r.append(f)
        if r.count > 3 { r.removeFirst(r.count - 3) }
        s.recent = r
        s.dSmooth = TMath.medianHi(r.map { Optional($0.d) })
    }
}
