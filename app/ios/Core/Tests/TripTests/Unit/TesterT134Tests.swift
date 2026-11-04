import Foundation
import Testing
@testable import Trip

/// Tester T13.4 (T11.3, Swift): port of the Kotlin tester cases `unit/TesterT113Test.kt` on the TR40 fixture
/// `coach_gb_caugie_gappass` (the coach passes the destination inside a GPS gap): the event timeline around the gap, every policy
/// phase, the Doze model, a process kill inside the gap and the measured "alarm silenced inside the gap" case. The P05 part of the
/// Kotlin test is covered by `P05ManifestTests`. Reports `unit/t134-tr40-*.txt` (no coordinates), one file per Kotlin section of
/// `t113-tr40.txt`, same line format so each section can be compared byte for byte with Kotlin.
@Suite("TesterT134Tests")
struct TesterT134Tests {
    static let trace = "coach_gb_caugie_gappass"
    /// T10.5 round 3b (orchestrator 03/11): OVERSHOOT within [g.end, g.end + 25].
    static let windowS = 25
    static let cases = ["distance_1000", "time_15", "smart", "summary_unknown"]

    static func load(_ caseId: String) throws -> (LoadedTrace, CaseSpec) {
        let ref = try #require(CaseCatalog.refs.first { $0.traceId == trace && $0.caseId == caseId })
        return try CaseCatalog.load(ref)
    }

    /// (fromT, toT) of the single GPS gap, from the GPX itself (first sample after the gap is at toT). Kotlin `gap`.
    static func gap(_ t: LoadedTrace) -> (Int, Int) {
        let s = t.samples
        let i = s.indices.first { $0 > 0 && s[$0].t - s[$0 - 1].t > t.file.intervalS }!
        return (s[i - 1].t + t.file.intervalS, s[i].t)
    }

    static func desc(_ x: (t: Int, e: TripEvent)) -> String {
        if case let .alarm(a) = x.e { return "\(x.t) alarm \(a.reason.jsonName) ringNow=\(a.ringNow)" }
        return "\(x.t) \(x.e.fixtureName)"
    }

    static func alarms(_ r: Runner) -> [(t: Int, a: TripEvent.Alarm)] {
        Checks.flat(r).compactMap { x in if case let .alarm(a) = x.e { return (x.t, a) } else { return nil } }
    }

    static func timeline(_ r: Runner, _ gStart: Int, _ gEnd: Int) -> String {
        Checks.flat(r).filter { $0.t >= gStart - 60 && $0.t <= gEnd + 120 }.map(desc).joined(separator: "; ")
    }

    static func section(_ file: String, _ title: String, _ lines: [String]) {
        Report.shared.write("unit/t134-tr40-\(file).txt", "## \(title)\n" + lines.map { $0 + "\n" }.joined() + "\n")
    }

    static func opt<T>(_ x: T?) -> String { x.map { "\($0)" } ?? "null" }

    /// Kotlin `checkRun`: nothing rings before g.end, the first alarm rings at once and in the window; OVERSHOOT for DISTANCE and
    /// SMART, TIME for time_15 (U114 d); the overshoot event in the window; no TIMEOUT.
    static func checkRun(_ tag: String, _ r: Runner, _ gEnd: Int, overshootReason: Bool) -> [String] {
        var fails: [String] = []
        let al = alarms(r)
        guard let first = al.first else { return ["\(tag): no alarm"] }
        let from = gEnd
        let firstDesc = desc((first.t, .alarm(first.a)))
        let firstOv = al.first { $0.a.reason == .overshoot }
        let ov = Checks.flat(r).first { if case .overshoot = $0.e { return true } else { return false } }
        if first.t < from { fails.append("\(tag): first alarm before the GPS returned: \(firstDesc)") }
        if first.t > from + windowS { fails.append("\(tag): first alarm late: \(firstDesc) (window [\(from), \(from + windowS)])") }
        if !first.a.ringNow { fails.append("\(tag): first alarm ringNow=false") }
        if overshootReason && first.a.reason != .overshoot { fails.append("\(tag): first alarm \(firstDesc), want OVERSHOOT") }
        if overshootReason && (firstOv == nil || firstOv!.t > from + windowS) { fails.append("\(tag): alarm OVERSHOOT \(opt(firstOv?.t))") }
        if !overshootReason && first.a.reason != .time { fails.append("\(tag): first alarm \(firstDesc), want TIME (U114 d)") }
        if ov == nil || ov!.t < from || ov!.t > from + windowS { fails.append("\(tag): overshoot event at \(opt(ov?.t))") }
        if al.contains(where: { $0.a.reason == .timeout }) { fails.append("\(tag): TIMEOUT") }
        return fails
    }

