import Testing
@testable import Trip

@Suite("RestoreTests")
struct RestoreTests {
    /// TRACKING, not alarmed, with a fallback target T; last fix at t = 20 s.
    static func tracking() -> EngineDriver {
        var d = EngineDriver()
        d.drive(from: 0, d0: 40_000, v: 15, count: 5)
        return d
    }

    static func restore(_ s: EngineState, _ now: Int64, _ info: RestoreInfo) -> Step { TripEngine.restore(s, nowMs: now, info: info) }

    @Test("U49 not alarmed, target T: RANG; UNKNOWN after/before T; PENDING; MISSING after/before T; MISSING without target")
    func u49() {
        let d = Self.tracking()
        let s = d.state, t = s.fallback.targetAtMs!, soon = s.nowMs + 5000
        #expect(Self.restore(s, t + 5000, RestoreInfo(status: .rang, firedAtMs: t)).events.alarms.map { [$0.reason == .fallback, $0.ringNow] } == [[true, false]])
        #expect(Self.restore(s, t + 5000, RestoreInfo(status: .unknown)).events.alarms.map { [$0.reason == .fallback, $0.ringNow] } == [[true, false]])
        let un = Self.restore(s, soon, RestoreInfo(status: .unknown))
        #expect(un.events.isEmpty)
        #expect(Self.restore(s, soon, RestoreInfo(status: .pending)).events.isEmpty)
        let mAfter = Self.restore(s, t + 5000, RestoreInfo(status: .missing))
        #expect(mAfter.events.alarms.map { [$0.reason == .fallbackMissed, $0.ringNow] } == [[true, true]])
        #expect(mAfter.events.fallbacks.isEmpty)
        let mBefore = Self.restore(s, soon, RestoreInfo(status: .missing))
        #expect(mBefore.events.fallbacks.map(\.cause) == [.resync])
        var noTarget = s
        noTarget.fallback = .cleared
        #expect(Self.restore(noTarget, soon, RestoreInfo(status: .missing)).events.fallbacks.map(\.cause) == [.resync])
    }

    @Test("U50 alarmed snapshot (ALARMING, ringing) + RANG / PENDING / MISSING / UNKNOWN → no Alarm(ringNow=true)")
    func u50() {
        let (d, _) = alarmedDriver()
        for st in [FallbackRestoreStatus.rang, .pending, .missing, .unknown] {
            let r = Self.restore(d.state, d.state.nowMs + 10_000, RestoreInfo(status: st, firedAtMs: d.state.nowMs))
            #expect(!r.events.alarms.contains { $0.ringNow }, "\(st)")
        }
    }

    @Test("U75 DISMISSED: (a) TRACKING → Alarm(FALLBACK, false) + TripEnded(DISMISSED, ON_TIME); (b) SNOOZED → SNOOZE_END + SNOOZED; (c) ALARMING 2 h → not ALARM_UNANSWERED")
    func u75() {
        let s = Self.tracking().state
        let t = s.fallback.targetAtMs!
        let a = Self.restore(s, t + 120_000, RestoreInfo(status: .dismissed, firedAtMs: t, dismissedAtMs: t + 60_000))
        #expect(a.events.alarms.map { [$0.reason == .fallback, $0.ringNow] } == [[true, false]])
        let ea = a.events.compactMap(\.asEnded).first
        #expect(ea?.endReason == .dismissed && ea?.outcome == .onTime && ea?.summary.dismissedAtMs == t + 60_000)
        #expect(a.events.fallbacks == [TripEvent.FallbackAlarmChanged(atMs: t + 120_000, fallbackAtMs: nil, cause: .tripEnded)])
        var (b, tb) = alarmedDriver()
        b.user(tb, .snooze)
        let rb = Self.restore(b.state, b.ms(tb + 200), RestoreInfo(status: .dismissed, firedAtMs: b.ms(tb + 90), dismissedAtMs: b.ms(tb + 100)))
        #expect(rb.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, false]])
        #expect(rb.events.compactMap(\.asEnded).first?.outcome == .snoozed)
        let (c, tc) = alarmedDriver()
        let rc = Self.restore(c.state, c.ms(tc + 7200), RestoreInfo(status: .dismissed))
        let ec = rc.events.compactMap(\.asEnded).first
        #expect(ec?.endReason == .dismissed && ec?.outcome == .onTime && rc.events.alarms.isEmpty)
    }

