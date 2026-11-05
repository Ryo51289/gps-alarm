import Foundation
import Testing
@testable import Trip

/// `u127.txt` lines by case key (parallel tests; written sorted by key under the lock, so the file is deterministic).
final class U127Log: @unchecked Sendable {
    static let shared = U127Log()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func note(_ key: String, _ text: String) {
        lock.lock()
        defer { lock.unlock() }
        lines[key] = text
        Report.shared.write("unit/u127.txt", lines.keys.sorted().map { "\($0): \(lines[$0]!)" }.joined(separator: "\n") + "\n")
    }
}

/// T10.7 (T10 mục cuối "T10.7", C30; RK24; Kotlin `unit/T107Test.kt`): the GPS-gap chord is also taken after an alarm
/// (ALARMING/SNOOZED, overshootAtMs == nil). T10.7 round 2 (C31): there it only records alarmedChordD, which proves "came
/// near" (nearD); the usual overshoot rule (increasing && fast against minD, PO #18) still decides the re-ring. U127 (a)–(l) of
/// T10 "T10.7" §9.1 (as corrected at T12.4: (k1)/(k2), (l) 192 rows). Builder `gapState` = the U114 (a) builder
/// (`T105GapTests.reproState`) after a GPS_LOST alarm rang in the gap, 15 min before n. Report: `u127.txt` (times relative to n,
/// pastM, the isGapFix truth table; no coordinates), lines sorted by case, byte-identical to Kotlin.
/// T10.7 round 2 (C31, Q14 = A): after the alarm the chord only proves "came near" (alarmedChordD → nearD); "moved away 1 km" is
/// measured from minD (observed fixes). U127 (m), (n) and U129 (codec) of "T10.7 vòng 2" §7.
@Suite("T107Tests")
struct T107Tests {
    static let n = T105GapTests.n

    /// U127 (a): T10.7 round 2 — the re-ring when dSmooth − minD (observed, 3 100) >= 1 000: designer by hand n + 65 s, pastM ≈ 4 180
    /// (dSmooth = d(t − 5 s), nearD = alarmedChordD ≈ 0). Round 1: n + 20 s, 3 370.
    static let u127AtMs: Int64 = 65_000
    static let u127PastM = 4_180
    /// U127 (k2): measured n + 5 s (as round 1, pastM 1 890): minD is the observed fix 400 m before the destination, so
    /// dSmooth − minD = 1 890 − 400 >= 1 000 at the 2nd fix (T12.4 round 3 notes; designer by hand ≈ n + 35 s assumed minD ≈ d_f).
    static let u127K2AtMs: Int64 = 5_000
    /// U127 (e1): measured index of the Overshoot fix.
    static let u127E1Fix = 63
    /// U127 (e2): measured index of the Overshoot fix (after passing the destination; Kotlin `U127_E2_FIX`).
    static let u127E2Fix = 86

    // MARK: - builders (as T105GapTests U114)

    static func alarmed(_ ringing: Bool, at: Int64 = T107Tests.n - 900_000, reason: AlarmReason = .gpsLost) -> AlarmState {
        AlarmState(atMs: at, reason: reason, source: .engine, lastRingAtMs: at, lastReason: reason, ringing: ringing, snoozeCount: 0,
                   snoozeUntilMs: nil, dismissedAtMs: nil)
    }

    /// U127 builder: `phase` after a GPS_LOST alarm at n − 900 s (chime stopped when !`ringing`); fallback cleared.
    static func gapState(_ phase: TripPhase = .alarming, ringing: Bool = false) -> EngineState {
        var s = T105GapTests.reproState()
        s.phase = phase
        s.alarm = alarmed(ringing)
        s.fallback = .cleared
        return s
    }

    /// One fix of a sequence: time, metres south (negative = north), metres east, Doppler speed, accuracy.
    struct Fx {
        let at: Int64
        let south: Double
        let east: Double
        let spd: Double?
        var acc: Double = 8.0
    }

    static func locFix(_ f: Fx) -> EngineInput {
        let p = T105GapTests.pt(f.south, f.east)
        return .locationFix(LocationFix(atMs: f.at, fixAtMs: f.at, lat: p.lat, lng: p.lng, accuracyM: f.acc, speedMps: f.spd))
    }

    /// Feeds every fix of `fixes` from `st` (stops at ENDED); returns every Step.
    static func drive(_ st: EngineState, _ fixes: [Fx]) -> [Step] {
        var out: [Step] = []
        var s = st
        for f in fixes {
            if s.phase == .ended { break }
            let step = TripEngine.reduce(s, locFix(f))
            out.append(step)
            s = step.state
        }
        return out
    }

    /// U114 (a) `away`: a fix every 5 s from n, moving away north from `past` m beyond the destination at `v` m/s; 120 s by default.
    static func away(past: Double = 3_100.0, v: Double = 18.0, count: Int = 25) -> [Fx] {
        (0..<count).map { i in Fx(at: n + 5_000 * Int64(i), south: -(past + v * 5.0 * Double(i)), east: 0.0, spd: v) }
    }

