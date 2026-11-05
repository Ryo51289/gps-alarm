import Foundation
import Testing
@testable import Trip

/// `u128-loop.txt` lines by run tag (parallel runs; written sorted by tag under the lock, deterministic).
final class U128Log: @unchecked Sendable {
    static let shared = U128Log()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func note(_ key: String, _ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines[key] = line
        Report.shared.write("unit/u128-loop.txt", lines.keys.sorted().map { lines[$0]! }.joined(separator: "\n") + "\n")
    }
}

/// U128 (T10 "T10.7 vòng 2" §7, C31, RK20 e; Kotlin `unit/T107LoopTest.kt`): loop routes (`LoopRoutes`, the tester's T12.4
/// geometry) with an alarm before / in the GPS gap that hides the loop; the chord passes through the destination while the road
/// stays ≥ 3 km away. TR40 case models `distance_1000` (GPS_LOST in the gap) and `time_15` (TIME before the gap) × `all`/`policy`
/// × chime {osRingMaxS 60, unlimited}. Gates: L2, L3, L4 (every seed, a = 5 and 14), L4n, L5: no Overshoot before the vehicle
/// really passed the destination; L3, L4, L4n, L5: an Overshoot in [arrival, arrival + 120 s], with Alarm(OVERSHOOT, ringNow=true)
/// in its Step when the chime stopped; L1 (accepted RK20 e): exactly one wrong-wording Overshoot, at the first Step whose dSmooth
/// (= d(t − 5)) is 1 km beyond minD (3 000 m); every run 0 harness violations. Report `u128-loop.txt` (t, distances, u, phase; no
/// coordinates), byte-identical to Kotlin.
@Suite("T107LoopTests")
struct T107LoopTests {
    static let cases = ["distance_1000", "time_15"]
    static let afterArrivalS = 120
    static let noiseSeed: Int64 = 124

    struct Run: Sendable {
        let tag: String
        let ring: Int?
        let r: Runner

        var evs: [TR43ReRingTests.TimedEvent] {
            var out: [TR43ReRingTests.TimedEvent] = []
            for (i, rec) in r.records.enumerated() { for e in rec.events { out.append(.init(t: rec.t, rec: i, e: e)) } }
            return out
        }
    }

    static func desc(_ e: TR43ReRingTests.TimedEvent) -> String {
        switch e.e {
        case let .alarm(a): "\(e.t) alarm \(a.reason.jsonName) ringNow=\(a.ringNow)"
        case let .overshoot(o): "\(e.t) overshoot pastM=\(o.pastM)"
        default: "\(e.t) \(e.e.fixtureName)"
        }
    }

    static func isAlarm(_ e: TR43ReRingTests.TimedEvent) -> Bool { if case .alarm = e.e { true } else { false } }

    /// Checks of one run; `kind`: "none" (no early Overshoot, an Overshoot after arrival), "noEarly" (L2), "l1".
    static func check(_ s: LoopRoutes.Synth, _ x: Run, _ kind: String) -> [String] {
        var f = Checks.run(x.r).map { "\(x.tag): \($0)" }
        let gEnd = s.gap.toT
        let evs = x.evs
        let first = evs.first(where: isAlarm)
        if first == nil || first!.t >= gEnd { f.append("\(x.tag): precondition: no alarm before g.end (\(first.map(desc) ?? "null"))") }
        let g = x.r.gapProbes.first { $0.atMs - x.r.startMs == Int64(gEnd) * 1000 }
        if g == nil || !g!.gapFix || g!.phase != .alarming || (g!.dChord ?? .greatestFiniteMagnitude) >= 1_000.0 {
            f.append("\(x.tag): precondition: fix at g.end gapFix=\(g.map { String($0.gapFix) } ?? "null") "
                     + "phase=\(g?.phase.jsonName ?? "null") dChord=\(KW.kdOpt(g?.dChord))")
        }
        let ovs = evs.filter { if case .overshoot = $0.e { true } else { false } }
        let ov = ovs.first
        let early = ov != nil && !s.passed(ov!.t)
        let arrival = s.arrivalS
        switch kind {
        case "l1":
            // RK20 (e) accepted: exactly one wrong-wording Overshoot, when the vehicle really went 1 km farther than minD.
            if ov == nil || !early || ovs.count != 1 {
                f.append("\(x.tag): L1 want one wrong-wording Overshoot (RK20 e accepted), got \(KW.klist(ovs.map(desc)))")
            }
            if let ov, !(s.trueD(ov.t - 5) >= 4_000.0 && s.trueD(ov.t - 10) < 4_000.0) {
                f.append("\(x.tag): L1 Overshoot at \(ov.t) not the first Step with d(t − 5) >= 4 000 (d \(KW.ki(s.trueD(ov.t - 5))))")
            }
        default:
            if early { f.append("\(x.tag): Overshoot at \(ov!.t) before the vehicle passed the destination (arrival \(KW.jf(arrival, 0)))") }
            if kind == "none" {
                if ov == nil || Double(ov!.t) < arrival || Double(ov!.t) > arrival + Double(afterArrivalS) {
                    f.append("\(x.tag): Overshoot \(ov.map { String($0.t) } ?? "null") not in [arrival, arrival + \(afterArrivalS)] "
                             + "(arrival \(KW.jf(arrival, 0)))")
                }
                let reRing = ov != nil && evs.contains { e in
                    if e.rec == ov!.rec, case let .alarm(a) = e.e { return a.reason == .overshoot && a.ringNow } else { return false }
                }
                if x.ring != nil, let ov, !reRing {
                    f.append("\(x.tag): chime stopped but no Alarm(OVERSHOOT, ringNow=true) with the Overshoot at \(ov.t)")
                }
            }
        }
        let withAlarm = ov.flatMap { o in evs.first { $0.rec == o.rec && isAlarm($0) } }.map { " + \(desc($0))" } ?? ""
        let line = "\(x.tag): first \(first.map(desc) ?? "null"); g.end \(gEnd) chord u=\(g?.u.map { KW.jf($0, 4) } ?? "null") "
            + "dChord=\(g?.dChord.map { KW.jf($0, 1) } ?? "null") phase=\(g?.phase.jsonName ?? "null") d_f=\(KW.jf(g?.dFixM ?? .nan, 0)); "
            + "arrival \(KW.jf(arrival, 0)); overshoot \(ov.map(desc) ?? "none") (\(ov == nil ? "-" : early ? "NOT PASSED" : "passed"), "
            + "trueD \(ov.map { KW.jf(s.trueD($0.t), 0) } ?? "-"))\(withAlarm)"
        U128Log.shared.note(x.tag, line)
        return f
    }