    @Test("U84 SNOOZED + MISSING before / after / within 30 s of snoozeUntil; SNOOZED + UNKNOWN due; repeated Tick silent")
    func u84() {
        var (d, ta) = alarmedDriver()
        d.user(ta, .snooze)
        let s = d.state, u = s.alarm.snoozeUntilMs!
        let before = Self.restore(s, u - 10_000, RestoreInfo(status: .missing))
        #expect(before.events == [.fallbackAlarmChanged(.init(atMs: u - 10_000, fallbackAtMs: u + 30_000, cause: .resync))])
        let after = Self.restore(s, u + 30_000, RestoreInfo(status: .missing))
        #expect(after.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, true]] && after.events.fallbacks.isEmpty)
        let within = Self.restore(s, u + 10_000, RestoreInfo(status: .missing))
        #expect(within.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, true]] && within.events.fallbacks.isEmpty)
        let unk = Self.restore(s, u + 40_000, RestoreInfo(status: .unknown))
        #expect(unk.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, false]])
        for st in [before.state, after.state, within.state, unk.state] {
            #expect(TripEngine.reduce(st, .tick(atMs: st.nowMs)).events.isEmpty)
        }
    }

    @Test("U84 (e) R3-1: SNOOZED + MISSING before until → REQUESTED; FallbackScheduled ok → CONFIRMED; at until SNOOZE_END + SUPERSEDED; (f) C6 merged order")
    func u84ef() {
        var (d, ta) = alarmedDriver()
        d.user(ta, .snooze)
        let u = d.state.alarm.snoozeUntilMs!
        d.restore(ta + 50, RestoreInfo(status: .missing))
        #expect(d.view.fallbackAtMs == u + 30_000 && d.view.fallbackStatus == .requested)
        d.feed(.fallbackScheduled(atMs: d.ms(ta + 51), fallbackAtMs: u + 30_000, ok: true))
        #expect(d.view.fallbackStatus == .confirmed)
        d.tick(ta + 60)
        #expect(d.events.alarms.map(\.reason) == [.snoozeEnd] && d.events.fallbacks.map(\.cause) == [.superseded])
        #expect(d.steps.allSatisfy { $0.events.fallbacks.count <= 1 })
        // (f) restore RANG long after the last fix: restore events first, Tick events after, then stable sort (gpsLost before alarm).
        let s = Self.tracking().state
        let t = s.fallback.targetAtMs!
        let r = Self.restore(s, t + 600_000, RestoreInfo(status: .rang, firedAtMs: t))
        #expect(r.events.map(\.fixtureName).prefix(2) == ["gpsLost", "alarm"])
        #expect(r.events.map(\.sortRank) == r.events.map(\.sortRank).sorted())
    }
}

