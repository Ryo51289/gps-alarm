import Testing
@testable import Trip

/// T10.3 (C16, U98) and Kotlin-parity cases from review T13 round 1 (#3–#7, #9).
@Suite("Round2Tests")
struct Round2Tests {
    /// ALARMING (DISTANCE 1000 approach, alarm at t = 90), then SNOOZE at t = 120 (N). snoozeUntil = N + 60 s.
    static func snoozed() -> (EngineDriver, Double) {
        var d = OvershootDetectorTests.run(OvershootDetectorTests.approachTo300)   // fixes at 0…120, alarm at 90
        d.user(120, .snooze)
        return (d, 120)
    }

    static func cleared(_ s: Step) -> Bool {
        s.view.snoozeUntilMs == nil && s.state.alarm.snoozeUntilMs == nil
            && TripEngine.encodeSnapshot(s.state).contains("\"snoozeUntilMs\":null")
    }

    @Test("U98 C16: snoozeUntilMs is null after every exit from SNOOZED (a)–(h); (i) MISSING before until stays SNOOZED with RESYNC")
    func u98() {
        var (base, n) = Self.snoozed()
        #expect(base.view.snoozeUntilMs == base.ms(n + 60) && base.view.phase == .snoozed)
        let snap = base.state
        // (a) Tick at N + 60 s
        var a = base; a.tick(n + 60)
        #expect(a.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, true]] && Self.cleared(a.last))
        // (b) FallbackFired at N + 30 s
        var b = base; b.fired(n + 30, firedAtMs: b.ms(n + 30))
        #expect(b.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, false]] && Self.cleared(b.last))
        // (c) overshoot while SNOOZED
        var c = base
        c.fix(n + 10, d: 400, spd: 11.1); c.fix(n + 20, d: 800, spd: 11.1); c.fix(n + 30, d: 1350, spd: 11.1)
        #expect(c.events.alarms.map(\.reason) == [.overshoot] && c.events.named("overshoot").count == 1 && Self.cleared(c.last))
        // (d) DISMISS, (e) STOP_TRIP
        var dd = base; dd.user(n + 5, .dismiss); #expect(dd.view.phase == .ended && Self.cleared(dd.last))
        var e = base; e.user(n + 5, .stopTrip); #expect(e.view.phase == .ended && Self.cleared(e.last))
        // (f) RANG, (g) DISMISSED, (h) MISSING after until
        let f = TripEngine.restore(snap, nowMs: base.ms(n + 40), info: RestoreInfo(status: .rang, firedAtMs: base.ms(n + 40)))
        #expect(f.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, false]] && Self.cleared(f))
        let g = TripEngine.restore(snap, nowMs: base.ms(n + 40), info: RestoreInfo(status: .dismissed))
        #expect(g.view.phase == .ended && Self.cleared(g))
        let h = TripEngine.restore(snap, nowMs: base.ms(n + 70), info: RestoreInfo(status: .missing))
        #expect(h.events.alarms.map { [$0.reason == .snoozeEnd, $0.ringNow] } == [[true, true]] && Self.cleared(h))
        // (i) MISSING before until
        let i = TripEngine.restore(snap, nowMs: base.ms(n + 30), info: RestoreInfo(status: .missing))
        #expect(i.view.phase == .snoozed && i.view.snoozeUntilMs == base.ms(n + 60))
        #expect(i.events.fallbacks == [TripEvent.FallbackAlarmChanged(atMs: base.ms(n + 30), fallbackAtMs: base.ms(n + 90), cause: .resync)])
        // Steps that stay SNOOZED keep it.
        base.tick(n + 30)
        #expect(base.view.snoozeUntilMs == base.ms(n + 60))
    }

    @Test("Parity #3: fb FAILED without emittedAtMs (hand-edited snapshot) → nextFallbackAt re-requests at once (as Kotlin)")
    func failedWithoutEmission() {
        let fb = FallbackState(targetAtMs: 5_000_000, emittedAtMs: nil, status: .failed, confirmedAtMs: nil, resync: false, near: false)
        #expect(FallbackPlanner.nextFallbackAt(fb, target: 4_000_000, predicted: 9_000_000, now: 1_000_000, .defaults) == 4_000_000)
    }