    static func record(_ fails: [String]) {
        for f in fails.prefix(40) { Issue.record(Comment(rawValue: f)) }
    }

    @Test("T134 a (Kotlin T113) TR40 timeline per case and sampling mode: no alarm inside the gap, first alarm in g_end + 25")
    func timelinePerCase() throws {
        var lines: [String] = []
        var fails: [String] = []
        var gEndSeen = 0
        for caseId in Self.cases {
            let (t, spec) = try Self.load(caseId)
            let (gStart, gEnd) = Self.gap(t)
            if lines.isEmpty {
                lines.append("gap [\(gStart), \(gEnd)), arrival \(t.file.arrivalT), passed the destination "
                             + "\(gEnd - t.file.arrivalT) s before GPS returned")
            }
            gEndSeen = gEnd
            for m in CaseCatalog.modes(spec, interval: t.file.intervalS) {
                var r = Runner(trace: t, spec: spec, mode: m)
                r.runAll()
                fails += r.configErrors
                let probes = r.gapProbes.compactMap { p in
                    p.dChord.map { String(format: "u=%.3f dChord=%.1f", p.u!, $0) }
                }.joined(separator: ", ")
                lines.append("\(r.run): \(Self.timeline(r, gStart, gEnd)) | chord: \(probes)")
                fails += Self.checkRun(r.run, r, gEnd, overshootReason: caseId != "time_15")
                // Exact pin (Kotlin t113-tr40.txt): OVERSHOOT 2 990 for DISTANCE / SMART / summary, TIME 2 980 + overshoot 3 000.
                let first = Self.alarms(r).first
                let ov = Checks.flat(r).first { if case .overshoot = $0.e { return true } else { return false } }
                let want = caseId == "time_15" ? (gEnd, AlarmReason.time, gEnd + 20) : (gEnd + 10, AlarmReason.overshoot, gEnd + 10)
                if first?.t != want.0 || first?.a.reason != want.1 || ov?.t != want.2 {
                    fails.append("\(r.run): first alarm \(Self.opt(first?.t)) \(first?.a.reason.jsonName ?? "-"), overshoot "
                                 + "\(Self.opt(ov?.t)); Kotlin \(want.0) \(want.1.jsonName), overshoot \(want.2)")
                }
            }
        }
        #expect(gEndSeen == 2980, "g.end \(gEndSeen)")
        Self.section("timeline", "TR40 timeline (all, policy)", lines)
        Self.record(fails)
    }

    /// Out of spec: every phase of the SPARSE delivery grid (36), as TR30 does.
    @Test("T134 b (Kotlin T113) TR40 every policy phase (36) keeps the first alarm in g_end + 25")
    func policyPhaseSweep() async throws {
        var lines: [String] = []
        var fails: [String] = []
        for caseId in Self.cases {
            let (t, spec) = try Self.load(caseId)
            let (_, gEnd) = Self.gap(t)
            let sparse = EngineParamsFactory.parseOverrides(MiniJson.write(.object(spec.config.params))).params.samplingSparseIntervalS
            let k = sparse / t.file.intervalS
            #expect(k == 36)
            let modes = (0..<k).map { String(format: "policy-j%02d", $0) }
            let runs: [Runner] = await withTaskGroup(of: Runner.self) { g in
                for m in modes {
                    g.addTask {
                        var r = Runner(trace: t, spec: spec, mode: m, options: RunOptions(probes: false))
                        r.runAll()
                        return r
                    }
                }
                var out: [Runner] = []
                for await r in g { out.append(r) }
                return out.sorted { $0.j < $1.j }
            }
            lines.append("\(caseId): " + runs.map { r in
                let a = Self.alarms(r).first
                return "j\(r.j)=" + (a.map { "\($0.t)/\($0.a.reason.jsonName)" } ?? "-")
            }.joined(separator: ", "))
            for r in runs {
                fails += r.configErrors
                fails += Self.checkRun("\(t.file.traceId)/\(caseId)/\(r.mode)", r, gEnd, overshootReason: caseId != "time_15")
            }
        }
        Self.section("policy-sweep", "TR40 policy phase sweep", lines)
        Self.record(fails)
    }

