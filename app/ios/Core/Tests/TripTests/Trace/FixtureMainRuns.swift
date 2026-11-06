import Foundation
@testable import Trip

/// One main run of the fixture harness (340 after T11.5, like Kotlin `Suite.outcomes`) with the T10.5 diagnostics: the urgent
/// later shifts (I4 exception, T10.5 §6) and the GPS-gap chord probes (U116, U117).
struct MainRunOutcome: Sendable {
    let run: String
    let traceId: String
    let startMs: Int64
    /// U116 a2 (T11.3): sampling mode is `policy*`, `truth.gpsGaps` of the trace, nearRadius and overshootOpenM of the case
    /// (Kotlin `caseSetup`).
    let isPolicy: Bool
    let gpsGaps: [(fromT: Int, toT: Int)]
    let nearRadiusM: Int
    let overshootOpenM: Int
    let urgentShifts: [Checks.UrgentShift]
    let gapProbes: [GapProbe]
    /// T10.6 C29.
    let t106: T106Counters
}

/// Computed once per test process (shared by U116 a, U117), sorted by run name; writes the "Urgent later shifts" and "GPS-gap
/// chord" sections of `<report>/trace/summary.md` (Kotlin `Suite.urgentShiftReport`, `Suite.gapReport`).
enum FixtureMainRuns {
    static let all: Task<[MainRunOutcome], Never> = Task { await compute() }

    static func compute() async -> [MainRunOutcome] {
        var jobs: [(LoadedTrace, CaseSpec, String)] = []
        for ref in CaseCatalog.refs {
            guard let loaded = try? CaseCatalog.load(ref) else { continue }
            let (t, spec) = loaded
            for m in CaseCatalog.modes(spec, interval: t.file.intervalS) { jobs.append((t, spec, m)) }
        }
        let out = await withTaskGroup(of: MainRunOutcome.self) { g in
            for (t, spec, m) in jobs {
                g.addTask {
                    var r = Runner(trace: t, spec: spec, mode: m, options: RunOptions(probes: false))
                    r.runAll()
                    let nearRadius = max(r.params.overshootNearMinM, r.config.mode == .distance ? (r.config.distanceThresholdM ?? 0) : 0)
                    return MainRunOutcome(run: r.run, traceId: t.file.traceId, startMs: r.startMs, isPolicy: r.isPolicy,
                                          gpsGaps: t.file.gpsGaps, nearRadiusM: nearRadius, overshootOpenM: r.params.overshootOpenM,
                                          urgentShifts: Checks.urgentShifts(r.records, r.params), gapProbes: r.gapProbes,
                                          t106: r.t106)
                }
            }
            var res: [MainRunOutcome] = []
            for await x in g { res.append(x) }
            return res
        }
        let sorted = out.sorted { $0.run < $1.run }
        report(sorted)
        return sorted
    }

    static func f3(_ x: Double) -> String { String(format: "%.3f", x) }

    static func report(_ outs: [MainRunOutcome]) {
        let withShift = outs.filter { !$0.urgentShifts.isEmpty }
        let total = withShift.reduce(0) { $0 + $1.urgentShifts.count }
        var md = "## Urgent later shifts (T10.5 §6, I4 exception), all main runs\n\n"
        md += "Total: \(total) in \(withShift.count) of \(outs.count) runs\n"
        if !withShift.isEmpty {
            md += "\n| run | t | F before (s) | F after (s) | predicted (s) |\n|---|---|---|---|---|\n"
            for o in withShift {
                func rel(_ ms: Int64?) -> String { ms.map { f3(Double($0 - o.startMs) / 1000.0) } ?? "-" }
                for u in o.urgentShifts {
                    md += "| \(o.run) | \(u.t) | \(rel(u.prevTarget)) | \(rel(u.newTarget)) | \(rel(u.predicted)) |\n"
                }
            }
        }
        Report.shared.writePart(dir: "trace", name: "t105-urgent-shifts", markdown: md + "\n", json: nil)

        let all = outs.flatMap { o in o.gapProbes.map { (o, $0) } }
        var g = "## GPS-gap chord (T10.5 round 3/3b, U116 a, U117), all main runs\n\n"
        g += "Probes (GpsRecovered or gap fix): \(all.count), gap fixes: \(all.filter { $0.1.gapFix }.count), 0 < u < 1: "
            + "\(all.filter { $0.1.dChord != nil }.count), standing term: \(all.filter { $0.1.standingTerm }.count)\n\n"
            + "| trace | runs | probes | gap fixes | u range | dChord min (m) | standing term |\n|---|---|---|---|---|---|---|\n"
        for trace in Set(all.map { $0.0.traceId }).sorted() {
            let list = all.filter { $0.0.traceId == trace }
            let us = list.compactMap { $0.1.u }
            let dc = list.compactMap { $0.1.dChord }
            let runs = Set(list.map { $0.0.run }).count
            let uRange = us.isEmpty ? "-" : "\(f3(us.reduce(us[0]) { TMath.min($0, $1) }))..\(f3(us.reduce(us[0]) { TMath.max($0, $1) }))"
            let dMin = dc.isEmpty ? "-" : f3(dc.reduce(dc[0]) { TMath.min($0, $1) })
            g += "| \(trace) | \(runs) | \(list.count) | \(list.filter { $0.1.gapFix }.count) | \(uRange) | \(dMin) | "
                + "\(list.filter { $0.1.standingTerm }.count) |\n"
        }
        Report.shared.writePart(dir: "trace", name: "t105-gap-chord", markdown: g + "\n", json: nil)

        // T10.6 C29 (Kotlin `Suite.t106Report`): preVLiftSteps, longLostAlarms, slowAwayAlarms over all main runs.
        var c = "### T10.6 counters (C29), all main runs\n\n"
        c += "preVLiftSteps: \(outs.reduce(0) { $0 + $1.t106.preVLiftSteps }), longLostAlarms: "
            + "\(outs.reduce(0) { $0 + $1.t106.longLostAlarms.count }), slowAwayAlarms: "
            + "\(outs.reduce(0) { $0 + $1.t106.slowAwayAlarms.count })\n\n"
        for o in outs {
            let x = o.t106
            if x.preVLiftSteps == 0 && x.longLostAlarms.isEmpty && x.slowAwayAlarms.isEmpty { continue }
            c += "- \(o.run): preVLiftSteps \(x.preVLiftSteps), longLost \(KW.klist(x.longLostAlarms)), "
                + "slowAway \(KW.klist(x.slowAwayAlarms))\n"
        }
        Report.shared.writePart(dir: "trace", name: "t106-counters", markdown: c, json: nil)
    }
}
