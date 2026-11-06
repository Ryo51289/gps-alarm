import Foundation
import Testing
@testable import Trip

/// `u130.txt` lines by case key (parallel tests; written sorted by key under the lock, so the file is deterministic). Same keys
/// and line format as Kotlin `unit/T108Test.kt` (`build/core-trip/napstop/u130.txt`), compared byte for byte.
final class U130Log: @unchecked Sendable {
    static let shared = U130Log()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func note(_ key: String, _ text: String) {
        lock.lock()
        defer { lock.unlock() }
        lines[key] = text
        Report.shared.write("unit/u130.txt", lines.keys.sorted().map { "\($0): \(lines[$0]!)" }.joined(separator: "\n") + "\n")
    }
}

/// T10 "T10.8" (PO P1, 06/11/2026, C32; Kotlin `unit/T108Test.kt`): in OVERSHOT, `AlarmSilenced` while `ringing == true` and
/// `alarm.lastReason ≠ OVERSHOOT` rings `Alarm(OVERSHOOT, ringNow=true)` once and marks the ring (U130–U132 of "T10.8" §3),
/// unless alarmMaxActiveS since the last ring is over (same expression as step 3, `lastRingAtMs` before `markRing`).
/// Base trip = OvershootDetectorTest U34 (Kotlin world `KW`: start S, destination (0, 106)): DISTANCE 1000, fixes every 60 s at
/// 40 km/h, the vehicle passes the destination while the DISTANCE alarm still rings (overshoot at t = 420 s with `Overshoot` only),
/// the OS ring stops at t = 425 s (inputs come within 60 s of the last fix so that no GpsLost joins the Step).
/// Report: `unit/u130.txt` (times relative to the trip start, transcript encoding of T12 §9.2; no coordinates).
/// Also: tester T12.5 X1 (a pre-T10.8 snapshot) and the I15 harness self-check (Kotlin `HarnessSelfTest`).
@Suite("T108Tests")
struct T108Tests {
    static let S = KW.S
    static let v40 = 40 / 3.6
    static let approach: [Double] = [3000.0, 2300.0, 1600.0, 900.0, 300.0]
    static let away: [Double] = [400.0, 800.0, 1350.0]
    static let overshootT = 420
    static let silencedT = 425
    static let maxActiveMs = TMath.ms(EngineParams.defaults.alarmMaxActiveS)

    static func ms(_ t: Int) -> Int64 { S + Int64(t) * 1000 }

    static func fixIn(_ t: Int, _ d: Double) -> EngineInput {
        let p = KW.pointOnMeridian(d)
        return .locationFix(LocationFix(atMs: ms(t), fixAtMs: ms(t), lat: p.lat, lng: p.lng, accuracyM: 8.0, speedMps: v40))
    }

    static func silencedIn(_ atMs: Int64) -> EngineInput { .alarmSilenced(atMs: atMs, silencedAtMs: atMs) }

    /// U130 (a) up to the overshoot Step: 8 fixes, 60 s apart.
    static let toOvershoot: [EngineInput] = (approach + away).enumerated().map { fixIn(60 * $0.offset, $0.element) }

    static func startStep(thr: Int = 1000) -> Step {
        try! TripEngine.start(config: KW.cfg(.distance, thr: thr), params: .defaults, nowMs: S)
    }

    /// Kotlin `EngineDriver(cfg(DISTANCE, thr))`: the start Step is recorded.
    static func driver(thr: Int = 1000) -> KDriver {
        let st = startStep(thr: thr)
        var d = KDriver(from: st.state)
        d.steps = [st]
        return d
    }

    static func drive(_ from: EngineState, _ inputs: [EngineInput]) -> [Step] {
        var s = from
        return inputs.map { x in
            let step = TripEngine.reduce(s, x)
            s = step.state
            return step
        }
    }

    static func overshoots(_ s: Step) -> [TripEvent.Overshoot] { KW.overshoots(s.events) }

    static func ended(_ s: Step) -> [TripEvent.TripEnded] { s.events.compactMap(\.asEnded) }

