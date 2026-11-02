import Foundation
@testable import Trip

/// Kill-time sweep (T10 §8.1-6, T12 §8.6): checks per run, statistics per case (`all` and pooled policy phases).
struct KillPoint: Sendable {
    let k: Int
    let remainS: Int        // arrival − k
    let fbRel: Int64        // floor((fb − startMs)/1000)
    let lateS: Int64        // fbRel − notAfter
    let earlyS: Int64       // earlyFrom − fbRel
    let tAtDeath: Int64?    // floor((predicted(view after k−I) − nowMs(k−I))/1000)
}

struct KillRunStats: Sendable {
    let mode: String
    let points: [KillPoint]
    let facTimes: [Int]
    let farFacTimes: [Int]
    let tA: Int
}

enum KillSweep {
    /// Checks one run; returns failures and the stats (nil when the run has no alarm).
    static func evaluate(_ r: Runner, _ ks: KillSweepSpec) -> ([String], KillRunStats?) {
        let tag = "[\(r.run) killSweep j=\(r.j)]"
        guard let tA = r.firstAlarmT else { return (["\(tag) config error: killSweep: không có alarm"], nil) }
        guard let from = r.resolve(ks.from), let notAfter = r.resolve(ks.notAfter), let early = r.resolve(ks.earlyFrom) else {
            return (["\(tag) config error: killSweep anchor unresolved"], nil)
        }
        var fails: [String] = []
        var points: [KillPoint] = []
        let arrival = r.trace.file.arrivalT
        var k = from
        // first tick ≥ from
        if k % r.interval != 0 { k += r.interval - k % r.interval }
        while k <= tA {
            let idx = (k - r.interval) / r.interval
            guard idx >= 0, let fb = r.fbOsAfterTick[idx] else {
                fails.append("\(tag) k=\(k): fbOs(k − I) is null")
                k += ks.everyS
                continue
            }
            let rel = Checks.floorDiv(fb - r.startMs, 1000)
            if !ks.statsOnly && rel > Int64(notAfter) {
                fails.append("\(tag) k=\(k): fbOs=\(rel) > notAfter=\(notAfter)")
            }
            let pred = r.predictedAfterTick[idx]
            let tDeath = pred.map { Checks.floorDiv($0 - r.nowMs(k - r.interval), 1000) }
            points.append(KillPoint(k: k, remainS: arrival - k, fbRel: rel, lateS: rel - Int64(notAfter),
                                    earlyS: Int64(early) - rel, tAtDeath: tDeath))
            k += ks.everyS
        }
        var fac: [Int] = [], far: [Int] = []
        let nearMs = Int64(r.params.fallbackNearS) * 1000
        for rec in r.records where rec.t <= tA {
            for e in rec.events {
                guard case .fallbackAlarmChanged = e else { continue }
                fac.append(rec.t)
                if let p = rec.view.predictedAlarmAtMs, p - r.nowMs(rec.t) > nearMs { far.append(rec.t) }
            }
        }
        return (fails, KillRunStats(mode: r.mode, points: points, facTimes: fac, farFacTimes: far, tA: tA))
    }

    static func nearestRank(_ sorted: [Int64], _ p: Double) -> Int64? {
        guard !sorted.isEmpty else { return nil }
        var idx = Int((p * Double(sorted.count)).rounded(.up)) - 1
        if idx < 0 { idx = 0 }
        return sorted[min(idx, sorted.count - 1)]
    }

    static func maxInWindow(_ times: [Int], _ w: Int) -> Int {
        var best = 0, lo = 0
        for hi in 0..<times.count {
            while times[hi] - times[lo] >= w { lo += 1 }
            best = max(best, hi - lo + 1)
        }
        return best
    }

    struct Group: Sendable {
        let label: String
        let runs: [KillRunStats]
    }