    static func events(_ steps: [Step]) -> [TripEvent] { steps.flatMap(\.events) }

    static func isOvershoot(_ e: TripEvent) -> Bool { if case .overshoot = e { return true } else { return false } }
    static func isAlarm(_ e: TripEvent) -> Bool { if case .alarm = e { return true } else { return false } }
    static func isFac(_ e: TripEvent) -> Bool { if case .fallbackAlarmChanged = e { return true } else { return false } }

    static func rel(_ s: Step) -> String { KW.kd(Double(s.state.nowMs - n) / 1000.0) }

    /// I1 (no Alarm(ringNow) while the previous still rings), I6, I11, I12, I13, C16 on a Step sequence from `st0`.
    static func invariants(_ st0: EngineState, _ steps: [Step], _ tag: String, sourceLocation: SourceLocation = #_sourceLocation) {
        var prev = st0
        for s in steps {
            let alarms = s.events.alarms
            #expect(alarms.count <= 1, "\(tag) I11 \(s.events)", sourceLocation: sourceLocation)
            #expect(s.events.fallbacks.count <= 1, "\(tag) I12 \(s.events)", sourceLocation: sourceLocation)
            for a in alarms { #expect(!a.ringNow || !prev.alarm.ringing, "\(tag) I1 at \(rel(s))", sourceLocation: sourceLocation) }
            #expect(Checks.i13Violation(s.view) == nil, "\(tag) I13 at \(rel(s))", sourceLocation: sourceLocation)
            #expect((s.view.snoozeUntilMs != nil) == (s.view.phase == .snoozed), "\(tag) C16 at \(rel(s))", sourceLocation: sourceLocation)
            prev = s.state
        }
        #expect(events(steps).filter(isOvershoot).count <= 1, "\(tag) I6", sourceLocation: sourceLocation)
    }

    static func note(_ key: String, _ text: String) { U127Log.shared.note(key, text) }

    /// Index and pastM of the first Overshoot (required).
    static func overshootAt(_ steps: [Step], _ tag: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> (Int, Int) {
        let i = try #require(steps.firstIndex { $0.events.contains(where: isOvershoot) }, "\(tag): no Overshoot",
                             sourceLocation: sourceLocation)
        let o = KW.overshoots(steps[i].events)
        #expect(o.count == 1, "\(tag)", sourceLocation: sourceLocation)
        return (i, o[0].pastM)
    }

    // MARK: - (a) (b) (c)

    @Test("U127 a b c after a GPS_LOST alarm the chord proves came near and the usual overshoot rule re-rings, Overshoot only, or supersedes the snooze")
    func u127abc() throws {
        let n = Self.n
        // (a) ALARMING, the chime stopped by itself. T10.7 round 2 (C31): minD stays observed, the chord goes to alarmedChordD.
        let a0 = Self.gapState(ringing: false)
        let a = Self.drive(a0, Self.away())
        Self.invariants(a0, a, "a")
        let first = try #require(a.first)
        #expect(KW.hasRecovered(first), "a first fix \(first.events)")
        #expect(!first.events.contains { Self.isAlarm($0) || Self.isOvershoot($0) }, "a first fix \(first.events)")
        #expect(try #require(first.state.minD) >= 3_099.0, "a minD \(KW.kdOpt(first.state.minD)) (not lowered by the chord)")
        #expect(try #require(first.state.alarmedChordD) <= 1.0, "a alarmedChordD \(KW.kdOpt(first.state.alarmedChordD))")
        #expect(!first.state.minDChord, "a minDChord")
        #expect(first.state.stopStartMs == nil, "a stopStartMs as before the Step")
        #expect(first.state.passAnchorD == nil, "a passAnchorD")
        let (ia, pastA) = try Self.overshootAt(a, "a")
        #expect(a[ia].state.nowMs == n + Self.u127AtMs, "a: Overshoot once dSmooth − minD (observed) >= 1 000")
        #expect(pastA == Self.u127PastM, "a pastM \(pastA)")
        let alA = try #require(a[ia].events.alarms.first)
        #expect(a[ia].events.alarms.count == 1)
        #expect(alA.reason == .overshoot)
        #expect(alA.ringNow, "a re-ring")
        #expect(Self.events(a).alarms.count == 1, "a: one Alarm")
        #expect(Self.events(a).fallbacks.isEmpty, "a: \(Self.events(a).fallbacks)")
        #expect(a.last?.state.phase == .overshot)
        Self.note("a", "Alarm(OVERSHOOT, ringNow=true)+Overshoot at n+\(Self.rel(a[ia])) s pastM=\(pastA)")

        // (b) ALARMING, the chime still rings: Overshoot only (screen 8), no double ring.
        let b0 = Self.gapState(ringing: true)
        let b = Self.drive(b0, Self.away())
        Self.invariants(b0, b, "b")
        let (ib, pastB) = try Self.overshootAt(b, "b")
        #expect(ib == ia, "b: same Step as (a)")
        #expect(pastB == pastA, "b pastM")
        #expect(Self.events(b).alarms.isEmpty, "b: \(Self.events(b).alarms)")
        #expect(b.last?.state.phase == .overshot)
        #expect(b.last?.state.alarm.ringing == true, "b: still ringing")
        Self.note("b", "Overshoot only at n+\(Self.rel(b[ib])) s pastM=\(pastB)")

        // (c) SNOOZED until n + 120 s (T10.7 round 2: the re-ring is at n + 65 s, so the snooze is longer than in round 1 to keep
        // the intent: still SNOOZED at the overshoot): Alarm(OVERSHOOT) + Overshoot + SUPERSEDED, no SNOOZE_END later.
        let p = EngineParams.defaults
        let until = n + 120_000
        var c0 = Self.gapState(.snoozed)
        var ca = Self.alarmed(false)
        ca.snoozeCount = 1
        ca.snoozeUntilMs = until
        c0.alarm = ca
        c0.fallback = FallbackState(targetAtMs: until + TMath.ms(p.fallbackLagS), emittedAtMs: n - 300_000, status: .confirmed,
                                    confirmedAtMs: n - 299_000, resync: false, near: false)
        let c = Self.drive(c0, Self.away(count: 30))
        Self.invariants(c0, c, "c")
        let (ic, pastC) = try Self.overshootAt(c, "c")
        #expect(ic == ia, "c: same Step as (a)")
        #expect(pastC == pastA, "c pastM")
        let sc = c[ic]
        #expect(sc.state.nowMs < until)
        let alC = try #require(sc.events.alarms.first)
        #expect(sc.events.alarms.count == 1)
        #expect(alC.reason == .overshoot)
        #expect(alC.ringNow)
        let facC = try #require(sc.events.fallbacks.first)
        #expect(sc.events.fallbacks.count == 1)
        #expect(facC.fallbackAtMs == nil)
        #expect(facC.cause == .superseded)
        #expect(sc.state.phase == .overshot)
        #expect(sc.state.alarm.snoozeUntilMs == nil, "c snoozeUntilMs (C16)")
        #expect(!Self.events(c).alarms.contains { $0.reason == .snoozeEnd }, "c: no SNOOZE_END")
        #expect(try #require(c.last).state.nowMs > until, "c: driven past snoozeUntil")
        Self.note("c", "SNOOZED: Alarm(OVERSHOOT, ringNow=true)+Overshoot+SUPERSEDED at n+\(Self.rel(sc)) s pastM=\(pastC)")
    }

    // MARK: - (d)

    @Test("U127 d a vehicle parked beyond the destination after the chime stopped does not re-ring, MISSED after alarmMaxActiveS")
    func u127d() throws {
        let n = Self.n
        let p = EngineParams.defaults
        let st0 = Self.gapState(ringing: false)
        let endAt = try #require(st0.alarm.lastRingAtMs) + TMath.ms(p.alarmMaxActiveS)
        let count = Int((endAt + 10_000 - n) / 5_000) + 1
        // (d1) Doppler 0, acc 8; (d2) acc 80, no Doppler, repeated coordinates (U114 q). First fix as (a).
        for (tag, acc, spd) in [("d1", 8.0, Double?(0.0)), ("d2", 80.0, Double?.none)] {
            let fixes = (0..<count).map { i in
                i == 0 ? Fx(at: n, south: -3_100.0, east: 0.0, spd: 18.0)
                    : Fx(at: n + 5_000 * Int64(i), south: -3_100.0, east: 0.0, spd: spd, acc: acc)
            }
            let steps = Self.drive(st0, fixes)
            Self.invariants(st0, steps, tag)
            let bad = Self.events(steps).filter { Self.isAlarm($0) || Self.isOvershoot($0) }
            #expect(bad.isEmpty, "\(tag): \(bad)")
            let iEnd = try #require(steps.firstIndex { s in s.events.contains { if case .tripEnded = $0 { true } else { false } } },
                                    "\(tag): no TripEnded")
            let chordKept = steps[0..<iEnd].allSatisfy { !$0.state.minDChord && ($0.state.alarmedChordD ?? .infinity) <= 1.0 }
            #expect(chordKept, "\(tag): alarmedChordD until the end")
            let te = try #require(steps[iEnd].events.compactMap { if case let .tripEnded(x) = $0 { x } else { nil } }.first)
            #expect(te.outcome == .missed, "\(tag)")
            #expect(te.endReason == .alarmUnanswered, "\(tag)")
            #expect(steps[iEnd].state.nowMs == endAt, "\(tag): the first Step at or after lastRingAtMs + alarmMaxActiveS")
            Self.note(tag, "parked 3 100 m beyond: no Alarm, no Overshoot; TripEnded(MISSED, ALARM_UNANSWERED) at n+\(Self.rel(steps[iEnd])) s")
        }
    }