    @Test("Parity #4 / C17: GpsRecovered only when gpsLostAtMs is set; gpsLostAtMs cleared afterwards")
    func recoveredNeedsLostAt() {
        var d = EngineDriver()
        d.drive(from: 0, d0: 20_000, v: 15, count: 3)
        d.state.gps = .lost
        d.state.gpsLostAtMs = nil
        d.fix(20, d: 20_000 - 300, spd: 15)
        #expect(d.events.named("gpsRecovered").isEmpty && d.view.gps == .ok)
        var e = EngineDriver()
        e.drive(from: 0, d0: 20_000, v: 15, count: 3)
        e.avail(12, .servicesOff)
        #expect(e.state.gpsLostAtMs == e.ms(12))
        e.fix(20, d: 20_000 - 300, spd: 15)
        #expect(e.events.named("gpsRecovered").count == 1 && e.state.gpsLostAtMs == nil)
    }

    @Test("Parity #5: targetTier in ENDED → nil (policy kept)")
    func endedTier() {
        var s = EngineDriver().state
        s.phase = .ended
        #expect(SamplingPlanner.targetTier(s, nil, predicted: nil, now: s.nowMs) == nil)
    }

    @Test("Parity #6: blank Remote Config string = Kotlin isBlank (U+001C–U+001F, NBSP blank; U+0085 not blank)")
    func blank() {
        for s in ["\u{1C}\u{1D}\u{1E}\u{1F}", " \t\n\r\u{0B}\u{0C}", "\u{A0}\u{2007}\u{202F}\u{3000}\u{2028}\u{2029}"] {
            let r = EngineParamsFactory.parseOverrides(s)
            #expect(!r.malformed && r.params == .defaults, "\(s.unicodeScalars.map(\.value))")
        }
        #expect(EngineParamsFactory.parseOverrides("\u{85}").malformed)
    }

    @Test("Parity #7: JSON error rule names and offsets (UTF-16) as the Kotlin parser")
    func jsonErrors() {
        func err(_ s: String) -> String {
            do { _ = try MiniJson.parse(s); return "ok" } catch { return error.description }
        }
        #expect(err("[\"é\",]") == "json: unexpected character at 5")
        #expect(err("[\"😀\",]") == "json: unexpected character at 6")
        #expect(err("{\"a\":1 \"b\"}") == "json: expected comma or brace at 7")
        #expect(err("[1 2]") == "json: expected comma or bracket at 3")
        #expect(err("\"\\uZZZZ\"") == "json: invalid unicode escape at 2")
        #expect(err("\"\\q\"") == "json: invalid escape at 2")
        #expect(err("\"\\") == "json: unterminated string at 2")
        #expect(err("\"\\ud800x\"") == "json: lone surrogate at 6")
        #expect(err("tru") == "json: invalid literal at 0")
        #expect(err("-") == "json: invalid number at 1")
    }

    @Test("allowFallbackFirst (T11.2 V14–V16): non-bool fails parsing; with kill / without an expect alarm ringNow=false is a config error")
    func allowFallbackFirst() throws {
        guard let trace = LoadedTrace.named("bus_hn_brt01") else { Issue.record("trace"); return }
        let base = #""id":"x","status":"final","testIds":["TR38"],"forbid":[]"#
        let cfg = #""config":{"mode":"distance","thresholdM":1000,"preAlert":true}"#
        let alarmFalse = #""expect":[{"event":"alarm","ringNow":false,"notBefore":0,"notAfter":10,"window":{},"ref":"x"}]"#
        #expect(throws: (any Error).self) {
            _ = try SwiftSpecificTests.caseJson("{\(base),\(cfg),\"allowFallbackFirst\":\"yes\",\"expect\":[]}")
        }
        let noAlarm = try SwiftSpecificTests.caseJson("{\(base),\(cfg),\"allowFallbackFirst\":true,\"expect\":[]}")
        #expect(Runner(trace: trace, spec: noAlarm, mode: "all").configErrors.contains { $0.contains("needs an expect entry") })
        let withKill = try SwiftSpecificTests.caseJson(
            "{\(base),\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"kill\":{\"t\":100}},\"allowFallbackFirst\":true,\(alarmFalse)}")
        #expect(Runner(trace: trace, spec: withKill, mode: "all").configErrors.contains { $0.contains("cannot be used with") })
        let ok = try SwiftSpecificTests.caseJson("{\(base),\(cfg),\"allowFallbackFirst\":true,\(alarmFalse)}")
        #expect(ok.allowFallbackFirst && Runner(trace: trace, spec: ok, mode: "all").configErrors.isEmpty)
    }
}
