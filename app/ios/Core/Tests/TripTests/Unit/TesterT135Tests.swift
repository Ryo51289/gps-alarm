import Foundation
import Testing
@testable import Trip

/// `t135-tester.txt` lines by key (parallel tests; written sorted by key under the lock, deterministic). Same keys and line format as
/// the Kotlin tester file `t124-tester.txt`, so the two files can be compared byte for byte.
final class T135Log: @unchecked Sendable {
    static let shared = T135Log()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func note(_ key: String, _ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines[key] = line
        Report.shared.write("unit/t135-tester.txt", lines.keys.sorted().map { lines[$0]! }.joined(separator: "\n") + "\n")
    }
}

/// `java.util.Random` (JDK 17, legacy algorithm): 48-bit LCG, `nextDouble` = 53 bits, `nextGaussian` = Marsaglia polar method with
/// the cached second value. Ported so the Gaussian loop routes of Kotlin `TesterT124Test` (L4, L5, L4 sweep) get the same noise.
/// Java uses `StrictMath.log` (fdlibm); here `Foundation.log` (glibc / Darwin libm). The two may differ by 1 ulp for some inputs,
/// which moves a sample by ~1e-15 m; the byte comparison of `t135-tester.txt` with Kotlin is the check that it did not matter.
struct JavaRandom {
    private static let mask: Int64 = (1 << 48) - 1
    private var seed: Int64
    private var nextNextGaussian = 0.0
    private var haveNextNextGaussian = false

    init(_ s: Int64) { seed = (s ^ 0x5DEECE66D) & Self.mask }

    mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* 0x5DEECE66D &+ 0xB) & Self.mask
        return Int32(truncatingIfNeeded: seed >> Int64(48 - bits))
    }

    mutating func nextDouble() -> Double {
        Double((Int64(next(26)) << 27) + Int64(next(27))) * 0x1.0p-53
    }

    mutating func nextGaussian() -> Double {
        if haveNextNextGaussian {
            haveNextNextGaussian = false
            return nextNextGaussian
        }
        var v1 = 0.0, v2 = 0.0, s = 0.0
        repeat {
            v1 = 2 * nextDouble() - 1
            v2 = 2 * nextDouble() - 1
            s = v1 * v1 + v2 * v2
        } while s >= 1 || s == 0
        let multiplier = (-2 * Foundation.log(s) / s).squareRoot()
        nextNextGaussian = v2 * multiplier
        haveNextNextGaussian = true
        return v1 * multiplier
    }
}

/// Tester T13.5 (T10.7 / RK24 + "T10.7 vòng 2", C31, PO Q14 = A; Swift): minimal port of the Kotlin tester cases
/// `unit/TesterT124Test.kt` (T12.4 test report Lần 2).
///
/// 1. TR40 (`coach_gb_caugie_gappass`, gap [2 020, 2 980)): (f2) relaunch at 3 010 while the OS chime still rings; SNOOZED with the
///    chord fix after snoozeUntil (s1, s2: chime still ringing at the overshoot; s1b, s3: chime stopped before it); (k) process killed
///    right after the chord fix (alarmedChordD through the snapshot). Each overshoot is also checked against an independent replay of
///    C31 (first fix with a measured rise >= 1 km; pastM = dSmooth − alarmedChordD), and pinned to the Kotlin numbers (`all`: f2 3 060
///    pastM 5 839; s*/k 3 030 pastM 5 179).
/// 2. RK20 (e) on the Kotlin tester's loop routes built in memory with the Kotlin placement (111 320 m per degree) and Gaussian noise
///    from a port of `java.util.Random` (U128 / `LoopRoutes` use splitmix64 uniform noise and R·π/180; this is the independent variant).
///    Gates L2–L5 no early Overshoot; L3–L5 Overshoot within 120 s after the arrival; L1 (RK20 e, accepted) only after a real rise
///    >= 1 km; L4 sweep 20 seeds × σ {3, 8} m.
/// Report: `unit/t135-tester.txt` (times, distances, u, phases; no coordinates), byte-identical to Kotlin `t124-tester.txt`.
@Suite("TesterT135Tests")
struct TesterT135Tests {
    static let traceId = "coach_gb_caugie_gappass"
    static let cases = ["distance_1000", "time_15", "smart"]
    static let killT = 2_320
    static let lost3600: [(String, JsonValue)] = [("gpsLostAlarmEtaS", .number("3600"))]
    /// Metres per degree of latitude used by Kotlin `TesterT124Test` to place the synthetic routes.
    static let mPerDeg = 111_320.0
    static let v = 15.0
    static let loopGap = (fromT: 1_005, toT: 1_800)

    typealias TimedEvent = TR43ReRingTests.TimedEvent