    // MARK: - (e)

    /// U114 (i) geometry: fix before the gap 20 km south, 700 s gap; ALARMING after GPS_LOST, chime stopped.
    static func bypassState() -> EngineState {
        let lp = T105GapTests.pt(20_000.0)
        let ld = KW.distToDest(lp)
        let base = KW.trackingState(KW.cfg(.distance, thr: 1000), now: n - 1_000, startedAt: n - 3_000_000, d: ld, ground: 10.0,
                                    closing: 10.0, gps: .lost, lastFixAt: n - 700_000, tier: .dense, maxTripS: 14_400)
        let l = FixRec(fixAtMs: n - 700_000, lat: lp.lat, lng: lp.lng, accM: 8.0, d: ld, groundSample: nil)
        var s = KW.withLast(base, l)
        s.phase = .alarming
        s.alarm = alarmed(false)
        s.fallback = .cleared
        return s
    }

    /// Distance from the bypass start (2 km north / 0.5 km east) to the destination; the line goes through it.
    static let d0 = (2_000.0 * 2_000.0 + 500.0 * 500.0).squareRoot()

    static func lineFix(_ at: Int64, _ r: Double, _ spd: Double) -> Fx { Fx(at: at, south: -2_000.0 * r, east: 500.0 * r, spd: spd) }

