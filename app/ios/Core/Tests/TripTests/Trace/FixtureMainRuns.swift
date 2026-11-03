import Foundation
@testable import Trip

/// One main run of the fixture harness (295, like Kotlin `Suite.outcomes`) with the T10.5 diagnostics: the urgent later shifts
/// (I4 exception, T10.5 §6) and the GPS-gap chord probes (U116, U117).
struct MainRunOutcome: Sendable {
    let run: String
    let traceId: String
    let startMs: Int64
    let urgentShifts: [Checks.UrgentShift]
    let gapProbes: [GapProbe]
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
                    return MainRunOutcome(run: r.run, traceId: t.file.traceId, startMs: r.startMs,
                                          urgentShifts: Checks.urgentShifts(r.records, r.params), gapProbes: r.gapProbes)
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
    }
}