    static func runOne(_ s: LoopRoutes.Synth, _ tag: String, _ spec: CaseSpec, _ ring: Int?, _ mode: String) -> Run {
        var r = Runner(trace: s.trace, spec: spec, mode: mode, options: RunOptions(probes: true))
        r.runAll()
        return Run(tag: tag, ring: ring, r: r)
    }

    static func runAll(_ s: LoopRoutes.Synth) async throws -> [Run] {
        var jobs: [(String, CaseSpec, Int?, String)] = []
        for ring in [Int?(60), nil] {
            for c in cases {
                let m = try TR43ReRingTests.model(c, ringMaxS: ring)
                for mode in CaseCatalog.modes(m, interval: s.trace.file.intervalS) {
                    jobs.append(("\(s.id) \(c)/\(mode) ring=\(ring.map(String.init) ?? "inf")", m, ring, mode))
                }
            }
        }
        return await withTaskGroup(of: Run.self) { g in
            for (tag, m, ring, mode) in jobs { g.addTask { runOne(s, tag, m, ring, mode) } }
            var out: [Run] = []
            for await x in g { out.append(x) }
            return out.sorted { $0.tag < $1.tag }
        }
    }

    @Test("U128 loop routes after an alarm - no wrong-wording Overshoot except L1, the real overshoot after the arrival")
    func u128() async throws {
        let tr40 = try TR43ReRingTests.trace()
        var fails: [String] = []
        let routes: [(LoopRoutes.Synth, String)] = [
            (LoopRoutes.synth(tr40, "L1", LoopRoutes.l1()), "l1"),
            (LoopRoutes.synth(tr40, "L2", LoopRoutes.l2()), "noEarly"),
            (LoopRoutes.synth(tr40, "L3", LoopRoutes.l3()), "none"),
            (LoopRoutes.synth(tr40, "L4", LoopRoutes.l4(), noiseA: 5.0, seed: Self.noiseSeed), "none"),
            (LoopRoutes.synth(tr40, "L4n", LoopRoutes.l4()), "none"),
            (LoopRoutes.synth(tr40, "L5", LoopRoutes.l5(), noiseA: 5.0, seed: Self.noiseSeed), "none"),
        ]
        for (s, kind) in routes {
            let runs = try await Self.runAll(s)
            #expect(runs.count == 8, "\(s.id): \(runs.count) runs")
            for x in runs { fails += Self.check(s, x, kind) }
        }
        // L4 sweep: seeds 1...20 × a ∈ {5, 14} m, distance_1000 `all`, chime stopped.
        let m = try TR43ReRingTests.model("distance_1000", ringMaxS: 60)
        let sweep: [(LoopRoutes.Synth, Run)] = await withTaskGroup(of: (LoopRoutes.Synth, Run).self) { g in
            for seed in Int64(1)...20 {
                for a in [5.0, 14.0] {
                    g.addTask {
                        let s = LoopRoutes.synth(tr40, "L4s\(seed)a\(KW.ki(a))", LoopRoutes.l4(), noiseA: a, seed: seed)
                        return (s, Self.runOne(s, "\(s.id) distance_1000/all ring=60", m, 60, "all"))
                    }
                }
            }
            var out: [(LoopRoutes.Synth, Run)] = []
            for await x in g { out.append(x) }
            return out.sorted { $0.1.tag < $1.1.tag }
        }
        #expect(sweep.count == 40)
        for (s, x) in sweep { fails += Self.check(s, x, "none") }
        if fails.count > 30 { fails = Array(fails.prefix(30)) }
        for f in fails { Issue.record(Comment(rawValue: f)) }
    }
}