    @Test("U127 e bypass entering from the far side after an alarm - no Overshoot while approaching or standing, re-ring once really past")
    func u127e() throws {
        let n = Self.n
        let st0 = Self.bypassState()
        // (e1) approach at 10 m/s through the destination, then away on the same line.
        let e1Fixes = (0..<200).map { i in Self.lineFix(n + 5_000 * Int64(i), 1.0 - 10.0 * 5.0 * Double(i) / Self.d0, i == 0 ? 30.0 : 10.0) }
        let e1 = Self.drive(st0, e1Fixes)
        Self.invariants(st0, e1, "e1")
        let chordMinD = try #require(e1.first?.state.alarmedChordD)
        #expect(!e1[0].state.minDChord && chordMinD < 1_000.0, "e1 chord \(chordMinD)")
        let passI = try #require(e1Fixes.firstIndex { $0.south > 0.0 })   // first fix beyond the destination
        let (io, past) = try Self.overshootAt(e1, "e1")
        #expect(io > passI, "e1: Overshoot at fix \(io) before passing the destination (fix \(passI))")
        let alarm = try #require(e1[io].events.alarms.first)
        #expect(e1[io].events.alarms.count == 1)
        #expect(alarm.reason == .overshoot)
        #expect(alarm.ringNow)
        let minD = try #require(e1[io].state.minD)
        #expect(minD < chordMinD, "e1: minD observed (\(minD)) below the chord (\(chordMinD))")
        #expect(try #require(e1[io].state.dSmooth) - minD >= 1_000.0)
        #expect(io == Self.u127E1Fix, "e1: fix index of the Overshoot")
        Self.note("e1", "chord minD=\(KW.ki(chordMinD)) passed at fix \(passI); Overshoot+Alarm(OVERSHOOT, ringNow=true) at fix \(io) "
                  + "(n+\(Self.rel(e1[io])) s) pastM=\(past)")

        // (e2) as (e1), but the vehicle stands 2 minutes at the first fix before driving on (U114 v rang a wrong OVERSHOOT in TRACKING).
        let stand = (0..<24).map { i in Self.lineFix(n + 5_000 * Int64(i), 1.0, i == 0 ? 30.0 : 0.0) }
        let go = (0..<200).map { i in Self.lineFix(n + 120_000 + 5_000 * Int64(i), 1.0 - 10.0 * 5.0 * Double(i + 1) / Self.d0, 10.0) }
        let e2Fixes = stand + go
        let e2 = Self.drive(st0, e2Fixes)
        Self.invariants(st0, e2, "e2")
        let passI2 = e2Fixes.firstIndex { $0.south > 0.0 } ?? -1
        let io2 = e2.firstIndex { $0.events.contains(where: Self.isOvershoot) } ?? -1
        #expect(io2 < 0 || io2 > passI2, "e2: Overshoot at fix \(io2) while standing / approaching (passed at \(passI2))")
        #expect(io2 == Self.u127E2Fix, "e2: fix index of the Overshoot (measured)")
        #expect(io2 >= 0 && e2[io2].events.alarms.contains { $0.reason == .overshoot && $0.ringNow }, "e2: re-ring with the Overshoot")
        Self.note("e2", "stand 120 s then approach: no Overshoot before passing (fix \(passI2)); first Overshoot at fix \(io2)"
                  + (io2 >= 0 ? " (n+\(Self.rel(e2[io2])) s)" : ""))
    }

    // MARK: - (f)