    /// Out of spec: TR39 Doze model (no Tick inside the gap, only wakeAtMs) must not change the first alarm.
    @Test("T134 c (Kotlin T113) TR40 Doze model gives the same first alarm as the normal run")
    func dozeModel() throws {
        var lines: [String] = []
        var fails: [String] = []
        for caseId in Self.cases {
            let (t, spec) = try Self.load(caseId)
            let (gStart, gEnd) = Self.gap(t)
            var normal = Runner(trace: t, spec: spec, mode: "all", options: RunOptions(probes: false))
            normal.runAll()
            var doze = Runner(trace: t, spec: spec, mode: "all", options: RunOptions(probes: false, dozeModel: true))
            doze.runAll()
            let n = try #require(Self.alarms(normal).first)
            let d = Self.alarms(doze).first
            let nd = Self.desc((n.t, .alarm(n.a)))
            let dd = d.map { Self.desc(($0.t, .alarm($0.a))) }
            lines.append("\(caseId): normal \(nd), doze \(Self.opt(dd)), doze timeline \(Self.timeline(doze, gStart, gEnd))")
            if d == nil || d!.t != n.t || d!.a.reason != n.a.reason { fails.append("\(caseId): doze first alarm \(Self.opt(dd)) != normal \(nd)") }
            fails += Self.checkRun("\(t.file.traceId)/\(caseId)/doze", doze, gEnd, overshootReason: caseId != "time_15")
        }
        Self.section("doze", "TR40 Doze model", lines)
        Self.record(fails)
    }

    static func variant(_ s: CaseSpec, kill: At?, relaunch: (at: At, status: String)?, osRingMaxS: Int?,
                        dropExpect: Bool, dropForbidMatch: Bool) -> CaseSpec {
        let c = s.config
        let cfg = CaseConfig(mode: c.mode, thresholdM: c.thresholdM, thresholdMin: c.thresholdMin, preAlert: c.preAlert,
                             vehicleHint: c.vehicleHint, params: c.params, battery: c.battery, actions: c.actions,
                             kill: kill ?? c.kill, relaunch: kill == nil ? c.relaunch : relaunch,
                             osDismissOffsetS: c.osDismissOffsetS, osSim: c.osSim, osRingMaxS: osRingMaxS)
        return CaseSpec(id: s.id, testIds: s.testIds, config: cfg, samplingModes: s.samplingModes, policyPhaseSweep: s.policyPhaseSweep,
                        allowFallbackFirst: s.allowFallbackFirst, expect: dropExpect ? [] : s.expect,
                        expectAfter: kill != nil ? [] : s.expectAfter, expectFallback: s.expectFallback, killSweep: s.killSweep,
                        expectOutcome: s.expectOutcome, expectSummary: s.expectSummary, forbid: s.forbid,
                        forbidMatch: dropForbidMatch ? [] : s.forbidMatch, forbidAfter: s.forbidAfter)
    }