    /// Markdown + JSON for one case. `reference` = (late %, late max s) for TR37 (f), (g) WARN lines.
    static func summarize(caseName: String, statsOnly: Bool, groups: [Group], nearS: Int,
                          reference: (Double, Int64)?) -> (String, String) {
        var md = "## \(caseName)\(statsOnly ? " (statsOnly)" : "")\n\n"
        md += "| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |\n"
        md += "|---|---|---|---|---|---|---|---|---|---|\n"
        var json = "{\"case\":\"\(caseName)\",\"statsOnly\":\(statsOnly),\"groups\":["
        var jsonGroups: [String] = []
        var detail = ""
        for g in groups {
            let pts = g.runs.flatMap(\.points)
            let late = pts.filter { $0.lateS > 0 }
            let pct = pts.isEmpty ? 0 : Double(late.count) * 100.0 / Double(pts.count)
            let lateMax = late.map(\.lateS).max() ?? 0
            let lateMean = late.isEmpty ? 0.0 : Double(late.map(\.lateS).reduce(0, +)) / Double(late.count)
            let hours = g.runs.map { Double(max($0.tA, 1)) / 3600.0 }.reduce(0, +)
            let facs = g.runs.map(\.facTimes.count).reduce(0, +)
            let farFacs = g.runs.map(\.farFacTimes.count).reduce(0, +)
            let maxWin = g.runs.map { maxInWindow($0.facTimes, 3600) }.max() ?? 0
            let minMargin = pts.map { -$0.lateS }.min() ?? 0
            md += "| \(g.label) | \(pts.count) | \(late.count) | \(fmt(pct)) | \(lateMax) | \(fmt(lateMean)) | \(minMargin) | "
                + "\(fmt(Double(facs) / hours)) | \(fmt(Double(farFacs) / hours)) | \(maxWin) |\n"
            if let (refPct, refMax) = reference, pct > refPct + 10.0 || lateMax > refMax + 300 {
                detail += "\nWARN \(caseName) \(g.label): late \(fmt(pct)) % (ref \(fmt(refPct)) %), max \(lateMax) s (ref \(refMax) s)\n"
            }
            // Earliness by remaining time.
            let buckets: [(String, (Int) -> Bool)] = [("< 1 h", { $0 < 3600 }), ("1–2 h", { $0 >= 3600 && $0 < 7200 }),
                                                      ("2–4 h", { $0 >= 7200 && $0 < 14400 }), ("> 4 h", { $0 >= 14400 })]
            detail += "\nEarliness `earlyFrom − fb` (s), \(g.label):\n\n| arrival − k | n | p10 | p50 | p90 | max |\n|---|---|---|---|---|---|\n"
            var jb: [String] = []
            for (name, pred) in buckets {
                let xs = pts.filter { pred($0.remainS) }.map(\.earlyS).sorted()
                let p10 = nearestRank(xs, 0.1), p50 = nearestRank(xs, 0.5), p90 = nearestRank(xs, 0.9)
                detail += "| \(name) | \(xs.count) | \(s(p10)) | \(s(p50)) | \(s(p90)) | \(s(xs.last)) |\n"
                jb.append("{\"bucket\":\"\(name)\",\"n\":\(xs.count),\"p10\":\(s(p10)),\"p50\":\(s(p50)),\"p90\":\(s(p90)),\"max\":\(s(xs.last))}")
            }
            let worst = late.sorted { $0.lateS != $1.lateS ? $0.lateS > $1.lateS : $0.k < $1.k }.prefix(10)
            if !worst.isEmpty {
                detail += "\n10 latest k, \(g.label):\n\n| k | arrival − k | fb | T at death | zone |\n|---|---|---|---|---|\n"
                for w in worst {
                    let zone = (w.tAtDeath ?? 0) <= Int64(nearS) ? "near" : "far"
                    detail += "| \(w.k) | \(w.remainS) | \(w.fbRel) | \(s(w.tAtDeath)) | \(zone) |\n"
                }
            }
            jsonGroups.append("{\"mode\":\"\(g.label)\",\"k\":\(pts.count),\"late\":\(late.count),\"latePct\":\(fmt(pct)),"
                + "\"lateMaxS\":\(lateMax),\"minMarginS\":\(minMargin),\"lateMeanS\":\(fmt(lateMean)),\"facPerHour\":\(fmt(Double(facs) / hours)),"
                + "\"farFacPerHour\":\(fmt(Double(farFacs) / hours)),\"maxFacIn3600s\":\(maxWin),\"early\":[\(jb.joined(separator: ","))],"
                + "\"latest\":[" + worst.map { "{\"k\":\($0.k),\"remainS\":\($0.remainS),\"fb\":\($0.fbRel),\"T\":\(s($0.tAtDeath))}" }
                    .joined(separator: ",") + "]}")
        }
        json += jsonGroups.joined(separator: ",") + "]}"
        return (md + detail + "\n", json)
    }

    static func fmt(_ x: Double) -> String { String(format: "%.1f", x) }
    static func s(_ x: Int64?) -> String { x.map(String.init) ?? "null" }
}