    @Test("U127 f process killed in the gap, restore RANG - after AlarmSilenced as (a), else as (b), snapshot round trip keeps the chord")
    func u127f() throws {
        let n = Self.n
        let ref = Self.drive(Self.gapState(ringing: false), Self.away())
        let (ia, pastA) = try Self.overshootAt(ref, "a")
        let snap = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(T105GapTests.reproState()))
        let r = TripEngine.restore(snap, nowMs: n - 60_000, info: RestoreInfo(status: .rang, firedAtMs: n - 360_000))
        let fb = try #require(r.events.alarms.first)
        #expect(r.events.alarms.count == 1)
        #expect(fb.reason == .fallback)
        #expect(!fb.ringNow)
        #expect(!r.events.contains { if case .gpsLost = $0 { true } else { false } }, "f: already LOST \(r.events)")
        #expect(r.state.alarm.ringing)

        // (f1) the OS ring stopped by itself: AlarmSilenced, then = (a).
        let s1 = TripEngine.reduce(r.state, .alarmSilenced(atMs: n - 59_000, silencedAtMs: n - 60_000))
        #expect(!s1.state.alarm.ringing)
        let f1 = Self.drive(s1.state, Self.away())
        Self.invariants(s1.state, f1, "f1")
        let (i1, past1) = try Self.overshootAt(f1, "f1")
        #expect(i1 == ia, "f1: same Step as (a)")
        #expect(past1 == pastA, "f1 pastM")
        let al1 = try #require(f1[i1].events.alarms.first)
        #expect(al1.reason == .overshoot && al1.ringNow, "f1 \(al1)")
        #expect(Self.events(f1).alarms.count == 1)
        Self.note("f1", "restore RANG + AlarmSilenced: Alarm(OVERSHOOT, ringNow=true)+Overshoot at n+\(Self.rel(f1[i1])) s pastM=\(past1)")

        // (f2) still ringing: = (b).
        let f2 = Self.drive(r.state, Self.away())
        Self.invariants(r.state, f2, "f2")
        let (i2, past2) = try Self.overshootAt(f2, "f2")
        #expect(i2 == ia, "f2: same Step as (a)")
        #expect(past2 == pastA, "f2 pastM")
        #expect(Self.events(f2).alarms.isEmpty, "f2: \(Self.events(f2).alarms)")
        Self.note("f2", "restore RANG, still ringing: Overshoot only at n+\(Self.rel(f2[i2])) s pastM=\(past2)")

        // (f3) (a) with a snapshot round trip + restore(PENDING) after the Step at n + 5 s: the same (t, events, view) as (a).
        let fixes = Self.away()
        let head = Self.drive(Self.gapState(ringing: false), Array(fixes.prefix(2)))
        let st = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(try #require(head.last).state))
        let headChord = try #require(head.last).state.alarmedChordD
        #expect(Bits.same(headChord, st.alarmedChordD), "f3: alarmedChordD after decode (I8)")
        #expect(st.alarmedChordD != nil)
        let rp = TripEngine.restore(st, nowMs: n + 5_000, info: RestoreInfo(status: .pending))
        #expect(rp.events.isEmpty, "f3 restore PENDING at now: \(rp.events)")
        let tail = Self.drive(rp.state, Array(fixes.dropFirst(2)))
        func line(_ s: Step) -> String {
            "\(s.state.nowMs - n) \(s.events.map { Transcript.event($0, n) }.joined(separator: ", ")) \(Transcript.view(s.view, n))"
        }
        #expect(ref.dropFirst(2).map(line) == tail.map(line), "f3: (t, events, view) as (a)")
        Self.note("f3", "snapshot round trip at n+5 s: \(tail.count) Steps equal to (a)")
    }

    // MARK: - (g) (h) (i) (j) (k)

    @Test("U127 g h i j k not passed, a stop from before the gap kept, OVERSHOT, an IMPLAUSIBLE fix, and the time term")
    func u127ghijk() throws {
        let n = Self.n
        // (g) same side, 5 000 m (U114 h): no chord (u >= 1), no Overshoot.
        let g0 = Self.gapState(ringing: false)
        let gp = T105GapTests.pt(5_000.0)
        let g = TripEngine.reduce(g0, .locationFix(LocationFix(atMs: n, fixAtMs: n, lat: gp.lat, lng: gp.lng, accuracyM: 8.0, speedMps: 0.8)))
        #expect(!g.state.minDChord, "g minDChord")
        #expect(g.state.alarmedChordD == nil, "g alarmedChordD")
        #expect(try #require(g.state.minD) >= 4_999.0, "g minD \(KW.kdOpt(g.state.minD)) (not lowered by a chord)")
        #expect(!g.events.contains { Self.isOvershoot($0) || Self.isAlarm($0) }, "g \(g.events)")

        // (h) a stop in progress before the gap: kept at the chord fix in ALARMING (decision #2), ended by the first MOVING sample.
        let last = try #require(Self.gapState().last)
        var h0 = Self.gapState(ringing: false)
        h0.stopStartMs = n - 1_900_000
        h0.stopAnchor = last
        let h = Self.drive(h0, Self.away())
        Self.invariants(h0, h, "h")
        #expect(h[0].state.stopStartMs == n - 1_900_000, "h: stop kept at the chord fix")
        #expect(try #require(h[0].state.minD) >= 3_099.0 && !h[0].state.minDChord, "h minD \(KW.kdOpt(h[0].state.minD)) (not lowered)")
        #expect(try #require(h[0].state.alarmedChordD) <= 1.0, "h alarmedChordD \(KW.kdOpt(h[0].state.alarmedChordD))")
        #expect(h[1].state.stopStartMs == nil, "h: stop ended by the first MOVING sample")
        var hT = T105GapTests.reproState()
        hT.stopStartMs = n - 1_900_000
        hT.stopAnchor = last
        #expect(TripEngine.reduce(hT, Self.locFix(Self.away()[0])).state.stopStartMs == nil,
                "h control (TRACKING, U114 m): cleared at the chord fix")
        let (ih, pastH) = try Self.overshootAt(h, "h")
        Self.note("h", "stop kept at n+0, ended at n+\(Self.rel(h[1])) s; Overshoot at n+\(Self.rel(h[ih])) s pastM=\(pastH)")

