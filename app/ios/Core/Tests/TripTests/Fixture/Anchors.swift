/// Anchor resolution (README §3.1 "Mốc thời gian At"). Static anchors come from the trace; run anchors from the run.
enum Anchors {
    static let runPrefixes = ["event:", "relaunch", "osFallbackFired"]

    static func isRun(_ anchor: String) -> Bool {
        anchor.hasPrefix("event:") || anchor == "relaunch" || anchor == "osFallbackFired"
    }

    /// Static anchor value (without offset); nil if unknown.
    static func staticValue(_ anchor: String, trace: TraceFile, killT: Int?) -> Int? {
        switch anchor {
        case "start": return 0
        case "end": return trace.durationS
        case "arrival": return trace.arrivalT
        case "overshoot": return trace.overshootT
        case "closest": return trace.closestT
        case "closest.departT": return trace.closestDepartT
        case "kill": return killT
        default:
            if anchor.hasPrefix("gpsGap[") {
                let inner = anchor.dropFirst("gpsGap[".count)
                guard let close = inner.firstIndex(of: "]"), let i = Int(inner[inner.startIndex..<close]),
                      i < trace.gpsGaps.count else { return nil }
                let rest = inner[inner.index(after: close)...]
                if rest == ".start" { return trace.gpsGaps[i].fromT }
                if rest == ".end" { return trace.gpsGaps[i].toT }
                return nil
            }
            if anchor.hasPrefix("route<="), let m = Int(anchor.dropFirst(7)) { return trace.routeT[m] }
            if anchor.hasPrefix("straight<="), let m = Int(anchor.dropFirst(10)) { return trace.straightT[m] }
            return nil
        }
    }

    /// B = anchor + offsetS, using `t` when present (static At already include the offset).
    static func resolve(_ at: At, trace: TraceFile, killT: Int?, run: [String: Int]) -> Int? {
        if let t = at.t { return t }
        guard let a = at.anchor else { return nil }
        if isRun(a) { return run[a].map { $0 + at.offsetS } }
        if a == "kill" { return killT.map { $0 + at.offsetS } }
        return staticValue(a, trace: trace, killT: killT).map { $0 + at.offsetS }
    }
}