    struct Run: Sendable {
        let caseId: String
        let r: Runner

        var tag: String { "\(caseId)/\(r.mode)" }

        var evs: [TimedEvent] {
            var out: [TimedEvent] = []
            for (i, rec) in r.records.enumerated() { for e in rec.events { out.append(TimedEvent(t: rec.t, rec: i, e: e)) } }
            return out
        }

        var alarms: [TimedEvent] { evs.filter { if case .alarm = $0.e { true } else { false } } }
        var overshoots: [TimedEvent] { evs.filter { if case .overshoot = $0.e { true } else { false } } }
    }

    static func tr40() throws -> LoadedTrace { try TR43ReRingTests.trace() }

    static func alarm(_ e: TimedEvent?) -> TripEvent.Alarm? {
        guard let e, case let .alarm(a) = e.e else { return nil }
        return a
    }

    static func pastM(_ e: TimedEvent?) -> Int? {
        guard let e, case let .overshoot(o) = e.e else { return nil }
        return o.pastM
    }

    static func s(_ x: Int?) -> String { x.map(String.init) ?? "null" }

    /// Kotlin `desc`.
    static func desc(_ e: TimedEvent) -> String {
        switch e.e {
        case let .alarm(a): "\(e.t) alarm \(a.reason.jsonName) ringNow=\(a.ringNow)"
        case let .overshoot(o): "\(e.t) overshoot pastM=\(o.pastM)"
        case let .fallbackAlarmChanged(f): "\(e.t) fallbackAlarmChanged \(f.fallbackAtMs == nil ? "null" : "set") \(f.cause.jsonName)"
        case let .tripEnded(x): "\(e.t) tripEnded \(x.outcome.jsonName) \(x.endReason.jsonName)"
        default: "\(e.t) \(e.e.fixtureName)"
        }
    }

    /// Kotlin `timeline`: markers and events in [from, to], fallbackAlarmChanged only when cleared.
    static func timeline(_ r: Runner, _ from: Int, _ to: Int) -> String {
        var out: [String] = []
        for (i, rec) in r.records.enumerated() {
            if rec.t < from || rec.t > to { continue }
            switch rec.input {
            case .kill: out.append("\(rec.t) KILL")
            case let .restore(_, status, _, _): out.append("\(rec.t) RESTORE \(status.jsonName)")
            case .input(.alarmSilenced, _): out.append("\(rec.t) in:alarmSilenced")
            case let .input(.userAction(_, k), _): out.append("\(rec.t) in:\(k.jsonName)")
            default: break
            }
            for e in rec.events {
                if case let .fallbackAlarmChanged(f) = e, f.fallbackAtMs != nil { continue }
                out.append(desc(TimedEvent(t: rec.t, rec: i, e: e)))
            }
        }
        return out.joined(separator: "; ")
    }

    static func runs(_ tr: LoadedTrace, _ cs: [String], _ m: (String) throws -> CaseSpec, _ options: RunOptions) async throws -> [Run] {
        var jobs: [(String, CaseSpec, String)] = []
        for c in cs {
            let spec = try m(c)
            for mode in CaseCatalog.modes(spec, interval: tr.file.intervalS) { jobs.append((c, spec, mode)) }
        }
        let out: [Run] = await withTaskGroup(of: Run.self) { g in
            for (c, spec, mode) in jobs {
                g.addTask {
                    var r = Runner(trace: tr, spec: spec, mode: mode, options: options)
                    r.runAll()
                    return Run(caseId: c, r: r)
                }
            }
            var res: [Run] = []
            for await x in g { res.append(x) }
            return res
        }
        return out.sorted { $0.caseId != $1.caseId ? $0.caseId < $1.caseId : $0.r.mode < $1.r.mode }
    }

    static func harness(_ x: Run) -> [String] { Checks.run(x.r).map { "\(x.tag): \($0)" } }

    static func inWindow(_ t: Int?, _ from: Int, _ w: Int) -> Bool { t != nil && t! >= from && t! <= from + w }

    /// Independent replay of C31 term (2) (Kotlin `replay`): dSmooth = medianHi of the raw distances of the newest 3 fixes within
    /// smoothWindowS, minD = min dSmooth since the start (never lowered by a chord after the alarm); first fix tick >= fromT with
    /// dSmooth − minD >= overshootOpenM; dSmooth at every fix tick.
    static func replay(_ x: Run, _ tr: LoadedTrace, _ fromT: Int) -> (firstRiseT: Int?, dSmoothAt: [Int: Double]) {
        let p = x.r.params
        var recent: [(Int64, Double)] = []
        var minD: Double? = nil
        var rise: Int? = nil
        var ds: [Int: Double] = [:]
        for rec in x.r.records {
            guard case let .input(.locationFix(f), _) = rec.input else { continue }
            let d = Geo.distanceM(f.lat, f.lng, tr.file.destLat, tr.file.destLng)
            recent.removeAll { $0.0 < f.fixAtMs - Int64(p.smoothWindowS) * 1000 }
            recent.append((f.fixAtMs, d))
            while recent.count > 3 { recent.removeFirst() }
            let sm = TMath.medianHi(recent.map { Optional($0.1) })!
            ds[rec.t] = sm
            let m = minD == nil || sm < minD! ? sm : minD!
            minD = m
            if rise == nil && rec.t >= fromT && sm - m >= Double(p.overshootOpenM) { rise = rec.t }
        }
        return (rise, ds)
    }