        // (i) OVERSHOT: no chord fix, no new overshoot event (I6).
        var i0 = Self.gapState(ringing: false)
        i0.phase = .overshot
        i0.overshootAtMs = n - 300_000
        i0.overshootPastM = 1_200
        let i = Self.drive(i0, Self.away())
        #expect(i.allSatisfy { !$0.state.minDChord && $0.state.alarmedChordD == nil }, "i minDChord / alarmedChordD")
        #expect(try #require(i.first?.state.minD) >= 3_099.0, "i minD \(KW.kdOpt(i.first?.state.minD))")
        #expect(!Self.events(i).contains { Self.isOvershoot($0) || Self.isAlarm($0) }, "i \(Self.events(i))")

        // (j) one IMPLAUSIBLE fix in the gap (U114 ad): not a chord fix (round 3f kept in ALARMING), silent for 10 minutes (RK20 d).
        let jp = T105GapTests.pt(500_000.0)
        let jump = TripEngine.reduce(Self.gapState(ringing: false),
                                     .locationFix(LocationFix(atMs: n - 1_000_000, fixAtMs: n - 1_000_000, lat: jp.lat, lng: jp.lng,
                                                              accuracyM: 8.0, speedMps: 10.0)))
        #expect(jump.state.rejects.count == 1, "j: IMPLAUSIBLE kept in rejects")
        let j = Self.drive(jump.state, Self.away(count: 120))
        #expect(j.allSatisfy { !$0.state.minDChord && $0.state.alarmedChordD == nil }, "j: no chord fix")
        #expect(!Self.events(j).contains { Self.isOvershoot($0) || Self.isAlarm($0) }, "j \(Self.events(j))")