    /// Out of spec (restart mid-trip): the process dies 300 s into the gap; relaunch before / after the GPS returns, or never;
    /// (d)/(e) with an OS ring limit of 60 s. Asserted: the user is woken no later than g.end + 25 (here by the OS fallback while
    /// the process is dead), harness invariants hold, no TIMEOUT.
    @Test("T134 d (Kotlin T113) TR40 process killed inside the gap - relaunch before or after GPS returns, or never")
    func killInsideGap() throws {
        let (t, base) = try Self.load("distance_1000")
        let (gStart, gEnd) = Self.gap(t)
        let killT = gStart + 300
        let variants: [(String, Int?, Int?)] = [
            ("a relaunch g.end-60", gEnd - 60, nil),
            ("b relaunch g.end+30", gEnd + 30, nil),
            ("c no relaunch", nil, nil),
            ("d relaunch g.end+30, osRingMaxS 60", gEnd + 30, 60),
            ("e relaunch g.end-60, osRingMaxS 60", gEnd - 60, 60),
        ]
        var lines: [String] = []
        var fails: [String] = []
        for (name, relaunchT, ringMaxS) in variants {
            let m = Self.variant(base, kill: At(t: killT, anchor: nil, offsetS: 0),
                                 relaunch: relaunchT.map { (At(t: $0, anchor: nil, offsetS: 0), "auto") }, osRingMaxS: ringMaxS,
                                 dropExpect: true, dropForbidMatch: false)
            for mode in CaseCatalog.modes(m, interval: t.file.intervalS) {
                var r = Runner(trace: t, spec: m, mode: mode, options: RunOptions(probes: false))
                r.runAll()
                fails += Checks.run(r).map { "\(name) \(mode): \($0)" }
                let fb = r.os.osFallbackFiredT
                let after = Checks.flat(r).filter { x in
                    guard x.t >= gEnd else { return false }
                    switch x.e { case .alarm, .overshoot: return true; default: return false }
                }.map(Self.desc).joined(separator: "; ")
                lines.append("\(name) \(mode): OS fallback fired at \(Self.opt(fb)) (+\(Self.opt(fb.map { $0 - t.file.arrivalT })) s after "
                             + "passing the destination, \(Self.opt(fb.map { gEnd - $0 })) s before GPS returned); engine alarms/overshoot "
                             + "from g.end: [\(after)]; timeline \(Self.timeline(r, gStart, gEnd + 60))")
                if fb == nil || fb! > gEnd + Self.windowS { fails.append("\(name) \(mode): OS fallback at \(Self.opt(fb)), after g.end + 25") }
                if Self.alarms(r).contains(where: { $0.a.reason == .timeout }) { fails.append("\(name) \(mode): TIMEOUT") }
            }
        }
        Self.section("kill", "TR40 kill inside the gap (kill at \(killT))", lines)
        Self.record(fails)
    }

    /// Out of spec, measured (RK24, open until T13.5): an alarm already rang inside the gap (GPS_LOST forced early with
    /// gpsLostAlarmEtaS 3600) and stopped by itself (osRingMaxS 60) before the coach passed the destination. Asserted only: the
    /// GPS_LOST alarm rang inside the gap. What happens after g.end is logged.
    @Test("T134 e (Kotlin T113) TR40 measured - alarm silenced inside the gap, then the coach passes the destination")
    func silencedInsideGap() throws {
        var lines: [String] = []
        var fails: [String] = []
        var title = ""
        for caseId in ["distance_1000", "time_15", "smart"] {
            let (t, base) = try Self.load(caseId)
            let (gStart, gEnd) = Self.gap(t)
            title = "TR40 measured: alarm silenced in the gap (gpsLostAlarmEtaS 3600, osRingMaxS 60), arrival \(t.file.arrivalT), g.end \(gEnd)"
            let m = Self.variant(base, kill: nil, relaunch: nil, osRingMaxS: 60, dropExpect: true, dropForbidMatch: true)
            let opts = RunOptions(paramOverrides: [("gpsLostAlarmEtaS", .number("3600"))], probes: false)
            for mode in CaseCatalog.modes(m, interval: t.file.intervalS) {
                var r = Runner(trace: t, spec: m, mode: mode, options: opts)
                r.runAll()
                fails += r.configErrors
                let first = Self.alarms(r).first
                let silencedT = r.records.first { rec in
                    if case let .input(x, _) = rec.input, case .alarmSilenced = x { return true } else { return false }
                }?.t
                let afterGap = Checks.flat(r).filter { x in
                    guard x.t >= gEnd else { return false }
                    switch x.e { case .alarm, .overshoot: return true; default: return false }
                }.map(Self.desc).joined(separator: "; ")
                let fd = first.map { Self.desc(($0.t, .alarm($0.a))) }
                lines.append("\(caseId) \(mode): first \(Self.opt(fd)); AlarmSilenced input at \(Self.opt(silencedT)); from g.end: [\(afterGap)]")
                if first == nil || first!.t >= gEnd || first!.t < gStart { fails.append("\(caseId) \(mode): first alarm not in the gap: \(Self.opt(fd))") }
            }
        }
        Self.section("silenced", title, lines)
        Self.record(fails)
    }
}
