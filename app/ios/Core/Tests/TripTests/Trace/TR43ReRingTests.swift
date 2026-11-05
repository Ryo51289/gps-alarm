import Foundation
import Testing
@testable import Trip

/// `t107-tr43.txt` lines by "variant case mode" (parallel tests; written sorted by key under the lock, deterministic).
final class TR43Log: @unchecked Sendable {
    static let shared = TR43Log()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func note(_ key: String, _ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines[key] = line
        Report.shared.write("unit/t107-tr43.txt", lines.keys.sorted().map { lines[$0]! }.joined(separator: "\n") + "\n")
    }
}

/// TR43 (T10 mục cuối "T10.7" §9.2, RK24; Kotlin `TR43ReRingTest.kt`): re-ring OVERSHOOT after an alarm that rang inside the
/// GPS gap of TR40 (`coach_gb_caugie_gappass`, gap [2 020, 2 980)), the vehicle passing the destination in the gap. Cases
/// distance_1000, time_15, smart, `all` + `policy`; the case expectations are replaced by the checks below (forbidMatch TIMEOUT
/// kept); every per-run harness check (I1–I7, I10–I12, P07, finite state) must hold. Not in the P05 manifest. Report
/// `t107-tr43.txt` (no coordinates), byte-identical to Kotlin. (f) is the deterministic gate of T12 "T12.4 — Trả lời designer".
@Suite("TR43ReRingTests")
struct TR43ReRingTests {
    static let traceId = "coach_gb_caugie_gappass"
    static let cases = ["distance_1000", "time_15", "smart"]
    /// T10.7 round 2 (C31): the re-ring waits for dSmooth − minD (observed) >= 1 000, window 60 s; (g2) keeps 25 s.
    static let windowS = 60
    static let g2WindowS = 25
    /// `all` re-ring time of (a)–(e) (by hand 3 030) and (f) (measured 3 060), T10 "T10.7 vòng 2" §4.
    static let reRingT = 3_030
    static let reRingFT = 3_060
    static let killT = 2_320
    static let lost3600: [(String, JsonValue)] = [("gpsLostAlarmEtaS", .number("3600"))]

    struct TimedEvent {
        let t: Int
        let rec: Int
        let e: TripEvent
    }

    struct Run: Sendable {
        let caseId: String
        let r: Runner

        var mode: String { r.mode }
        var isPolicy: Bool { r.isPolicy }
        var tag: String { "\(caseId)/\(mode)" }

        var evs: [TimedEvent] {
            var out: [TimedEvent] = []
            for (i, rec) in r.records.enumerated() { for e in rec.events { out.append(TimedEvent(t: rec.t, rec: i, e: e)) } }
            return out
        }

        var alarms: [TimedEvent] { evs.filter { if case .alarm = $0.e { true } else { false } } }
        var overshoot: TimedEvent? { evs.first { if case .overshoot = $0.e { true } else { false } } }

        func silenced(_ pred: (Int) -> Bool) -> Bool {
            r.records.contains { rec in
                if case .input(.alarmSilenced, _) = rec.input { return pred(rec.t) } else { return false }
            }
        }

        func phaseAt(_ e: TimedEvent?) -> TripPhase? { e.map { r.records[$0.rec].view.phase } }
    }