        // (k1) GPS still OK (Doze, no Step in the gap; U114 k): the time term of gapFix makes it a chord fix, as (a).
        var k0 = Self.gapState(ringing: false)
        k0.gps = .ok
        k0.gpsLostAtMs = nil
        k0.nowMs = n - 1_761_000
        let k = Self.drive(k0, Self.away())
        Self.invariants(k0, k, "k1")
        #expect(!KW.hasRecovered(k[0]), "k1: gps was OK")
        let k1Chord = try #require(k[0].state.alarmedChordD)
        #expect(!k[0].state.minDChord && k1Chord <= 1.0, "k1 alarmedChordD \(KW.kd(k1Chord))")
        let (ik, pastK) = try Self.overshootAt(k, "k1")
        #expect(k[ik].state.nowMs == n + Self.u127AtMs, "k1: as (a)")
        #expect(k[ik].events.alarms.contains { $0.reason == .overshoot && $0.ringNow })
        // (k2) Δt = lostAfterS + 1 s exactly (a DISTANCE alarm whose chime stopped; 400 m before → 1 800 m beyond, 36 m/s).
        let k2State = KW.trackingState(KW.cfg(.distance, thr: 1000), now: n - 61_000, startedAt: n - 3_000_000, d: 400.0, ground: 18.0,
                                       closing: 18.0, lastFixAt: n - 61_000, tier: .dense, phase: .alarming, maxTripS: 14_400,
                                       alarm: Self.alarmed(false, at: n - 120_000, reason: .distance))
        #expect(GpsMonitor.lostAfterS(k2State) == 60)
        let k2 = Self.drive(k2State, Self.away(past: 1_800.0))
        Self.invariants(k2State, k2, "k2")
        let k2Chord = try #require(k2[0].state.alarmedChordD)
        #expect(!k2[0].state.minDChord && k2Chord <= 1.0, "k2 alarmedChordD \(KW.kd(k2Chord))")
        let (ik2, pastK2) = try Self.overshootAt(k2, "k2")
        #expect(k2[ik2].state.nowMs == n + Self.u127K2AtMs, "k2: measured (designer by hand ≈ n + 35 s)")
        #expect(k2[ik2].events.alarms.contains { $0.reason == .overshoot && $0.ringNow })
        Self.note("k", "k1 Overshoot at n+\(Self.rel(k[ik])) s pastM=\(pastK); k2 (dt = lostAfterS + 1 s) Overshoot at n+\(Self.rel(k2[ik2])) s "
                  + "pastM=\(pastK2)")
    }

    // MARK: - (m) (n) T10.7 round 2

    /// U127 (m) (T10.7 round 2 §7, the unit version of U128 L4): after the GPS_LOST alarm (chime stopped) the chord passes through
    /// the destination (dChord ≈ 0) while the vehicle drives a loop around it at 3 100 m, 18 m/s, uniform noise ±5 m per axis
    /// (splitmix64 seed 127, `Mix`) for 10 minutes; then it heads straight for the destination and 2 km past it. No Overshoot
    /// until the vehicle is really past; then Overshoot + Alarm(OVERSHOOT, ringNow=true) within 120 s.
    @Test("U127 m after an alarm a chord through the destination then a loop around it at 3 100 m - no Overshoot until really past")
    func u127m() throws {
        let n = Self.n
        let st0 = Self.gapState(ringing: false)
        var rnd = Mix(127)
        let r0 = 3_100.0
        let v = 18.0
        let loopS = 600
        var fixes: [Fx] = []
        var truth: [Double] = []   // signed distance along the way in: > 0 before the destination
        func add(_ atS: Int, _ x: Double, _ y: Double, _ d: Double) {
            let nx = rnd.dbl(-5.0, 5.0)
            let ny = rnd.dbl(-5.0, 5.0)
            fixes.append(Fx(at: n + Int64(atS) * 1000, south: -(y + ny), east: x + nx, spd: v))
            truth.append(d)
        }
        var t = 0
        while t <= loopS {
            let th = Double.pi / 2 - v * Double(t) / r0
            add(t, r0 * cos(th), r0 * sin(th), r0)
            t += 5
        }
        let thEnd = Double.pi / 2 - v * Double(loopS) / r0
        var k = 1
        while r0 - v * 5.0 * Double(k) >= -2_000.0 {
            let r = r0 - v * 5.0 * Double(k)
            add(loopS + 5 * k, r * cos(thEnd), r * sin(thEnd), r)
            k += 1
        }
        let steps = Self.drive(st0, fixes)
        Self.invariants(st0, steps, "m")
        let chord = try #require(steps.first?.state.alarmedChordD)
        #expect(chord <= 10.0, "m chord (noise ±5 m) \(chord)")
        let passI = try #require(truth.firstIndex { $0 <= 0.0 })
        let io = try #require(steps.firstIndex { $0.events.contains(where: Self.isOvershoot) }, "m: no Overshoot")
        #expect(io > passI, "m: Overshoot at fix \(io) before the destination was passed (fix \(passI), truth \(truth[io]))")
        let dtS = Double(steps[io].state.nowMs - fixes[passI].at) / 1000.0
        #expect(dtS <= 120.0, "m: Overshoot \(dtS) s after passing")
        #expect(steps[io].events.alarms.contains { $0.reason == .overshoot && $0.ringNow }, "m: re-ring")
        let pastM = try #require(KW.overshoots(steps[io].events).first).pastM
        Self.note("m", "loop 600 s at 3 100 m (±5 m): no Overshoot; passed at fix \(passI) (n+\((fixes[passI].at - n) / 1000) s); "
                  + "Overshoot+Alarm(OVERSHOOT, ringNow=true) at fix \(io) (+\(KW.ki(dtS)) s) pastM=\(pastM)")
    }

    /// U127 (n) (I8): round trip + restore(PENDING) after every Step of (a) (alarmedChordD in the snapshot) continues as (a).
    @Test("U127 n snapshot round trip and restore PENDING after any Step of (a) continues the same (t, events, view)")
    func u127n() throws {
        let n = Self.n
        let fixes = Self.away()
        let ref = Self.drive(Self.gapState(ringing: false), fixes)
        func line(_ s: Step) -> String {
            "\(s.state.nowMs - n) \(s.events.map { Transcript.event($0, n) }.joined(separator: ", ")) \(Transcript.view(s.view, n))"
        }
        let want = ref.map(line)
        for k in 0..<(ref.count - 1) {
            let st = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(ref[k].state))
            #expect(st == ref[k].state, "n: decode after Step \(k)")
            let rp = TripEngine.restore(st, nowMs: st.nowMs, info: RestoreInfo(status: .pending))
            #expect(rp.events.isEmpty, "n restore PENDING at now after Step \(k): \(rp.events)")
            #expect(Array(want.dropFirst(k + 1)) == Self.drive(rp.state, Array(fixes.dropFirst(k + 1))).map(line), "n: after Step \(k)")
        }
        #expect(ref[1].state.alarmedChordD != nil)
        Self.note("n", "round trip + restore PENDING after each of \(ref.count - 1) Steps: equal to (a)")
    }

    // MARK: - U129

    @Test("U129 alarmedChordD is written right after passAnchorD, round-trips, a missing key reads nil and a wrong type fails")
    func u129() throws {
        for chord in [Double?.none, 4.131000057, 0.1, Double.leastNonzeroMagnitude, 1_234.5] {
            var st = KW.trackingState()
            st.passAnchorD = 7.25
            st.alarmedChordD = chord
            let json = TripEngine.encodeSnapshot(st)
            // Swift writes the shortest round-trip digits (`description`); Kotlin writes `Double.toString` (5e-324 → 4.9E-324).
            let lit = chord.map { "\($0)" } ?? "null"
            #expect(json.contains("\"passAnchorD\":7.25,\"alarmedChordD\":\(lit),\"last3\""), "\(json)")
            let back = try TripEngine.decodeSnapshot(json)
            #expect(back == st)
            #expect(Bits.same(back.alarmedChordD, chord))
            // Third named exception to C20: an older snapshot without the key reads nil.
            let without = json.replacingOccurrences(of: ",\"alarmedChordD\":\(lit)", with: "")
            #expect(!without.contains("alarmedChordD"))
            var expected = st
            expected.alarmedChordD = nil
            #expect(try TripEngine.decodeSnapshot(without) == expected)
            for wrong in ["\"1\"", "true", "1e999"] {
                let w = json.replacingOccurrences(of: "\"alarmedChordD\":\(lit)", with: "\"alarmedChordD\":\(wrong)")
                #expect(throws: SnapshotError.self) { try TripEngine.decodeSnapshot(w) }
            }
        }
    }

    // MARK: - (l)

    /// U127 (l): `isGapFix` truth table (C30), compared with the §2 expression written out here, and `notYet` (only clears the
    /// stop). Rows: phase (6, `TripPhase` order) × overshootAtMs {nil, set} × alarm.atMs {nil, set} × L {nil, present} × gps
    /// {OK, LOST} × Δt {5 s, lostAfterS}; one line each in `u127.txt` (byte-identical to Kotlin).
    @Test("U127 l isGapFix truth table over phase, overshootAtMs, alarm, L, gps and the time term")
    func u127l() {
        let n = Self.n
        let p = EngineParams.defaults
        let pol = SamplingPlanner.policyFor(.dense, p, maxSaving: false)
        var base = EngineState.initial(config: KW.cfg(), params: p, nowMs: n)
        base.policy = pol
        base.policyIntervalAtLastFixS = pol.intervalS
        let lostS = GpsMonitor.lostAfterS(base)
        let f = FixRec(fixAtMs: n, lat: 0.0, lng: KW.destLng, accM: 8.0, d: 1.0, groundSample: nil)
        var rows: [String] = []
        var trueRows = 0
        for phase in TripPhase.allCases { for ov in [Int64?.none, n - 1] { for al in [Int64?.none, n - 2] { for hasL in [false, true] {
            for gps in [GpsStatus.ok, .lost] { for dtS in [5, lostS] {
                let l = hasL ? FixRec(fixAtMs: n - Int64(dtS) * 1000, lat: -0.01, lng: KW.destLng, accM: 8.0, d: 1_000.0, groundSample: nil) : nil
                var s = base
                s.phase = phase
                s.overshootAtMs = ov
                s.alarm.atMs = al
                s.gps = gps
                s.last = l
                let got = OvershootDetector.isGapFix(s, l: l, f: f)
                let inPhase = phase == .acquiring || phase == .tracking || phase == .alarming || phase == .snoozed
                let want = hasL && inPhase && ov == nil && (gps == .lost || dtS >= lostS)
                let notYet = (phase == .acquiring || phase == .tracking) && al == nil
                #expect(got == want, "isGapFix phase=\(phase.jsonName) overshoot=\(String(describing: ov)) alarm=\(String(describing: al)) L=\(hasL) gps=\(gps.jsonName) dt=\(dtS)")
                if got { trueRows += 1 }
                rows.append("phase=\(phase.jsonName) overshoot=\(ov == nil ? "null" : "set") alarm=\(al == nil ? "null" : "set") "
                            + "L=\(hasL ? "yes" : "no") gps=\(gps.jsonName) dt=\(dtS) gapFix=\(got) notYet=\(notYet)")
            } }
        } } } }
        #expect(rows.count == 192)
        #expect(trueRows == 4 * 2 * 3, "gapFix rows: 4 phases × alarm {nil, set} × (LOST any dt, OK dt = lostAfterS)")
        Self.note("l", "lostAfterS=\(lostS) rows=\(rows.count) gapFix=\(trueRows)\n" + rows.map { "  \($0)" }.joined(separator: "\n"))
    }
}