    /// Driver at the overshoot Step of (a): OVERSHOT entered while the DISTANCE alarm rings (asserted).
    static func overshotWhileRinging(sourceLocation: SourceLocation = #_sourceLocation) -> KDriver {
        var e = driver()
        for x in toOvershoot { e.feed(x) }
        let ov = e.steps[e.steps.count - 1]
        #expect(ov.state.nowMs == ms(overshootT), sourceLocation: sourceLocation)
        #expect(overshoots(ov).count == 1, "precondition: Overshoot at t = \(overshootT)", sourceLocation: sourceLocation)
        #expect(ov.events.alarms.isEmpty, "precondition: no Alarm with the Overshoot (ringing)", sourceLocation: sourceLocation)
        #expect(ov.view.phase == .overshot, sourceLocation: sourceLocation)
        #expect(ov.state.alarm.ringing, sourceLocation: sourceLocation)
        #expect(ov.state.alarm.lastReason == .distance, sourceLocation: sourceLocation)
        #expect(e.events().alarms.map(\.reason) == [.distance], sourceLocation: sourceLocation)
        return e
    }

    static func overshootAlarms(_ e: KDriver) -> [TripEvent.Alarm] { e.events().alarms.filter { $0.reason == .overshoot } }

    static func note(_ key: String, _ text: String) { U130Log.shared.note(key, text) }

    /// Kotlin `enc(s)`: "t=<s> [<events>]" (seconds truncated, events in the transcript encoding relative to S).
    static func enc(_ s: Step) -> String {
        "t=\((s.state.nowMs - S) / 1000) [\(s.events.map { Transcript.event($0, S) }.joined(separator: ","))]"
    }

    // MARK: - U130

