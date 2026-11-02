import Testing
@testable import Trip

/// DISTANCE 1000 trip driven to its alarm (ALARMING, ringing); returns driver and alarm time (s).
func alarmedDriver(params: String? = nil) -> (EngineDriver, Double) {
    var d = EngineDriver(.distance, thr: 1000, params: params)
    var t = 0.0
    while t < 400 {
        d.fix(t, d: 3000 - 15 * t, spd: 15)
        if !d.events.alarms.isEmpty { return (d, t) }
        t += 5
    }
    return (d, t)
}

@Suite("AlarmLifecycleTests")
struct AlarmLifecycleTests {
    static func noGps(_ e: [TripEvent]) -> [TripEvent] { e.filter { !$0.fixtureName.hasPrefix("gps") } }

    @Test("U45 SNOOZE → Snoozed(now + 60 s) + FallbackAlarmChanged(now + 90 s, SNOOZE); +59 s nothing; +60 s Alarm(SNOOZE_END, ringNow, snoozeAllowed false)")
    func u45() {
        var (d, ta) = alarmedDriver()
        d.user(ta, .snooze)
        #expect(d.events == [.snoozed(.init(atMs: d.ms(ta), untilMs: d.ms(ta + 60))),
                             .fallbackAlarmChanged(.init(atMs: d.ms(ta), fallbackAtMs: d.ms(ta + 90), cause: .snooze))])
        d.tick(ta + 59)
        #expect(Self.noGps(d.events).isEmpty)
        d.tick(ta + 60)
        let a = d.events.alarms
        #expect(a.count == 1 && a[0].reason == .snoozeEnd && a[0].ringNow && !a[0].snoozeAllowed)
    }

    @Test("U45 (b) R3-1: after SNOOZE status REQUESTED; FallbackScheduled(ok=false) → FAILED; other time → unchanged; SNOOZE_END → SUPERSEDED, NONE")
    func u45b() {
        var (d, ta) = alarmedDriver()
        d.user(ta, .snooze)
        #expect(d.view.fallbackAtMs == d.ms(ta + 90) && d.view.fallbackStatus == .requested)
        d.scheduled(ta + 1, d.ms(ta + 90), ok: false)
        #expect(d.view.fallbackStatus == .failed)
        d.scheduled(ta + 2, d.ms(ta + 91), ok: true)
        #expect(d.view.fallbackStatus == .failed)
        d.tick(ta + 60)
        #expect(d.events.fallbacks == [TripEvent.FallbackAlarmChanged(atMs: d.ms(ta + 60), fallbackAtMs: nil, cause: .superseded)])
        #expect(d.view.fallbackAtMs == nil && d.view.fallbackStatus == .notSet)
    }

    @Test("U46 after SNOOZE_END a second SNOOZE is ignored (maxSnoozes 1), still ALARMING")
    func u46() {
        var (d, ta) = alarmedDriver()
        d.user(ta, .snooze); d.tick(ta + 60)
        d.user(ta + 61, .snooze)
        #expect(d.events.isEmpty && d.view.phase == .alarming)
    }

    @Test("U47 outcomes ON_TIME / SNOOZED / MISSED / CANCELLED; summary alarmAtMs = first Alarm, dismissedAtMs = DISMISS (null for STOP)")
    func u47() {
        var (a, ta) = alarmedDriver()
        a.user(ta + 10, .dismiss)
        let ea = a.events.compactMap(\.asEnded).first!
        #expect(ea.outcome == .onTime && ea.endReason == .dismissed && ea.summary.alarmAtMs == a.ms(ta) && ea.summary.dismissedAtMs == a.ms(ta + 10))
        var (b, tb) = alarmedDriver()
        b.user(tb, .snooze); b.tick(tb + 60); b.user(tb + 70, .dismiss)
        #expect(b.events.compactMap(\.asEnded).first?.outcome == .snoozed)
        var c = OvershootDetectorTests.run(OvershootDetectorTests.approachTo300 + [400, 800, 1350])
        c.user(300, .dismiss)
        #expect(c.events.compactMap(\.asEnded).first?.outcome == .missed)
        var s = EngineDriver()
        s.fix(0, d: 20_000)
        s.user(10, .stopTrip)
        let es = s.events.compactMap(\.asEnded).first!
        #expect(es.outcome == .cancelled && es.endReason == .userStop && es.summary.dismissedAtMs == nil && es.summary.alarmAtMs == nil)
    }

    @Test("U48 TRACKING + FallbackFired → Alarm(FALLBACK, ringNow=false), no SUPERSEDED; later fix in zone does not ring")
    func u48() {
        var d = EngineDriver()
        d.fix(0, d: 20_000, spd: 15)
        d.fired(10, firedAtMs: d.ms(10))
        #expect(d.events.alarms.map { [$0.reason == .fallback, $0.ringNow] } == [[true, false]])
        #expect(d.events.fallbacks.isEmpty)
        d.fix(15, d: 900, spd: 15)
        #expect(d.allEvents(from: d.steps.count - 1).alarms.isEmpty)
    }

    @Test("U68 maxSnoozes 2 → snoozeAllowed true, true, false; maxSnoozes 0 → false and SNOOZE ignored")
    func u68() {
        var (d, ta) = alarmedDriver(params: #"{"maxSnoozes": 2}"#)
        var allowed = [d.events.alarms[0].snoozeAllowed]
        d.user(ta, .snooze); d.tick(ta + 60); allowed.append(d.events.alarms[0].snoozeAllowed)
        d.user(ta + 61, .snooze); d.tick(ta + 121); allowed.append(d.events.alarms[0].snoozeAllowed)
        #expect(allowed == [true, true, false])
        var (z, tz) = alarmedDriver(params: #"{"maxSnoozes": 0}"#)
        #expect(z.events.alarms[0].snoozeAllowed == false)
        z.user(tz, .snooze)
        #expect(z.events.isEmpty && z.view.phase == .alarming)
    }

    @Test("U76 (a) TIMEOUT at startedAt + maxTripDurationS; (b) never a fix → TIMEOUT at 4 h, distanceM null; (c) then ALARM_UNANSWERED after 3600 s")
    func u76() {
        var a = EngineDriver()
        var t = 0.0
        while t < 14_400 { a.fix(t, d: 50_000, spd: 0); #expect(a.events.alarms.isEmpty); t += 60 }
        #expect(a.state.maxTripDurationS == 14_400)
        a.fix(14_400, d: 50_000, spd: 0)
        #expect(a.events.alarms.map(\.reason) == [.timeout] && a.view.phase == .alarming && a.events.alarms[0].ringNow)
        a.tick(14_400 + 3599)
        #expect(a.events.compactMap(\.asEnded).isEmpty)
        a.tick(18_000)
        let e = a.events.compactMap(\.asEnded).first
        #expect(e?.outcome == .missed && e?.endReason == .alarmUnanswered)
        var b = EngineDriver()
        b.tick(120); b.tick(14_399)
        b.tick(14_400)
        #expect(b.events.alarms.map(\.reason) == [.timeout] && b.view.distanceM == nil)
    }

    @Test("U83 ALARMING (engine) + FallbackFired → no events, alarmRinging; OVERSHOT + FallbackFired → no events")
    func u83() {
        var (d, ta) = alarmedDriver()
        d.silenced(ta + 1)
        #expect(!d.view.alarmRinging)
        d.fired(ta + 2, firedAtMs: d.ms(ta + 2))
        #expect(d.events.isEmpty && d.view.alarmRinging)
        var o = OvershootDetectorTests.run(OvershootDetectorTests.approachTo300 + [400, 800, 1350])
        #expect(o.view.phase == .overshot)
        o.fired(215, firedAtMs: o.ms(215))
        #expect(o.events.isEmpty && o.view.alarmRinging)
    }

    @Test("U88 markRing: (a) clamp + 1 h from the real ring time; (b) overshoot while the fallback rings; (c) SNOOZED; (d) restore RANG/UNKNOWN; (e) ALARMING; (f) future firedAtMs")
    func u88() {
        var a = EngineDriver()
        a.fix(0, d: 20_000, spd: 15)
        let n = a.ms(100)
        a.fired(100, firedAtMs: n - 3000)
        #expect(a.events.alarms.first?.atMs == n && a.view.alarmAtMs == n - 3000 && a.view.alarmRinging)
        a.tick(300)   // absorbs GpsLost
        a.feed(.tick(atMs: n - 3000 + 3_600_000 - 1))
        #expect(a.events.isEmpty)
        a.feed(.tick(atMs: n - 3000 + 3_600_000))
        let e = a.events.compactMap(\.asEnded).first
        #expect(e?.endReason == .alarmUnanswered && e?.outcome == .missed && e?.summary.alarmAtMs == n - 3000)
        // (b)
        var b = OvershootDetectorTests.run([3000, 2300, 1600])
        b.fired(95, firedAtMs: b.ms(95))
        for (i, x) in [900.0, 300, 400, 800, 1350].enumerated() { b.fix(120 + Double(i) * 30, d: x, spd: 11.1) }
        #expect(b.allEvents().alarms.count == 1 && b.events.named("overshoot").count == 1)
        // (c)
        var (c, tc) = alarmedDriver()
        c.user(tc, .snooze)
        let u = c.ms(tc + 60)
        c.feed(.fallbackFired(atMs: u + 30_000, firedAtMs: u + 30_000))
        #expect(c.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, false]] && c.state.alarm.lastRingAtMs == u + 30_000)
        // (d)
        var dd = EngineDriver()
        dd.fix(0, d: 20_000, spd: 15)
        let f = dd.view.fallbackAtMs!
        let snap = dd.state
        let r1 = TripEngine.restore(snap, nowMs: f + 60_000, info: RestoreInfo(status: .rang, firedAtMs: f))
        let r2 = TripEngine.restore(snap, nowMs: f + 60_000, info: RestoreInfo(status: .unknown))
        for r in [r1, r2] { #expect(r.state.alarm.atMs == f && r.state.alarm.lastRingAtMs == f && r.view.alarmRinging) }
        // (e)
        var (ee, te) = alarmedDriver()
        let l = ee.state.alarm.lastRingAtMs!
        ee.feed(.fallbackFired(atMs: ee.ms(te + 20), firedAtMs: l + 10_000))
        #expect(ee.events.isEmpty && ee.state.alarm.lastRingAtMs == l + 10_000)
        // (f)
        var ff = EngineDriver()
        ff.fix(0, d: 20_000, spd: 15)
        ff.fired(50, firedAtMs: ff.ms(55))
        #expect(ff.state.alarm.atMs == ff.ms(50))
    }
}

@Suite("ClockAndHistoryTests")
struct ClockAndHistoryTests {
    @Test("U52 input atMs 10 s back: now does not go back, no fake GpsLost")
    func u52() {
        var d = EngineDriver()
        d.drive(from: 0, d0: 20_000, v: 15, count: 10)
        let now = d.state.nowMs
        d.tick(35)
        #expect(d.state.nowMs == now && d.events.isEmpty)
    }

    @Test("U53 maxTripDurationS: etaS at first fix 1 h / 6 h / 20 h / 30 h → 4 h / 12 h / 40 h / 48 h; no fix → 4 h")
    func u53() {
        let p = EngineParams.defaults
        for (eta, want) in [(3600.0, 14_400), (21_600, 43_200), (72_000, 144_000), (108_000, 172_800)] {
            #expect(ModeRules.maxTripDurationFromFirstFix(makeE(dNow: 1, v: 1, k: 1, eta: eta), p) == want)
        }
        #expect(ModeRules.maxTripDurationFromFirstFix(nil, p) == 14_400)
        #expect(EngineDriver().state.maxTripDurationS == 14_400)
    }

    @Test("U54 vehicleGuess: 22 km/h → BUS; 70 km/h + TRAIN → TRAIN; 70 km/h + UNKNOWN → UNKNOWN")
    func u54() {
        var s = EngineDriver(hint: .train).state
        s.movingTimeS = 1000; s.movingDistM = 22 / 3.6 * 1000
        #expect(ViewBuilder.vehicleGuess(s) == .bus)
        s.movingDistM = 70 / 3.6 * 1000
        #expect(ViewBuilder.vehicleGuess(s) == .train)
        s.config.vehicleHint = .unknown
        #expect(ViewBuilder.vehicleGuess(s) == .unknown)
    }

    @Test("U55 travelledM: (a) Doppler 0 then 10 min of speed-less fixes jittering ≤ 20 m → unchanged; (b) jitter ≤ 6 m, no Doppler 0 → + ≤ 50 m")
    func u55() {
        let jitter20: [Double] = [0, 18, -2, 20, 3, -15, 9, -20, 12, -6]
        var a = EngineDriver()
        a.drive(from: 0, d0: 30_000, v: 15, count: 30)
        let stop = 30_000 - 15.0 * 145 - 10
        a.fix(150, d: stop, spd: 0)
        let tr = a.view.travelledM
        for i in 0..<120 { a.fix(155 + Double(i) * 5, d: stop + jitter20[i % 10], spd: nil) }
        #expect(a.view.travelledM == tr)
        let jitter6: [Double] = [0, 5, -1, 6, 2, -5, 3, -6, 4, -2]
        var b = EngineDriver()
        b.drive(from: 0, d0: 30_000, v: 15, count: 30)
        let stopB = 30_000 - 15.0 * 145 - 5
        let trB = b.view.travelledM
        for i in 0..<120 { b.fix(150 + Double(i) * 5, d: stopB + jitter6[i % 10], spd: nil) }
        #expect(b.view.travelledM - trB <= 50)
    }
}