@Suite("OsSimTests")
struct OsSimTests {
    @Test("U89 (a) FallbackFired → SNOOZE → SNOOZE_END rings + SUPERSEDED; (b) RANG → silenced → overshoot rings; (c) fallback ringing blocks; (d) no trip-wide flag; (e) P07(i)")
    func u89() {
        // (a)
        var a = EngineDriver()
        a.fix(0, d: 20_000, spd: 15)
        a.fired(10, firedAtMs: a.ms(10))
        var os = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        os.ringing = .fallback
        a.user(20, .snooze)
        #expect(a.view.fallbackStatus == .requested)
        os.react(a.events, nowMs: a.ms(20), t: 20)
        let prevView = a.view
        a.tick(80)
        #expect(prevView.fallbackAtMs == a.ms(110))
        #expect(a.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, true]])
        #expect(a.events.fallbacks.map(\.cause) == [.superseded])
        os.react(a.events, nowMs: a.ms(80), t: 80)
        #expect(os.ringing == .engine && os.violations.isEmpty)
        // (b)
        var b = OvershootDetectorTests.run([3000, 2300, 1600])
        let f = b.view.fallbackAtMs!
        b.restore(100, RestoreInfo(status: .rang, firedAtMs: f))
        b.silenced(101)
        let pv = b.view
        for (i, x) in [900.0, 300, 400, 800, 1350].enumerated() { b.fix(120 + Double(i) * 30, d: x, spd: 11.1) }
        #expect(pv.fallbackAtMs == nil)
        #expect(b.events.alarms.map { [$0.reason == .overshoot, $0.ringNow] } == [[true, true]] && b.events.named("overshoot").count == 1)
        var osb = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        osb.react(b.events, nowMs: b.ms(240), t: 240)
        #expect(osb.ringing == .engine)
        // (c)
        var c = OvershootDetectorTests.run([3000, 2300, 1600])
        var osc = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        osc.ringing = .fallback; osc.ringStartMs = c.ms(85)
        c.fix(95, d: 900, spd: 11.1)
        #expect(c.events.alarms.first?.ringNow == true)
        osc.react(c.events, nowMs: c.ms(95), t: 95)
        #expect(osc.ringing == .fallback && osc.queue == [.fallbackFired(atMs: c.ms(95), firedAtMs: c.ms(85))])
        c.feed(osc.queue.removeFirst())
        #expect(c.events.isEmpty && c.view.alarmRinging)
        // (d)
        var osd = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        osd.ringing = .fallback
        osd.react([.snoozed(.init(atMs: 0, untilMs: 60_000))], nowMs: 0, t: 0)
        osd.react([.alarm(.init(atMs: 60_000, reason: .snoozeEnd, ringNow: true, snoozeAllowed: false, distanceM: nil, etaS: nil, batteryPct: nil))], nowMs: 60_000, t: 60)
        #expect(osd.ringing == .engine && osd.queue.isEmpty)
        // (e)
        var ose = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        ose.ringing = .engine
        ose.react([.alarm(.init(atMs: 1, reason: .overshoot, ringNow: true, snoozeAllowed: false, distanceM: nil, etaS: nil, batteryPct: nil))], nowMs: 1, t: 0)
        #expect(ose.violations.count == 1 && ose.violations[0].hasPrefix("P07(i)"))
    }

    @Test("S13 osSim queue is FIFO; FallbackScheduled(x) → CONFIRMED; P07(ii) checked after the queue; no records after ENDED")
    func s13() throws {
        var os = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        os.ringing = .fallback; os.ringStartMs = 5; os.fbOs = 99
        os.react([.alarm(.init(atMs: 10, reason: .distance, ringNow: true, snoozeAllowed: true, distanceM: nil, etaS: nil, batteryPct: nil)),
                  .fallbackAlarmChanged(.init(atMs: 10, fallbackAtMs: nil, cause: .superseded))], nowMs: 10, t: 0)
        #expect(os.queue == [.fallbackFired(atMs: 10, firedAtMs: 5)] && os.fbOs == nil && os.ringing == .fallback)
        var o2 = OsSim(enabled: true, osRingMaxS: nil, osDismissOffsetS: nil)
        o2.ringing = .engine
        o2.react([.snoozed(.init(atMs: 0, untilMs: 60_000)), .fallbackAlarmChanged(.init(atMs: 0, fallbackAtMs: 90_000, cause: .snooze))], nowMs: 0, t: 0)
        #expect(o2.ringing == .none && o2.fbOs == 90_000 && o2.queue == [.fallbackScheduled(atMs: 0, fallbackAtMs: 90_000, ok: true)])
        var (d, ta) = alarmedDriver()
        d.user(ta, .snooze)
        d.feed(.fallbackScheduled(atMs: d.ms(ta), fallbackAtMs: d.ms(ta + 90), ok: true))
        #expect(d.view.fallbackStatus == .confirmed)
        // Runner: TR18 run dismisses at event:snoozed + 80; ticks after that are not recorded.
        let (trace, spec) = try NegativeSweepTests.loadCase("train_hn_dh", "distance_1000_snooze")
        var r = Runner(trace: trace, spec: spec, mode: "all")
        r.runAll()
        let endIdx = r.records.firstIndex { $0.events.contains { $0.fixtureName == "tripEnded" } }!
        #expect(endIdx == r.records.count - 1)
        #expect(r.violations.isEmpty && r.os.violations.isEmpty)
    }
}