    @Test("U130 a ALARMING ringing, overshoot, AlarmSilenced rings OVERSHOOT once and marks the ring, b second AlarmSilenced is silent")
    func u130ab() throws {
        var e = Self.overshotWhileRinging()
        let ring1 = try #require(e.state.alarm.lastRingAtMs)
        let firstAt = e.state.alarm.atMs
        let a = e.feed(Self.silencedIn(Self.ms(Self.silencedT)))
        let v = a.view
        #expect(a.events == [.alarm(.init(atMs: Self.ms(Self.silencedT), reason: .overshoot, ringNow: true, snoozeAllowed: false,
                                          distanceM: v.distanceM, etaS: v.etaS, batteryPct: v.batteryPct))])
        #expect(a.state.alarm.lastReason == .overshoot)
        #expect(a.state.alarm.lastRingAtMs == Self.ms(Self.silencedT))
        #expect(a.state.alarm.ringing)
        #expect(v.alarmRinging)
        #expect(v.phase == .overshot)
        // The first alarm of the trip (atMs, reason, source) is unchanged; the overshoot itself is not re-reported.
        #expect(a.state.alarm.atMs == firstAt)
        #expect(a.state.alarm.reason == .distance)
        #expect(a.state.overshootAtMs == Self.ms(Self.overshootT))
        #expect(ring1 < Self.ms(Self.silencedT))
        // (b) the overshoot ring stops too: nothing, ringing = false.
        let b = e.feed(Self.silencedIn(Self.ms(Self.silencedT + 5)))
        #expect(b.events.isEmpty, "b: \(b.events)")
        #expect(!b.state.alarm.ringing)
        #expect(b.state.alarm.lastReason == .overshoot)
        #expect(b.state.alarm.lastRingAtMs == Self.ms(Self.silencedT))
        #expect(Self.overshootAlarms(e).count == 1)
        let lr = try #require(a.state.alarm.lastRingAtMs)
        Self.note("a", Self.enc(a) + " lastRingAtMs=\((lr - Self.S) / 1000) ringing=\(a.state.alarm.ringing)")
        Self.note("b", Self.enc(b) + " ringing=\(b.state.alarm.ringing)")
    }

    @Test("U130 c TRACKING overshoot already rang OVERSHOOT, AlarmSilenced is silent")
    func u130c() {
        var e = Self.driver(thr: 500)
        for (i, d) in [900.0, 800.0, 1100.0, 2000.0].enumerated() { e.feed(Self.fixIn(180 * i, d)) }
        #expect(e.view.phase == .overshot)
        #expect(e.steps[e.steps.count - 1].events.alarms.map(\.reason) == [.overshoot])
        let s = e.feed(Self.silencedIn(Self.ms(545)))
        #expect(s.events.isEmpty, "c: \(s.events)")
        #expect(!s.state.alarm.ringing)
        #expect(Self.overshootAlarms(e).count == 1)
        Self.note("c", Self.enc(s))
    }

    @Test("U130 d ALARMING not ringing, overshoot rings (PO 18), AlarmSilenced is silent")
    func u130d() {
        var e = Self.driver()
        for (i, d) in Self.approach.enumerated() { e.feed(Self.fixIn(60 * i, d)) }
        e.feed(Self.silencedIn(Self.ms(300)))
        for (i, d) in Self.away.enumerated() { e.feed(Self.fixIn(305 + 60 * i, d)) }
        let ov = e.steps[e.steps.count - 1]
        #expect(Self.overshoots(ov).count == 1)
        #expect(ov.events.alarms.map(\.reason) == [.overshoot])
        let s = e.feed(Self.silencedIn(Self.ms(430)))
        #expect(s.events.isEmpty, "d: \(s.events)")
        #expect(Self.overshootAlarms(e).count == 1)
        Self.note("d", Self.enc(s))
    }

    @Test("U130 e FallbackFired in OVERSHOT before AlarmSilenced does not count as the overshoot ring")
    func u130e() {
        var e = Self.overshotWhileRinging()
        let f = e.feed(.fallbackFired(atMs: Self.ms(422), firedAtMs: Self.ms(422)))
        #expect(f.events.isEmpty, "e fired: \(f.events)")
        #expect(f.state.alarm.lastReason == .distance)
        let s = e.feed(Self.silencedIn(Self.ms(Self.silencedT)))
        #expect(s.events.alarms.map(\.reason) == [.overshoot])
        #expect(s.events.alarms.map(\.ringNow) == [true])
        #expect(e.feed(Self.silencedIn(Self.ms(Self.silencedT + 5))).events.isEmpty)
        #expect(Self.overshootAlarms(e).count == 1)
        Self.note("e", Self.enc(s))
    }

    @Test("U130 f DISMISS before AlarmSilenced ends the trip, no ring")
    func u130f() {
        var e = Self.overshotWhileRinging()
        let d = e.feed(.userAction(atMs: Self.ms(422), action: .dismiss))
        #expect(Self.ended(d).map(\.endReason) == [.dismissed])
        let s = e.feed(Self.silencedIn(Self.ms(Self.silencedT)))
        #expect(s.events.isEmpty, "f: \(s.events)")
        #expect(s.view.phase == .ended)
        #expect(Self.overshootAlarms(e).isEmpty)
        Self.note("f", Self.enc(s))
    }

    @Test("U130 g AlarmSilenced at lastRingAtMs + alarmMaxActiveS ends ALARM_UNANSWERED without a ring, g2 1 ms earlier it rings")
    func u130g() throws {
        var e = Self.overshotWhileRinging()
        let ring1 = try #require(e.state.alarm.lastRingAtMs)
        let g = e.feed(Self.silencedIn(ring1 + Self.maxActiveMs))
        #expect(g.events.alarms.isEmpty, "g: \(g.events)")
        let end = Self.ended(g)
        #expect(end.map(\.endReason) == [.alarmUnanswered])
        #expect(end.map(\.outcome) == [.missed])
        #expect(g.view.phase == .ended)
        var e2 = Self.overshotWhileRinging()
        let g2 = e2.feed(Self.silencedIn(ring1 + Self.maxActiveMs - 1))
        #expect(g2.events.alarms.map(\.reason) == [.overshoot])
        #expect(Self.ended(g2).isEmpty)
        #expect(g2.state.alarm.lastRingAtMs == ring1 + Self.maxActiveMs - 1)
        Self.note("g", Self.enc(g))
        Self.note("g2", Self.enc(g2))
    }

    // MARK: - U131

    @Test("U131 alarmMaxActiveS counts from the overshoot ring")
    func u131() throws {
        var e = Self.overshotWhileRinging()
        let ring1 = try #require(e.state.alarm.lastRingAtMs)
        e.feed(Self.silencedIn(Self.ms(Self.silencedT)))
        let ring2 = try #require(e.state.alarm.lastRingAtMs)
        #expect(ring2 == Self.ms(Self.silencedT))
        #expect(Self.ended(e.tickMs(ring1 + Self.maxActiveMs)).isEmpty, "old mark must not end the trip")
        #expect(Self.ended(e.tickMs(ring2 + Self.maxActiveMs - 1)).isEmpty)
        let end = e.tickMs(ring2 + Self.maxActiveMs)
        #expect(Self.ended(end).map(\.endReason) == [.alarmUnanswered])
        #expect(e.events().alarms.map(\.reason) == [.distance, .overshoot])
        Self.note("u131", Self.enc(end))
    }

    // MARK: - U132

    static func line(_ s: Step) -> String {
        "\(s.state.nowMs - S) \(s.events.map { Transcript.event($0, S) }.joined(separator: ", ")) \(Transcript.view(s.view, S))"
    }

    static func snapshotKeys(_ s: EngineState) throws -> [String] {
        let re = try Regex("\"([A-Za-z0-9]+)\":")
        return TripEngine.encodeSnapshot(s).matches(of: re).map { String($0.output[1].substring ?? "") }
    }

    @Test("U132 snapshot round trip and restore PENDING after any Step of (a) continues the same, no new snapshot key")
    func u132() throws {
        let inputs = Self.toOvershoot + [Self.silencedIn(Self.ms(Self.silencedT)), Self.silencedIn(Self.ms(Self.silencedT + 5)),
                                         .tick(atMs: Self.ms(Self.silencedT + 60))]
        let start = Self.startStep()
        let ref = [start] + Self.drive(start.state, inputs)
        let want = ref.map(Self.line)
        let reRing = ref[Self.toOvershoot.count + 1]
        #expect(reRing.events.alarms.map(\.reason) == [.overshoot])
        for k in 0..<(ref.count - 1) {
            let st = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(ref[k].state))
            #expect(st == ref[k].state, "decode after Step \(k)")
            let rp = TripEngine.restore(st, nowMs: st.nowMs, info: RestoreInfo(status: .pending))
            #expect(rp.events.isEmpty, "restore PENDING at now after Step \(k): \(rp.events)")
            #expect(Array(want.dropFirst(k + 1)) == Self.drive(rp.state, Array(inputs.dropFirst(k))).map(Self.line), "after Step \(k)")
        }
        // The rule reads phase, alarm.lastReason and alarm.ringing only: the snapshot keys are those of the Step before.
        #expect(try Self.snapshotKeys(ref[Self.toOvershoot.count].state) == Self.snapshotKeys(reRing.state))
        Self.note("u132", "round trip + restore PENDING after each of \(ref.count - 1) Steps: equal; snapshot keys unchanged")
    }

    // MARK: - tester T12.5 X1 (Kotlin `TesterT125Test.X1`)

    @Test("T125 X1 pre-T10.8 snapshot, chime already stopped in OVERSHOT - AlarmSilenced is silent, a later fallback ring re-rings OVERSHOOT once")
    func x1OldSnapshot() throws {
        let e = Self.overshotWhileRinging()
        // What the engine before T10.8 left after AlarmSilenced at 425: OVERSHOT, ringing = false, lastReason = DISTANCE.
        var old = e.state
        old.nowMs = Self.ms(425)
        old.alarm.ringing = false
        let st = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(old))
        let r = TripEngine.restore(st, nowMs: Self.ms(600), info: RestoreInfo(status: .pending))
        #expect(r.events.alarms.isEmpty, "restore: \(r.events)")
        #expect(r.view.phase == .overshot)
        var e2 = KDriver(from: r.state)
        let s = e2.feed(Self.silencedIn(Self.ms(601)))
        #expect(s.events.isEmpty, "ringing == false: nothing (\(s.events))")
        #expect(!s.state.alarm.ringing)
        #expect(s.state.alarm.lastReason == .distance)
        let f = e2.feed(.fallbackFired(atMs: Self.ms(700), firedAtMs: Self.ms(700)))
        #expect(f.events.alarms.isEmpty, "FallbackFired in OVERSHOT: \(f.events)")
        #expect(f.state.alarm.ringing)
        let s2 = e2.feed(Self.silencedIn(Self.ms(760)))
        #expect(s2.events.alarms.map(\.reason) == [.overshoot], "\(s2.events)")
        #expect(s2.events.alarms.map(\.ringNow) == [true])
        #expect(e2.feed(Self.silencedIn(Self.ms(765))).events.isEmpty)
    }

    // MARK: - I15 harness self-check (Kotlin `HarnessSelfTest` "I15 flags …")

    @Test("I15 flags a second Alarm(OVERSHOOT) and a silent AlarmSilenced after an overshoot while ringing (T10.8)")
    func i15SelfCheck() {
        let view = Self.startStep().view
        let ms = Self.S
        func alarm(_ at: Int64, _ r: AlarmReason, ringNow: Bool = true, snooze: Bool = false) -> TripEvent {
            .alarm(.init(atMs: at, reason: r, ringNow: ringNow, snoozeAllowed: snooze, distanceM: nil, etaS: nil, batteryPct: nil))
        }
        let dist = alarm(ms, .distance, snooze: true)
        let ov = alarm(ms + 10_000, .overshoot)
        let over = TripEvent.overshoot(.init(atMs: ms + 5_000, pastM: 1000))
        func rec(_ t: Int, _ input: EngineInput?, _ ev: [TripEvent]) -> StepRecord {
            StepRecord(t: t, input: input.map { .input($0, fixIndex: nil) } ?? .start, events: ev, view: view, v: "")
        }
        let silenced = Self.silencedIn(ms + 10_000)
        let head = [rec(0, nil, [dist]), rec(5, nil, [over])]
        #expect(Checks.i15(head + [rec(10, silenced, [ov])]).isEmpty)
        let silent = Checks.i15(head + [rec(10, silenced, [])])
        #expect(silent.count == 1 && silent[0].hasPrefix("I15: AlarmSilenced"), "\(silent)")
        let ended = TripEvent.tripEnded(.init(atMs: ms + 10_000, outcome: .missed, endReason: .alarmUnanswered,
                                              summary: TripSummary(startedAtMs: ms, alarmAtMs: ms, alarmReason: .distance,
                                                                   dismissedAtMs: nil, snoozeCount: 0, travelledM: 0,
                                                                   vehicleGuess: .coach)))
        #expect(Checks.i15(head + [rec(10, silenced, [ended])]).isEmpty)
        // Review T12.5 nit 2: a re-ring that does not ring now does not count.
        let late = Checks.i15(head + [rec(10, silenced, [alarm(ms + 10_000, .overshoot, ringNow: false)])])
        #expect(late.count == 1 && late[0].hasPrefix("I15: AlarmSilenced in OVERSHOT without"), "\(late)")
        // Review T12.5 nit 1: the Step that ends the trip (alarmMaxActiveS) must not ring as well.
        let both = Checks.i15(head + [rec(10, silenced, [ov, ended])])
        #expect(both.count == 1 && both[0].hasPrefix("I15: AlarmSilenced Step rings OVERSHOOT and ends"), "\(both)")
        // The wait is only armed by an Overshoot Step without Alarm(OVERSHOOT): after an Overshoot that rang (TRACKING → OVERSHOT,
        // #18) a silent AlarmSilenced is not a failure.
        #expect(Checks.i15([rec(0, nil, [ov, over]), rec(10, silenced, [])]).isEmpty)
        let twice = Checks.i15([rec(0, nil, [ov, over]), rec(10, silenced, []), rec(15, nil, [ov])])
        #expect(twice.count == 1 && twice[0].hasPrefix("I15: 2 Alarm(OVERSHOOT)"), "\(twice)")
        // Through `invariants` too (P03: every main run).
        #expect(Checks.invariants(head + [rec(10, silenced, [])], .defaults).contains { $0.hasPrefix("I15:") })
    }
}