    static func trace() throws -> LoadedTrace { try #require(LoadedTrace.named(traceId), "trace \(traceId) not loaded") }

    static var gStart: Int { (LoadedTrace.named(traceId)?.file.gpsGaps.first?.fromT) ?? -1 }
    static var gEnd: Int { (LoadedTrace.named(traceId)?.file.gpsGaps.first?.toT) ?? -1 }

    /// The fixture case `caseId` with `config` overridden (Kotlin `copy`): osRingMaxS, kill, relaunch (`auto`), extra actions;
    /// expect / expectAfter removed.
    static func model(_ caseId: String, ringMaxS: Int? = nil, kill: Int? = nil, relaunch: Int? = nil,
                      actions: [(at: At, action: String)] = []) throws -> CaseSpec {
        let ref = try #require(CaseCatalog.refs.first { $0.traceId == traceId && $0.caseId == caseId }, "case \(caseId)")
        let (_, b) = try CaseCatalog.load(ref)
        let c = b.config
        let config = CaseConfig(mode: c.mode, thresholdM: c.thresholdM, thresholdMin: c.thresholdMin, preAlert: c.preAlert,
                                vehicleHint: c.vehicleHint, params: c.params, battery: c.battery, actions: c.actions + actions,
                                kill: kill.map { At(t: $0, anchor: nil, offsetS: 0) },
                                relaunch: relaunch.map { (at: At(t: $0, anchor: nil, offsetS: 0), status: "auto") },
                                osDismissOffsetS: c.osDismissOffsetS, osSim: c.osSim, osRingMaxS: ringMaxS)
        return CaseSpec(id: b.id, testIds: b.testIds, config: config, samplingModes: b.samplingModes, policyPhaseSweep: b.policyPhaseSweep,
                        allowFallbackFirst: b.allowFallbackFirst, expect: [], expectAfter: [], expectFallback: b.expectFallback,
                        killSweep: b.killSweep, expectOutcome: b.expectOutcome, expectSummary: b.expectSummary, forbid: b.forbid,
                        forbidMatch: b.forbidMatch, forbidAfter: b.forbidAfter)
    }

    /// TR43 (g)/(g2): the vehicle stops at the first fix after the gap — every sample with t ≥ `tS` gets the position of the
    /// sample at `tS`, speed 0, accuracy kept. In memory only.
    static func parkedAfter(_ tr: LoadedTrace, _ tS: Int) throws -> LoadedTrace {
        let at = try #require(tr.samples.first { $0.t == tS })
        let samples = tr.samples.map { s in
            s.t < tS ? s : TraceSample(index: s.index, t: s.t, lat: at.lat, lng: at.lng, accuracyM: s.accuracyM, speedMps: 0.0)
        }
        return LoadedTrace(file: tr.file, samples: samples, byTick: tr.byTick)
    }

    static func desc(_ e: TimedEvent) -> String {
        switch e.e {
        case let .alarm(a): "\(e.t) alarm \(a.reason.jsonName) ringNow=\(a.ringNow)"
        case let .fallbackAlarmChanged(f): "\(e.t) fallbackAlarmChanged \(f.fallbackAtMs == nil ? "null" : "set") \(f.cause.jsonName)"
        default: "\(e.t) \(e.e.fixtureName)"
        }
    }

    /// Events and the KILL / RESTORE / AlarmSilenced / UserAction markers in [g.start − 60, g.end + 120].
    static func timeline(_ r: Runner) -> String {
        var out: [String] = []
        for (i, rec) in r.records.enumerated() {
            if rec.t < gStart - 60 || rec.t > gEnd + 120 { continue }
            switch rec.input {
            case .kill: out.append("\(rec.t) KILL")
            case let .restore(_, status, _, _): out.append("\(rec.t) RESTORE \(status.jsonName)")
            case .input(.alarmSilenced, _): out.append("\(rec.t) in:alarmSilenced")
            case let .input(.userAction(_, k), _): out.append("\(rec.t) in:\(k.jsonName)")
            default: break
            }
            for e in rec.events { out.append(desc(TimedEvent(t: rec.t, rec: i, e: e))) }
        }
        return out.joined(separator: "; ")
    }

    static func note(_ variant: String, _ x: Run, _ extra: String = "") {
        TR43Log.shared.note("\(variant) \(x.caseId) \(x.mode)", "(\(variant)) \(x.caseId) \(x.mode): \(timeline(x.r))\(extra)")
    }

    /// Every sampling mode of the 3 cases under `m`, run in parallel, sorted by case then mode (notes written unless `noteIt` false).
    static func runs(_ variant: String, _ m: (String) throws -> CaseSpec, tr: LoadedTrace? = nil,
                     options: RunOptions = RunOptions(probes: false), noteIt: Bool = true) async throws -> [Run] {
        let trace = try tr ?? Self.trace()
        var jobs: [(String, CaseSpec, String)] = []
        for c in cases {
            let spec = try m(c)
            for mode in CaseCatalog.modes(spec, interval: trace.file.intervalS) { jobs.append((c, spec, mode)) }
        }
        let out: [Run] = await withTaskGroup(of: Run.self) { g in
            for (c, spec, mode) in jobs {
                g.addTask {
                    var r = Runner(trace: trace, spec: spec, mode: mode, options: options)
                    r.runAll()
                    return Run(caseId: c, r: r)
                }
            }
            var res: [Run] = []
            for await x in g { res.append(x) }
            return res
        }
        let sorted = out.sorted { $0.caseId != $1.caseId ? $0.caseId < $1.caseId : $0.mode < $1.mode }
        if noteIt { for x in sorted { note(variant, x) } }
        return sorted
    }

    static func inWindow(_ t: Int?, from: Int = TR43ReRingTests.gEnd) -> Bool { t != nil && t! >= from && t! <= from + windowS }

    /// Harness checks of the run (forbidMatch TIMEOUT, I1–I7, I10–I12, P07, finite state) under its case model.
    static func harness(_ x: Run) -> [String] { Checks.run(x.r).map { "\(x.tag): \($0)" } }

    static func alarm(_ e: TimedEvent?) -> TripEvent.Alarm? {
        guard let e, case let .alarm(a) = e.e else { return nil }
        return a
    }

    /// The re-ring: exactly one Alarm from `from`, OVERSHOOT ringNow=true in the window, with the Overshoot in the same Step.
    static func reRing(_ x: Run, from: Int = TR43ReRingTests.gEnd) -> [String] {
        var f: [String] = []
        let after = x.alarms.filter { $0.t >= from }
        let ov = x.overshoot
        if after.count != 1 { f.append("\(x.tag): \(after.count) alarms from \(from): \(KW.klist(after.map(desc)))") }
        let a = after.first
        if let al = alarm(a), al.reason == .overshoot, al.ringNow, inWindow(a?.t, from: from) {} else {
            f.append("\(x.tag): re-ring \(a.map(desc) ?? "null"), want alarm OVERSHOOT ringNow=true in [\(from), \(from + windowS)]")
        }
        if ov == nil || a == nil || ov!.rec != a!.rec {
            f.append("\(x.tag): overshoot \(ov.map { String($0.t) } ?? "null") not in the Step of the re-ring \(a.map { String($0.t) } ?? "null")")
        }
        return f
    }

    static func report(_ fails: [String]) {
        var list = fails
        if list.count > 40 { list = Array(list.prefix(40)) + ["… \(fails.count - 40) more"] }
        for f in list { Issue.record(Comment(rawValue: f)) }
    }

    @Test("TR43 a b c alarm rang in the gap - chime stopped re-rings OVERSHOOT, still ringing gives Overshoot only, snoozed supersedes")
    func tr43abc() async throws {
        let gStart = Self.gStart, gEnd = Self.gEnd
        #expect(gStart == 2_020 && gEnd == 2_980, "TR40 gap [\(gStart), \(gEnd))")
        var fails: [String] = []
        let lost = RunOptions(paramOverrides: Self.lost3600, probes: false)
        // (a) GPS_LOST forced inside the gap, the chime stops after 60 s.
        for x in try await Self.runs("a", { try Self.model($0, ringMaxS: 60) }, options: lost) {
            fails += Self.harness(x)
            let first = x.alarms.first
            let fa = Self.alarm(first)
            if fa?.reason != .gpsLost || first!.t <= gStart || first!.t >= gEnd {
                fails.append("\(x.tag) (a): first alarm \(first.map(Self.desc) ?? "null"), want GPS_LOST inside the gap")
            }
            if !x.silenced({ $0 < gEnd }) { fails.append("\(x.tag) (a): no AlarmSilenced before g.end") }
            fails += Self.reRing(x).map { "(a) \($0)" }
            if x.phaseAt(x.overshoot) != .overshot {
                fails.append("\(x.tag) (a): phase \(x.phaseAt(x.overshoot)?.jsonName ?? "null") at the overshoot")
            }
            if !x.isPolicy && (first?.t != 2_105 || x.overshoot?.t != Self.reRingT) {
                fails.append("\(x.tag) (a): by hand GPS_LOST 2105, OVERSHOOT \(Self.reRingT); got \(first.map { String($0.t) } ?? "null"), "
                             + "\(x.overshoot.map { String($0.t) } ?? "null")")
            }
        }
        // (b) the chime still rings: Overshoot only (screen 8), no Alarm after GPS_LOST.
        for x in try await Self.runs("b", { try Self.model($0) }, options: lost) {
            fails += Self.harness(x)
            let ov = x.overshoot
            if !Self.inWindow(ov?.t) { fails.append("\(x.tag) (b): overshoot at \(ov.map { String($0.t) } ?? "null")") }
            if x.alarms.count != 1 || Self.alarm(x.alarms.first)?.reason != .gpsLost {
                fails.append("\(x.tag) (b): alarms \(KW.klist(x.alarms.map(Self.desc))), want GPS_LOST only")
            }
            if let ov, !x.r.records[ov.rec].view.alarmRinging { fails.append("\(x.tag) (b): alarmRinging false at the overshoot") }
            if !x.isPolicy && ov?.t != Self.reRingT { fails.append("\(x.tag) (b): by hand \(Self.reRingT), got \(ov.map { String($0.t) } ?? "null")") }
        }
        // (c) as (a), snoozed at 2 990 (until 3 050; T10.7 round 2): the re-ring supersedes the snooze before it ends.
        let snooze: [(at: At, action: String)] = [(at: At(t: 2_990, anchor: nil, offsetS: 0), action: "snooze")]
        for x in try await Self.runs("c", { try Self.model($0, ringMaxS: 60, actions: snooze) }, options: lost) {
            fails += Self.harness(x)
            if !x.evs.contains(where: { e in if case .snoozed = e.e { return e.t == 2_990 } else { return false } }) {
                fails.append("\(x.tag) (c): no snoozed at 2990")
            }
            fails += Self.reRing(x).map { "(c) \($0)" }
            let a = x.alarms.last
            let sup = x.evs.first { e in
                if case let .fallbackAlarmChanged(f) = e.e { return e.rec == a?.rec && f.cause == .superseded } else { return false }
            }
            var supNull = false
            if let sup, case let .fallbackAlarmChanged(f) = sup.e { supNull = f.fallbackAtMs == nil }
            if a == nil || sup == nil || !supNull {
                fails.append("\(x.tag) (c): fallbackAlarmChanged(null, SUPERSEDED) \(sup.map(Self.desc) ?? "null") not in the Step of the "
                             + "re-ring \(a.map { String($0.t) } ?? "null")")
            }
            if a == nil || a!.t >= 3_050 { fails.append("\(x.tag) (c): re-ring at \(a.map { String($0.t) } ?? "null"), want before snoozeUntil 3050") }
            if x.alarms.contains(where: { Self.alarm($0)?.reason == .snoozeEnd }) { fails.append("\(x.tag) (c): SNOOZE_END") }
            if !x.isPolicy && x.overshoot?.t != Self.reRingT {
                fails.append("\(x.tag) (c): by hand \(Self.reRingT), got \(x.overshoot.map { String($0.t) } ?? "null")")
            }
        }
        Self.report(fails)
    }

    @Test("TR43 d e f process killed in the gap, relaunch before or after the GPS returns")
    func tr43def() async throws {
        let gEnd = Self.gEnd
        var fails: [String] = []
        // (d) relaunch at 2 920 (GPS back at 2 980), the OS chime stops after 60 s: re-ring (= TesterT113Test e).
        for x in try await Self.runs("d", { try Self.model($0, ringMaxS: 60, kill: Self.killT, relaunch: 2_920) }) {
            fails += Self.harness(x)
            let fb = x.r.os.osFallbackFiredT
            if fb == nil || fb! > gEnd { fails.append("\(x.tag) (d): OS fallback at \(fb.map(String.init) ?? "null"), want <= g.end") }
            let ra = x.alarms.first { $0.t == 2_920 }
            if let a = Self.alarm(ra), a.reason == .fallback, !a.ringNow {} else {
                fails.append("\(x.tag) (d): at relaunch \(ra.map(Self.desc) ?? "null"), want alarm FALLBACK ringNow=false")
            }
            if !x.silenced({ $0 >= 2_920 }) { fails.append("\(x.tag) (d): no AlarmSilenced after relaunch") }
            fails += Self.reRing(x).map { "(d) \($0)" }
            if !x.isPolicy && x.overshoot?.t != Self.reRingT {
                fails.append("\(x.tag) (d): by hand \(Self.reRingT), got \(x.overshoot.map { String($0.t) } ?? "null")")
            }
        }
        // (e) as (d), the OS chime still rings (= TesterT113Test a): Overshoot only.
        for x in try await Self.runs("e", { try Self.model($0, kill: Self.killT, relaunch: 2_920) }) {
            fails += Self.harness(x)
            if !Self.inWindow(x.overshoot?.t) { fails.append("\(x.tag) (e): overshoot at \(x.overshoot.map { String($0.t) } ?? "null")") }
            let rang = x.alarms.filter { $0.t >= 2_920 && Self.alarm($0)?.ringNow == true }
            if !rang.isEmpty { fails.append("\(x.tag) (e): \(KW.klist(rang.map(Self.desc))) after relaunch") }
            if !x.isPolicy && x.overshoot?.t != Self.reRingT {
                fails.append("\(x.tag) (e): by hand \(Self.reRingT), got \(x.overshoot.map { String($0.t) } ?? "null")")
            }
        }
        // (f) relaunch at 3 010 (after the GPS came back), the OS chime stopped while the engine was dead (= TesterT113Test d).
        // Deterministic gate (T10 "T10.7" §9.2 (f), T12 "T12.4 — Trả lời designer" §1): (f-i) the harness relaunch sends
        // AlarmSilenced (the OS chime rang <= g.end and stopped 60 s later, before the relaunch) with Alarm(FALLBACK, ringNow=false);
        // (f-ii) the first accepted fix after the relaunch is a chord fix in ALARMING with dChord < nearRadius (1 000);
        // (f-iii) exactly one Alarm(ringNow=true) from the relaunch: OVERSHOOT, in the Step of the only overshoot, in the window.
        let relF = 3_010
        let f = try await Self.runs("f", { try Self.model($0, ringMaxS: 60, kill: Self.killT, relaunch: relF) },
                                    options: RunOptions(probes: true), noteIt: false)
        for x in f {
            fails += Self.harness(x)
            let startMs = x.r.startMs
            var g: GapProbe? = nil
            for p in x.r.gapProbes where p.atMs - startMs >= Int64(relF) * 1000 {
                if let cur = g, cur.atMs <= p.atMs { continue }
                g = p
            }
            let chord = g?.dChord
            let silencedAtRelaunch = x.silenced { $0 == relF }
            let probe = " | first fix after relaunch: t=\(g.map { String(($0.atMs - startMs) / 1000) } ?? "null") "
                + "gapFix=\(g.map { String($0.gapFix) } ?? "null") phase=\(g?.phase.jsonName ?? "null") "
                + "u=\(g?.u.map { KW.jf($0, 4) } ?? "null") dChord=\(chord.map { KW.jf($0, 1) } ?? "null"); "
                + "AlarmSilenced at relaunch=\(silencedAtRelaunch)"
            Self.note("f", x, probe)
            // (f-i)
            let ra = x.alarms.first { $0.t == relF }
            if let a = Self.alarm(ra), a.reason == .fallback, !a.ringNow {} else {
                fails.append("\(x.tag) (f): at relaunch \(ra.map(Self.desc) ?? "null"), want alarm FALLBACK ringNow=false")
            }
            if !silencedAtRelaunch { fails.append("\(x.tag) (f): harness precondition: no AlarmSilenced at relaunch") }
            // (f-ii)
            if g == nil || g!.gapFix != true || g!.phase != .alarming || chord == nil || chord! >= 1_000.0 {
                fails.append("\(x.tag) (f): first fix after relaunch is not a chord fix in ALARMING with dChord < 1000:\(probe)")
            }
            // (f-iii)
            let ov = x.overshoot
            let overshoots = x.evs.filter { if case .overshoot = $0.e { true } else { false } }
            if overshoots.count != 1 || !Self.inWindow(ov?.t, from: relF) {
                fails.append("\(x.tag) (f): \(overshoots.count) overshoot(s), first at \(ov.map { String($0.t) } ?? "null"), "
                             + "window [\(relF), \(relF + Self.windowS)]")
            }
            let rang = x.alarms.filter { $0.t >= relF && Self.alarm($0)?.ringNow == true }
            if rang.count != 1 || Self.alarm(rang.first)?.reason != .overshoot || rang.first?.rec != ov?.rec {
                fails.append("\(x.tag) (f): after relaunch \(KW.klist(rang.map(Self.desc))), want one alarm OVERSHOOT ringNow=true with the "
                             + "overshoot \(ov.map { String($0.t) } ?? "null")")
            }
            if x.phaseAt(ov) != .overshot { fails.append("\(x.tag) (f): phase \(x.phaseAt(ov)?.jsonName ?? "null") at the overshoot") }
            if !x.isPolicy && ov?.t != Self.reRingFT { fails.append("\(x.tag) (f): measured \(Self.reRingFT), got \(ov.map { String($0.t) } ?? "null")") }
        }
        Self.report(fails)
    }

    @Test("TR43 g g2 parked beyond the destination after the gap - no re-ring once the chime stopped, OVERSHOOT before any alarm")
    func tr43g() async throws {
        let gEnd = Self.gEnd
        var fails: [String] = []
        let trace = try Self.trace()
        let parked = try Self.parkedAfter(trace, gEnd)
        #expect(trace.samples.map(\.t) == parked.samples.map(\.t))
        // (g) as (a) on the parked trace: nothing after g.end until the end of the trace (alarmMaxActiveS not reached).
        let lostProbes = RunOptions(paramOverrides: Self.lost3600, probes: true)
        for x in try await Self.runs("g", { try Self.model($0, ringMaxS: 60) }, tr: parked, options: lostProbes) {
            fails += Self.harness(x)
            // Not vacuous (review T12.4 nit #2, T13.5 #1): the first fix after the gap is a chord fix in ALARMING with dChord < nearRadius.
            let chordAtEnd = x.r.gapProbes.first { $0.atMs - x.r.startMs == Int64(gEnd) * 1000 }
            if chordAtEnd == nil || chordAtEnd!.phase != .alarming || (chordAtEnd!.dChord ?? .greatestFiniteMagnitude) >= 1_000.0 {
                fails.append("\(x.tag) (g): no ALARMING chord fix < 1000 m at g.end (phase=\(chordAtEnd?.phase.jsonName ?? "null") "
                             + "dChord=\(KW.kdOpt(chordAtEnd?.dChord)))")
            }
            let first = x.alarms.first
            if Self.alarm(first)?.reason != .gpsLost || first!.t >= gEnd {
                fails.append("\(x.tag) (g): first alarm \(first.map(Self.desc) ?? "null"), want GPS_LOST in the gap")
            }
            let after = x.evs.filter { e in
                guard e.t >= gEnd else { return false }
                switch e.e { case .alarm, .overshoot: return true; default: return false }
            }
            if !after.isEmpty { fails.append("\(x.tag) (g): \(KW.klist(after.map(Self.desc))) after g.end") }
            if x.evs.contains(where: { if case .tripEnded = $0.e { true } else { false } }) {
                fails.append("\(x.tag) (g): trip ended before the end of the trace")
            }
        }
        // (g2) control, default params (no alarm before the gap): the round-3b/3c standing term rings OVERSHOOT; TIME rings TIME.
        for x in try await Self.runs("g2", { try Self.model($0) }, tr: parked) {
            fails += Self.harness(x)
            if x.caseId == "time_15" { continue }   // printed only (T10.7 §9.2)
            let first = x.alarms.first
            if let a = Self.alarm(first), a.reason == .overshoot, a.ringNow, let ft = first?.t, ft >= gEnd, ft <= gEnd + Self.g2WindowS {} else {
                fails.append("\(x.tag) (g2): first alarm \(first.map(Self.desc) ?? "null"), want OVERSHOOT ringNow=true in the window")
            }
            if first == nil || x.overshoot?.rec != first!.rec {
                fails.append("\(x.tag) (g2): overshoot \(x.overshoot.map { String($0.t) } ?? "null") not with the alarm "
                             + "\(first.map { String($0.t) } ?? "null")")
            }
            if !x.isPolicy && first?.t != 2_985 { fails.append("\(x.tag) (g2): by hand 2985, got \(first.map { String($0.t) } ?? "null")") }
        }
        Self.report(fails)
    }
}
