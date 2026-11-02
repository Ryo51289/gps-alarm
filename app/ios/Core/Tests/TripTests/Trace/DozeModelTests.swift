import Foundation
import Testing
@testable import Trip

/// TR39 (T10 mục T10.4 §7.3): Doze model on the fixture. Every case on a trace with `gpsGaps` and without kill / relaunch /
/// osDismiss / allowFallbackFirst, mode `all`: inside the GPS gaps the platform delivers no grid Tick, only Tick(wakeAtMs) and
/// the OS fallback (whichever is earlier). Compared with the normal `all` run of the same case. Check only, not in the P05
/// manifest (like TR36). Same as T12 `DozeModelTest`.
@Suite("DozeModelTests")
struct DozeModelTests {
    struct Row: Sendable {
        let name: String
        let fails: [String]
        let md: String
    }

    static func firstLost(_ r: Runner) -> TripEvent.GpsLost? {
        for rec in r.records { for e in rec.events { if case let .gpsLost(g) = e { return g } } }
        return nil
    }

    static func firstAlarm(_ r: Runner) -> (t: Int, a: TripEvent.Alarm)? {
        for rec in r.records { for e in rec.events { if case let .alarm(a) = e { return (rec.t, a) } } }
        return nil
    }

    /// Seconds from the start with 3 decimals ("-" for nil); integer arithmetic, no locale.
    static func s3(_ ms: Int64?, _ startMs: Int64) -> String {
        guard let ms else { return "-" }
        let d = ms - startMs
        let sign = d < 0 ? "-" : ""
        let a = d < 0 ? -d : d
        let frac = String(a % 1000)
        return "\(sign)\(a / 1000).\(String(repeating: "0", count: 3 - frac.count))\(frac)"
    }

    static func check(_ trace: LoadedTrace, _ spec: CaseSpec) -> Row {
        let name = "\(trace.file.traceId)/\(spec.id)"
        let tag = "[\(name)/all TR39 doze]"
        var normal = Runner(trace: trace, spec: spec, mode: "all", options: RunOptions(probes: false))
        normal.runAll()
        var doze = Runner(trace: trace, spec: spec, mode: "all", options: RunOptions(dozeModel: true))
        doze.runAll()
        var fails: [String] = []
        fails += (normal.configErrors + doze.configErrors).map { "\(tag) \($0)" }
        // (a) I1–I7, I10–I13 at every Step; I14, P08, P07 and finite state come from the runner.
        fails += (doze.violations + doze.os.violations + Checks.invariants(doze)).map { "\(tag) \($0)" }
        // (b) first gpsLost at the same atMs.
        let nl = firstLost(normal), dl = firstLost(doze)
        if nl?.atMs != dl?.atMs {
            fails.append("\(tag) (b) first gpsLost \(s3(dl?.atMs, doze.startMs)) s, normal run \(s3(nl?.atMs, normal.startMs)) s")
        }
        // (c), (d) first alarm: same reason, ringNow, within [tW − I, tW + wakeGuard + 1 ms]; never a fallback first.
        let na = firstAlarm(normal), da = firstAlarm(doze)
        let i = Int64(trace.file.intervalS)
        if let na, let da {
            let tW = Int64(na.t)
            let a = da.a
            let rel = a.atMs - doze.startMs
            if a.reason == .fallback || a.reason == .fallbackMissed {
                fails.append("\(tag) (d) first alarm is \(a.reason.jsonName) at \(s3(a.atMs, doze.startMs)) s")
            }
            if a.reason != na.a.reason { fails.append("\(tag) (c) first alarm \(a.reason.jsonName), normal run \(na.a.reason.jsonName)") }
            if !a.ringNow { fails.append("\(tag) (c) first alarm ringNow=false") }
            let lo = 1000 * (tW - i), hi = 1000 * tW + WakePlanner.wakeGuardMs + 1
            if rel < lo || rel > hi { fails.append("\(tag) (c) first alarm at \(rel) ms, window [\(lo), \(hi)]") }
        } else {
            fails.append("\(tag) (c) \(na == nil ? "normal run has no alarm" : "no alarm in the Doze model")")
        }
        let wakeTicks = doze.records.filter { rec in
            if case let .input(.tick(atMs), _) = rec.input { return (atMs - doze.startMs) % (1000 * i) != 0 }
            return false
        }.count
        let naCell = na.map { "\($0.t) \($0.a.reason.jsonName)" } ?? "-"
        let daCell = da.map { "\(s3($0.a.atMs, doze.startMs)) \($0.a.reason.jsonName) ringNow=\($0.a.ringNow)" } ?? "-"
        let md = "| \(name) | \(s3(nl?.atMs, normal.startMs)) | \(s3(dl?.atMs, doze.startMs)) | \(naCell) | \(daCell) | "
            + "\(wakeTicks) | \(fails.isEmpty ? "pass" : "FAIL") |\n"
        return Row(name: name, fails: fails, md: md)
    }

    @Test("TR39 Doze model on the gpsGaps cases alarms from the engine like the normal run")
    func tr39() async throws {
        var jobs: [(LoadedTrace, CaseSpec)] = []
        for ref in CaseCatalog.refs {
            let (trace, spec) = try CaseCatalog.load(ref)
            let c = spec.config
            guard !trace.file.gpsGaps.isEmpty, c.kill == nil, c.relaunch == nil, c.osDismissOffsetS == nil,
                  !spec.allowFallbackFirst, (spec.samplingModes ?? ["all", "policy"]).contains("all") else { continue }
            jobs.append((trace, spec))
        }
        #expect(jobs.count == 11, "TR39 case set changed: \(jobs.map { "\($0.0.file.traceId)/\($0.1.id)" })")
        let rows: [Row] = await withTaskGroup(of: Row.self) { g in
            for (t, s) in jobs { g.addTask { Self.check(t, s) } }
            var out: [Row] = []
            for await r in g { out.append(r) }
            return out.sorted { $0.name < $1.name }
        }
        var md = "## TR39 Doze model (T10.4 §7.3, mode all, no 9-minute Doze limit)\n\n"
        md += "| case | gpsLost normal (s) | gpsLost Doze (s) | first alarm normal (t) | first alarm Doze (s) | wake Ticks off grid | result |\n"
        md += "|---|---|---|---|---|---|---|\n"
        for r in rows { md += r.md }
        Report.shared.writePart(dir: "trace", name: "tr39", markdown: md + "\n", json: nil)
        var fails = rows.flatMap(\.fails)
        if fails.count > 40 { fails = Array(fails.prefix(40)) + ["… \(fails.count - 40) more"] }
        for f in fails { Issue.record(Comment(rawValue: f)) }
    }
}