    /// Kotlin `c31`: the overshoot is at the first measured rise >= 1 km, pastM = roundHalfUp(dSmooth − chordD) within 1 m.
    static func c31(_ x: Run, _ tr: LoadedTrace, _ ov: TimedEvent?, _ fromT: Int, _ chordD: Double?, _ label: String) -> [String] {
        guard let ov, let chordD else { return ["\(x.tag) (\(label)): C31 check without overshoot/chord"] }
        var f: [String] = []
        let rp = replay(x, tr, fromT)
        if rp.firstRiseT != ov.t {
            f.append("\(x.tag) (\(label)): overshoot \(ov.t), first measured rise >= 1 km at \(s(rp.firstRiseT)) (C31 term 2)")
        }
        let want = rp.dSmoothAt[ov.t].map { TMath.roundHalfUp($0 - chordD) }
        let pm = pastM(ov) ?? Int.min
        if want == nil || abs(pm - want!) > 1 { f.append("\(x.tag) (\(label)): pastM \(pm), want dSmooth − alarmedChordD = \(s(want)) (C31)") }
        return f
    }

    static func report(_ fails: [String]) {
        var list = fails
        if list.count > 40 { list = Array(list.prefix(40)) + ["… \(fails.count - 40) more"] }
        for f in list { Issue.record(Comment(rawValue: f)) }
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // 1. TR40 variants
    // ---------------------------------------------------------------------------------------------------------------------------

    /// Kotlin `T124 f2`: as TR43 (f) (kill 2 320, relaunch 3 010) but no osRingMaxS — the OS fallback chime still rings at the
    /// relaunch. Restore RANG → Alarm(FALLBACK, ringNow=false), no AlarmSilenced, the first fix after the relaunch is an ALARMING chord
    /// fix, then the Overshoot only (no second ring). `all` 3 060, pastM 5 839 (Kotlin).
    @Test("T135 f2 relaunch after the GPS returned while the OS chime still rings - Overshoot only, no second ring")
    func f2() async throws {
        let tr = try Self.tr40()
        var fails: [String] = []
        let rel = 3_010
        let rs = try await Self.runs(tr, Self.cases, { try TR43ReRingTests.model($0, kill: Self.killT, relaunch: rel) },
                                     RunOptions(probes: true))
        #expect(rs.count == 6)
        for x in rs {
            fails += Self.harness(x)
            let fb = x.r.os.osFallbackFiredT
            if fb == nil || fb! >= rel { fails.append("\(x.tag) (f2): OS fallback fired at \(Self.s(fb)), want before the relaunch \(rel)") }
            let restore = x.alarms.first { $0.t == rel }
            if let a = Self.alarm(restore), a.reason == .fallback, !a.ringNow {} else {
                fails.append("\(x.tag) (f2): at relaunch \(restore.map(Self.desc) ?? "null"), want alarm FALLBACK ringNow=false")
            }
            let ov = x.overshoots.count == 1 ? x.overshoots[0] : nil
            let silenced = x.r.records.contains { rec in
                guard case .input(.alarmSilenced, _) = rec.input else { return false }
                return rec.t >= rel && (ov == nil || rec.t <= ov!.t)
            }
            if silenced { fails.append("\(x.tag) (f2): precondition: AlarmSilenced while the OS chime should still ring") }
            var g: GapProbe? = nil
            for p in x.r.gapProbes where p.atMs - x.r.startMs >= Int64(rel) * 1000 {
                if let cur = g, cur.atMs <= p.atMs { continue }
                g = p
            }
            if g == nil || !g!.gapFix || g!.phase != .alarming || (g!.dChord ?? .greatestFiniteMagnitude) >= 1_000.0 {
                fails.append("\(x.tag) (f2): first fix after relaunch gapFix=\(g.map { String($0.gapFix) } ?? "null") "
                             + "phase=\(g?.phase.jsonName ?? "null") dChord=\(KW.kdOpt(g?.dChord))")
            }
            if !Self.inWindow(ov?.t, rel, 60) {
                fails.append("\(x.tag) (f2): overshoot \(KW.klist(x.overshoots.map(Self.desc))), window [\(rel), \(rel + 60)]")
            }
            let rang = x.alarms.filter { $0.t >= rel && Self.alarm($0)!.ringNow }
            if !rang.isEmpty { fails.append("\(x.tag) (f2): second ring \(KW.klist(rang.map(Self.desc)))") }
            if let ov {
                let view = x.r.records[ov.rec].view
                if !view.alarmRinging { fails.append("\(x.tag) (f2): alarmRinging false at the overshoot") }
                if view.phase != .overshot { fails.append("\(x.tag) (f2): phase \(view.phase.jsonName) at the overshoot") }
            }
            fails += Self.c31(x, tr, ov, rel, g?.dChord, "f2")
            if !x.r.isPolicy && ov?.t != 3_060 { fails.append("\(x.tag) (f2): by hand 3060 (T10.7 vòng 2 §4), got \(Self.s(ov?.t))") }
            // Parity with Kotlin T12.4 Lần 2 (t124-tester.txt): pastM 5 839 = dSmooth 6 372.5 − dChord 533.5 in every mode.
            if Self.pastM(ov) != 5_839 { fails.append("\(x.tag) (f2): pastM \(Self.s(Self.pastM(ov))), Kotlin 5839") }
            let line = "(f2) \(x.tag): OS fallback \(Self.s(fb)); chord t=\(g.map { String(($0.atMs - x.r.startMs) / 1000) } ?? "null") "
                + "u=\(g?.u.map { KW.jf($0, 4) } ?? "null") dChord=\(g?.dChord.map { KW.jf($0, 1) } ?? "null"); "
                + "first measured rise >= 1 km at \(Self.s(Self.replay(x, tr, rel).firstRiseT)); \(Self.timeline(x.r, 2_880, 3_100))"
            T135Log.shared.note("1 f2 \(x.tag)", line)
        }
        Self.report(fails)
    }

    /// Kotlin `T124 s1 s1b s2 s3`: SNOOZED, the chord fix (2 980) after snoozeUntil; the overshoot at 3 030 (`all`):
    /// (s1) osRingMaxS 60, snooze 2 915: SNOOZE_END 2 975 still rings at 3 030 (stops 3 035) → Overshoot only.
    /// (s1b) osRingMaxS 60, snooze 2 900: SNOOZE_END 2 960 stops at 3 020 → AlarmSilenced 3 020, one re-ring OVERSHOOT (PO #18).
    /// (s2) snooze 2 900, the chime never stops → Overshoot only.
    /// (s3) osRingMaxS 60, snooze 2 840: SNOOZE_END 2 900 stopped at 2 960 → one re-ring OVERSHOOT.
    @Test("T135 s1 s1b s2 s3 snoozed, chord fix after snoozeUntil - still ringing gives Overshoot only, stopped chime re-rings OVERSHOOT")
    func snoozed() async throws {
        let tr = try Self.tr40()
        let gEnd = TR43ReRingTests.gEnd
        #expect(gEnd == 2_980)
        var fails: [String] = []
        let variants: [(id: String, ringMax: Int?, snoozeAt: Int, ringingAtOvershoot: Bool, silencedAt: Int?)] = [
            ("s1", 60, 2_915, true, nil), ("s1b", 60, 2_900, false, 3_020), ("s2", nil, 2_900, true, nil), ("s3", 60, 2_840, false, 2_960),
        ]
        for v in variants {
            let acts: [(at: At, action: String)] = [(at: At(t: v.snoozeAt, anchor: nil, offsetS: 0), action: "snooze")]
            let until = v.snoozeAt + 60
            let rs = try await Self.runs(tr, Self.cases, { try TR43ReRingTests.model($0, ringMaxS: v.ringMax, actions: acts) },
                                         RunOptions(paramOverrides: Self.lost3600, probes: true))
            #expect(rs.count == 6)
            for x in rs {
                fails += Self.harness(x)
                let first = x.alarms.first
                if let a = Self.alarm(first), a.reason == .gpsLost, first!.t < v.snoozeAt {} else {
                    fails.append("\(x.tag) (\(v.id)): first alarm \(first.map(Self.desc) ?? "null"), want GPS_LOST before the snooze")
                }
                if !x.evs.contains(where: { e in if case .snoozed = e.e { return e.t == v.snoozeAt } else { return false } }) {
                    fails.append("\(x.tag) (\(v.id)): no snoozed at \(v.snoozeAt)")
                }
                let se = x.alarms.first { Self.alarm($0)!.reason == .snoozeEnd }
                if se == nil || se!.t != until || !Self.alarm(se)!.ringNow {
                    fails.append("\(x.tag) (\(v.id)): SNOOZE_END \(se.map(Self.desc) ?? "null"), want ringNow=true at \(until)")
                }
                let ov = x.overshoots.count == 1 ? x.overshoots[0] : nil
                let silenced = x.r.records.compactMap { rec -> Int? in
                    guard case .input(.alarmSilenced, _) = rec.input, rec.t >= until, ov == nil || rec.t <= ov!.t else { return nil }
                    return rec.t
                }
                let wantSilenced = v.silencedAt.map { [$0] } ?? []
                if silenced != wantSilenced {
                    fails.append("\(x.tag) (\(v.id)): precondition: AlarmSilenced at \(silenced), want \(wantSilenced)")
                }
                let g = x.r.gapProbes.first { $0.atMs - x.r.startMs == Int64(gEnd) * 1000 }
                if g == nil || !g!.gapFix || g!.phase != .alarming || (g!.dChord ?? .greatestFiniteMagnitude) >= 1_000.0 {
                    fails.append("\(x.tag) (\(v.id)): fix at g.end gapFix=\(g.map { String($0.gapFix) } ?? "null") "
                                 + "phase=\(g?.phase.jsonName ?? "null") dChord=\(KW.kdOpt(g?.dChord))")
                }
                if !Self.inWindow(ov?.t, gEnd, 60) {
                    fails.append("\(x.tag) (\(v.id)): overshoot \(KW.klist(x.overshoots.map(Self.desc))), window [\(gEnd), \(gEnd + 60)]")
                }
                let after = x.alarms.filter { $0.t > until }
                if v.ringingAtOvershoot {
                    if !after.isEmpty { fails.append("\(x.tag) (\(v.id)): \(KW.klist(after.map(Self.desc))) after SNOOZE_END (chime still rings)") }
                    if let ov, !x.r.records[ov.rec].view.alarmRinging { fails.append("\(x.tag) (\(v.id)): alarmRinging false") }
                } else {
                    let a = after.count == 1 ? after[0] : nil
                    if let al = Self.alarm(a), al.reason == .overshoot, al.ringNow, a!.rec == ov?.rec {} else {
                        fails.append("\(x.tag) (\(v.id)): after SNOOZE_END \(KW.klist(after.map(Self.desc))), want one OVERSHOOT ringNow=true "
                                     + "with the overshoot")
                    }
                }
                if let ov, x.r.records[ov.rec].view.phase != .overshot { fails.append("\(x.tag) (\(v.id)): phase at the overshoot") }
                fails += Self.c31(x, tr, ov, gEnd, g?.dChord, v.id)
                if !x.r.isPolicy && ov?.t != 3_030 {
                    fails.append("\(x.tag) (\(v.id)): by hand 3030 (T10.7 vòng 2 §4, as TR43 a), got \(Self.s(ov?.t))")
                }
                if Self.pastM(ov) != 5_179 { fails.append("\(x.tag) (\(v.id)): pastM \(Self.s(Self.pastM(ov))), Kotlin 5179") }
                T135Log.shared.note("2 \(v.id) \(x.tag)", "(\(v.id)) \(x.tag): \(Self.timeline(x.r, 2_830, 3_060))")
            }
        }
        Self.report(fails)
    }

    /// Kotlin `T124 k` (restart in mid-trip, T10.7 §5 I8; vòng 2 §4 row "T124 k"): chime stopped (TR43 a), the process killed at
    /// 2 990 right after the chord fix (2 980) stored alarmedChordD in ALARMING, relaunched at 2 995. Without alarmedChordD in the
    /// snapshot nearD = minD ≈ 4 600 m and nothing would ring. Gate: one re-ring OVERSHOOT in [g.end, g.end + 60], C31, same t and
    /// pastM as without the kill (`all` 3 030, pastM 5 179).
    @Test("T135 k process killed right after the chord fix in ALARMING - the re-ring survives the restart")
    func killAfterChord() async throws {
        let tr = try Self.tr40()
        let gEnd = TR43ReRingTests.gEnd
        var fails: [String] = []
        let kill = 2_990
        let rel = 2_995
        let opts = RunOptions(paramOverrides: Self.lost3600, probes: true)
        let refRuns = try await Self.runs(tr, Self.cases, { try TR43ReRingTests.model($0, ringMaxS: 60) }, opts)
        var ref: [String: Run] = [:]
        for x in refRuns { ref[x.tag] = x }
        let rs = try await Self.runs(tr, Self.cases, { try TR43ReRingTests.model($0, ringMaxS: 60, kill: kill, relaunch: rel) }, opts)
        #expect(rs.count == 6)
        for x in rs {
            fails += Self.harness(x)
            let g = x.r.gapProbes.first { $0.atMs - x.r.startMs == 2_980_000 }
            if g == nil || !g!.gapFix || g!.phase != .alarming || (g!.dChord ?? .greatestFiniteMagnitude) >= 1_000.0 {
                fails.append("\(x.tag) (k): no ALARMING chord fix at 2980 (\(g?.phase.jsonName ?? "null") \(KW.kdOpt(g?.dChord)))")
            }
            let before = x.evs.contains { e in
                guard e.t >= 2_980 && e.t < kill else { return false }
                switch e.e { case .overshoot, .alarm: return true; default: return false }
            }
            if before { fails.append("\(x.tag) (k): precondition: event before the kill") }
            let after = x.alarms.filter { $0.t >= kill && Self.alarm($0)!.ringNow }
            let ov = x.overshoots.count == 1 ? x.overshoots[0] : nil
            let a = after.count == 1 ? after[0] : nil
            if Self.alarm(a)?.reason != .overshoot || ov == nil || a!.rec != ov!.rec || !Self.inWindow(ov?.t, gEnd, 60) {
                fails.append("\(x.tag) (k): after relaunch \(KW.klist(after.map(Self.desc))) overshoot \(KW.klist(x.overshoots.map(Self.desc))), "
                             + "want one OVERSHOOT re-ring in [\(gEnd), \(gEnd + 60)]")
            }
            fails += Self.c31(x, tr, ov, gEnd, g?.dChord, "k")
            let r0 = ref[x.tag].flatMap { $0.overshoots.count == 1 ? $0.overshoots[0] : nil }
            if r0 == nil || ov == nil || r0!.t != ov!.t || Self.pastM(r0) != Self.pastM(ov) {
                fails.append("\(x.tag) (k): overshoot \(ov.map(Self.desc) ?? "null"), run without the kill \(r0.map(Self.desc) ?? "null")")
            }
            if !x.r.isPolicy && ov?.t != 3_030 { fails.append("\(x.tag) (k): by hand 3030 (T10.7 vòng 2 §4), got \(Self.s(ov?.t))") }
            if Self.pastM(ov) != 5_179 { fails.append("\(x.tag) (k): pastM \(Self.s(Self.pastM(ov))), Kotlin 5179") }
            T135Log.shared.note("3 k \(x.tag)", "(k) \(x.tag): \(Self.timeline(x.r, 2_970, 3_060)); without the kill: \(r0.map(Self.desc) ?? "null")")
        }
        Self.report(fails)
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // 2. RK20 (e): synthetic loop routes (in memory)
    // ---------------------------------------------------------------------------------------------------------------------------

    struct Synth: Sendable {
        let trace: LoadedTrace
        let route: LoopRoutes.Route
        let sD: Double
        let gap: (fromT: Int, toT: Int)

        var arrivalT: Int { trace.file.arrivalT }

        func passed(_ t: Int) -> Bool { TesterT135Tests.v * Double(t) >= sD }

        func trueD(_ t: Int) -> Double {
            let p = route.at(TesterT135Tests.v * Double(t))
            return (p[0] * p[0] + p[1] * p[1]).squareRoot()
        }

        /// Smallest true distance so far (5 s steps, as Kotlin).
        func trueMinD(_ t: Int) -> Double {
            var m = Double.greatestFiniteMagnitude
            var u = 0
            while u <= t {
                m = Swift.min(m, trueD(u))
                u += 5
            }
            return m
        }
    }

    /// Kotlin `synth`: samples every 5 s at 15 m/s along `route`, none in `gap`, accuracy 8 m, Doppler v, optional Gaussian noise
    /// (`java.util.Random(seed)`, x then y per delivered sample), placed around the TR40 destination with 111 320 m per degree.
    static func synth(_ tr40: LoadedTrace, _ id: String, _ route: LoopRoutes.Route, noiseM: Double = 0.0, seed: Int64 = 124) -> Synth {
        let dLat = tr40.file.destLat
        let dLng = tr40.file.destLng
        let cosLat = Foundation.cos(dLat * Double.pi / 180.0)
        let dur = (KW.ki(route.length / v) / 5) * 5
        var rnd = JavaRandom(seed)
        var samples: [TraceSample] = []
        var t = 0
        while t <= dur {
            if t < loopGap.fromT || t >= loopGap.toT {
                let p = route.at(v * Double(t))
                let nx = noiseM > 0 ? rnd.nextGaussian() * noiseM : 0.0
                let ny = noiseM > 0 ? rnd.nextGaussian() * noiseM : 0.0
                samples.append(TraceSample(index: samples.count, t: t, lat: dLat + (p[1] + ny) / mPerDeg,
                                           lng: dLng + (p[0] + nx) / (mPerDeg * cosLat), accuracyM: 8.0, speedMps: v))
            }
            t += 5
        }
        let sD = route.closestS()
        let b = tr40.file
        let file = TraceFile(traceId: "t124_\(id)", vehicle: "coach", gpx: "t124_\(id).gpx", startTime: b.startTime, startMs: b.startMs,
                             intervalS: 5, durationS: dur, sampleCount: samples.count, destLat: dLat, destLng: dLng,
                             arrivalT: KW.ki(sD / v), gpsGaps: [loopGap], overshootT: nil, closestT: nil, closestDepartT: nil,
                             routeT: [:], straightT: [:], rawCases: [])
        var byTick = [Int?](repeating: nil, count: dur / 5 + 1)
        for x in samples { byTick[x.t / 5] = x.index }
        return Synth(trace: LoadedTrace(file: file, samples: samples, byTick: byTick), route: route, sD: sD, gap: loopGap)
    }

    enum LoopGate { case rk20e, noEarly, afterArrival }

    /// Kotlin `loopRuns`: distance_1000 and time_15, chime stopped (60 s) and still ringing, `all` + `policy`.
    static func loopRuns(_ id: String, _ s: Synth, _ gate: LoopGate) async throws -> (wrong: Int, lines: Int, fails: [String]) {
        var fails: [String] = []
        var count = 0
        var wrong = 0
        let gEnd = s.gap.toT
        for ring in [Int?(60), nil] {
            let rs = try await runs(s.trace, ["distance_1000", "time_15"], { try TR43ReRingTests.model($0, ringMaxS: ring) },
                                    RunOptions(probes: true))
            for x in rs {
                let ringS = ring.map(String.init) ?? "inf"
                let tag = "\(id) \(x.tag) ring=\(ringS)"
                fails += harness(x).map { "\(id) ring=\(ringS) \($0)" }
                let first = x.alarms.first
                if first == nil || first!.t >= gEnd { fails.append("\(tag): precondition: no alarm before g.end (\(first.map(desc) ?? "null"))") }
                let g = x.r.gapProbes.first { $0.atMs - x.r.startMs == Int64(gEnd) * 1000 }
                if g == nil || !g!.gapFix || g!.phase != .alarming {
                    fails.append("\(tag): precondition: fix at g.end gapFix=\(g.map { String($0.gapFix) } ?? "null") phase=\(g?.phase.jsonName ?? "null")")
                }
                let ov = x.overshoots.first
                let ovAlarm = ov.flatMap { o in x.alarms.first { $0.rec == o.rec } }
                let early = ov != nil && !s.passed(ov!.t)
                if early { wrong += 1 }
                let arr = s.arrivalT
                switch gate {
                case .rk20e:
                    if let ov, early, s.trueD(ov.t) - s.trueMinD(ov.t) < 1_000.0 - 10.0 {
                        fails.append("\(tag): wrong-wording Overshoot at \(ov.t) with a real rise of only \(KW.kd(s.trueD(ov.t) - s.trueMinD(ov.t))) m (C31)")
                    }
                case .noEarly:
                    if let ov, early { fails.append("\(tag): Overshoot at \(ov.t) before the arrival \(arr)") }
                case .afterArrival:
                    if ov == nil || early || ov!.t > arr + 120 { fails.append("\(tag): Overshoot \(Self.s(ov?.t)), want in [\(arr), \(arr + 120)]") }
                }
                // PO #18: with the chime stopped the Overshoot re-rings in its Step; while it still rings, no second ring.
                let ovA = alarm(ovAlarm)
                if let ov, ring != nil, ovA == nil || ovA!.reason != .overshoot || !ovA!.ringNow {
                    fails.append("\(tag): overshoot \(ov.t) without the re-ring (\(ovAlarm.map(desc) ?? "null"))")
                }
                if ring == nil && x.alarms.dropFirst().contains(where: { alarm($0)!.ringNow }) { fails.append("\(tag): second ring while the chime rings") }
                let ended = x.evs.first { if case .tripEnded = $0.e { true } else { false } }
                let afterArrival = x.alarms.filter { $0.t >= arr - 60 }
                let truth = ov == nil ? "-" : early ? "NOT PASSED (wrong wording)" : "passed"
                let line = "\(tag): first \(first.map(desc) ?? "null"); chord fix t=\(gEnd) u=\(g?.u.map { KW.jf($0, 4) } ?? "null") "
                    + "dChord=\(g?.dChord.map { KW.jf($0, 1) } ?? "null") d_f=\(KW.jf(g?.dFixM ?? .nan, 0)) trueMinD=\(KW.jf(s.trueMinD(gEnd), 0)); "
                    + "overshoot \(ov.map(desc) ?? "none")\(ovAlarm.map { " + \(desc($0))" } ?? "") (truth \(truth), "
                    + "trueD=\(ov.map { KW.jf(s.trueD($0.t), 0) } ?? "-")); arrival \(arr), alarms from arrival−60: "
                    + "\(KW.klist(afterArrival.map(desc))); \(ended.map(desc) ?? "no tripEnded")"
                T135Log.shared.note("4 \(line)", "(RK20e) \(line)")
                count += 1
            }
        }
        return (wrong, count, fails)
    }

    /// Kotlin `T124 RK20e`: L1 (RK20 e accepted, only after a real rise >= 1 km), L2 (no early Overshoot), L3, L4 (σ 3 m, seed 124),
    /// L4n, L5 (σ 3 m) (no early Overshoot, Overshoot within 120 s after the arrival, re-ring when the chime stopped); L4 sweep seeds
    /// 1–20 × σ {3, 8} m, distance_1000 `all`, chime stopped. Kotlin Lần 2: L1 8/8 wrong-wording at 1 985 (real rise 1 087 m), the rest
    /// 0; sweep 0/40.
    @Test("T135 RK20e loop route - alarm before the gap, chord cuts within 1 km, vehicle still approaching")
    func rk20e() async throws {
        let tr = try Self.tr40()
        var fails: [String] = []
        let l4 = LoopRoutes.l4()
        let routes: [(String, Synth, LoopGate)] = [
            ("L1", Self.synth(tr, "L1", LoopRoutes.l1()), .rk20e),
            ("L2", Self.synth(tr, "L2", LoopRoutes.l2()), .noEarly),
            ("L3", Self.synth(tr, "L3", LoopRoutes.l3()), .afterArrival),
            ("L4", Self.synth(tr, "L4", l4, noiseM: 3.0), .afterArrival),
            ("L4n", Self.synth(tr, "L4n", l4), .afterArrival),
            ("L5", Self.synth(tr, "L5", LoopRoutes.l5(), noiseM: 3.0), .afterArrival),
        ]
        var wrongBy: [String: Int] = [:]
        for (id, s, gate) in routes {
            let r = try await Self.loopRuns(id, s, gate)
            #expect(r.lines == 8, "\(id): \(r.lines) runs")
            fails += r.fails
            wrongBy[id] = r.wrong
            T135Log.shared.note("5 \(id)", "(RK20e) \(id): wrong-wording overshoots \(r.wrong)/\(r.lines) runs")
        }
        // Kotlin Lần 2 counts.
        if wrongBy != ["L1": 8, "L2": 0, "L3": 0, "L4": 0, "L4n": 0, "L5": 0] { fails.append("wrong-wording counts \(wrongBy), Kotlin L1 8, others 0") }
        let m = try TR43ReRingTests.model("distance_1000", ringMaxS: 60)
        for sigma in [3.0, 8.0] {
            let sweep: [(Int64, Synth, Runner)] = await withTaskGroup(of: (Int64, Synth, Runner).self) { g in
                for seed in Int64(1)...20 {
                    g.addTask {
                        let s = Self.synth(tr, "L4s\(seed)", l4, noiseM: sigma, seed: seed)
                        var r = Runner(trace: s.trace, spec: m, mode: "all", options: RunOptions(probes: false))
                        r.runAll()
                        return (seed, s, r)
                    }
                }
                var out: [(Int64, Synth, Runner)] = []
                for await x in g { out.append(x) }
                return out.sorted { $0.0 < $1.0 }
            }
            #expect(sweep.count == 20)
            var hits: [String] = []
            var ts: [Int: Int] = [:]
            for (seed, s, r) in sweep {
                fails += Checks.run(r).map { "L4 seed \(seed) sigma \(KW.kd(sigma)): \($0)" }
                var ov: Int? = nil
                outer: for rec in r.records {
                    for e in rec.events { if case .overshoot = e { ov = rec.t; break outer } }
                }
                if let ov { ts[ov, default: 0] += 1 }
                if let ov, !s.passed(ov) { hits.append("seed \(seed) t=\(ov)") }
                if ov == nil || !s.passed(ov!) || ov! > s.arrivalT + 120 {
                    fails.append("L4 seed \(seed) sigma \(KW.kd(sigma)): Overshoot \(Self.s(ov)), want in [\(s.arrivalT), \(s.arrivalT + 120)]")
                }
            }
            let tsStr = "{" + ts.keys.sorted().map { "\($0)=\(ts[$0]!)" }.joined(separator: ", ") + "}"
            T135Log.shared.note("6 L4 sweep \(KW.kd(sigma))",
                                "(RK20e) L4 sweep sigma=\(KW.ki(sigma)) m: wrong-wording overshoots \(hits.count)/20 [\(hits.joined(separator: ", "))]; "
                                + "overshoot t \(tsStr)")
        }
        Self.report(fails)
    }
}
