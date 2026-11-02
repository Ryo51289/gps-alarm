import Testing
@testable import Trip

/// Hand-built estimate (only the fields the rule under test reads matter).
func makeE(dNow: Double, v: Double, k: Double, cvDr: Double? = nil, eta: Double? = nil, established: Bool = true) -> Estimate {
    let cv = cvDr ?? v / k
    let etaS = eta ?? (v >= 0.5 ? dNow * k / v + 20 : nil)
    return Estimate(established: established, v: v, k: k, closingV: v / k, guardV: nil, lift: false, vDr: v, cvDr: cv,
                    elapsedS: 0, dNow: dNow, etaS: etaS, errM: 8, etaMinS: nil, etaMaxS: nil)
}

/// Driver whose state is established at (ground, closing), with `dSmooth = d`, last fix now, not in a stop.
func establishedAt(_ mode: AlarmMode = .distance, thr: Int? = 1000, thrMin: Int? = nil, hint: VehicleKind = .train, params: String? = nil,
                   ground: Double, closing: Double, d: Double) -> EngineDriver {
    var x = EngineDriver(mode, thr: thr, thrMin: thrMin, hint: hint, params: params)
    x.drive(from: 0, d0: 150_000, v: 20, count: 40)
    x.state.ground = ground
    x.state.closing = closing
    x.state.dSmooth = d
    x.state.stopStartMs = nil
    x.state.last!.fixAtMs = x.state.nowMs
    x.state.recent = [x.state.last!]
    return x
}

@Suite("ModeRulesTests")
struct ModeRulesTests {
    @Test("U14 DISTANCE 1000: dSmooth 1000.0 alarms (DISTANCE), 1000.01 does not")
    func u14() {
        var a = EngineDriver(); a.fix(0, d: 1000.0, exact: true)
        #expect(a.state.dSmooth == 1000.0)
        #expect(a.events.alarms.map(\.reason) == [.distance])
        var b = EngineDriver(); b.fix(0, d: 1000.01)
        #expect(b.state.dSmooth! > 1000 && b.events.alarms.isEmpty)
    }

    @Test("U15 TIME 15: etaS 900.0 alarms (TIME), 900.5 does not")
    func u15() {
        var a = establishedAt(.time, thr: nil, thrMin: 15, ground: 10, closing: 10, d: 8800)
        #expect(a.estimate!.etaS == 900.0)
        a.tick(Double(a.state.nowMs - a.startMs) / 1000)
        #expect(a.events.alarms.map(\.reason) == [.time])
        var b = establishedAt(.time, thr: nil, thrMin: 15, ground: 10, closing: 10, d: 8805)
        #expect(b.estimate!.etaS == 900.5)
        b.tick(Double(b.state.nowMs - b.startMs) / 1000)
        #expect(b.events.alarms.isEmpty)
    }

    @Test("U17 SMART: 60 km/h, etaS 599 → SMART_TIME; smartTargetS 300 + slow 5 km/h, 11 km/h, etaS 400, d 990 → SMART_DISTANCE")
    func u17() {
        let v = 60 / 3.6
        var a = establishedAt(.smart, thr: nil, ground: v, closing: v, d: 579 * v)
        a.state.slow = false
        #expect(approx(a.estimate!.etaS, 599, 1e-6))
        a.tick(Double(a.state.nowMs - a.startMs) / 1000)
        #expect(a.events.alarms.map(\.reason) == [.smartTime])
        let g = 11 / 3.6, k = 380 * g / 990
        var b = establishedAt(.smart, thr: nil, params: #"{"smartTargetS": 300, "smartSlowSpeedKmh": 5}"#, ground: g, closing: g / k, d: 990)
        b.state.slow = false
        #expect(approx(b.estimate!.etaS, 400, 1e-6))
        b.tick(Double(b.state.nowMs - b.startMs) / 1000)
        #expect(b.events.alarms.map(\.reason) == [.smartDistance])
    }

    @Test("U18 SMART slow: 12 km/h d 2600 no, 2500 SMART_SLOW_DISTANCE; 16 km/h stays slow; 17.1 leaves; smartFloorM 3000 → slowDistM 3000")
    func u18() {
        var x = establishedAt(.smart, thr: nil, ground: 12 / 3.6, closing: 12 / 3.6, d: 2600)
        x.state.slow = false
        Estimator.updateSlow(&x.state)
        #expect(x.state.slow)
        #expect(ModeRules.modeReason(x.state, x.estimate!) == nil)
        x.state.dSmooth = 2500
        #expect(ModeRules.modeReason(x.state, x.estimate!) == .smartSlowDistance)
        x.state.ground = 16 / 3.6; Estimator.updateSlow(&x.state); #expect(x.state.slow)
        x.state.ground = 17.1 / 3.6; Estimator.updateSlow(&x.state); #expect(!x.state.slow)
        #expect(ModeRules.slowDistM(.defaults) == 2500.0)
        #expect(ModeRules.slowDistM(EngineDriver.params(#"{"smartFloorM": 3000, "smartTargetS": 600}"#)) == 3000)
    }

    @Test("U57 first fix already inside the zone (d 800, DISTANCE 1000) → Alarm(DISTANCE) at that Step")
    func u57() {
        var d = EngineDriver(); d.fix(0, d: 800)
        #expect(d.events.alarms.map(\.reason) == [.distance] && d.view.phase == .alarming)
    }

    @Test("U58 TIME 15, not established, hint BUS, d 4 km: etaS = 4000·1.2/(20/3.6) + 20 ≈ 884 → alarm at once")
    func u58() {
        var d = EngineDriver(.time, thr: nil, thrMin: 15, hint: .bus)
        d.fix(0, d: 4000)
        #expect(approx(d.estimate!.etaS, 4000 * 1.2 / (20 / 3.6) + 20, 1e-6))
        #expect(d.events.alarms.map(\.reason) == [.time])
    }

    @Test("U81 TIME 15, established, ground 0.4 (etaS null), k 2: Alarm(TIME) once d ≤ 300")
    func u81() {
        var d = EngineDriver(.time, thr: nil, thrMin: 15)
        d.fix(0, d: 20_000)
        d.state.movingTimeS = 200; d.state.movingSamples = 5; d.state.ground = 0.4; d.state.closing = 0.2
        var t = 0.0
        for dist in Array(stride(from: 18_000.0, through: 1000, by: -2000)) + [400.0, 301, 300] {
            t += 60
            d.fix(t, d: dist, spd: 0.4)
            #expect(d.estimate!.etaS == nil)
            if dist > 300 { #expect(d.events.alarms.isEmpty, "d = \(dist)") }
        }
        #expect(d.events.alarms.map(\.reason) == [.time])
    }
}

@Suite("PredictedAlarmAtTest")
struct PredictedAlarmAtTests {
    static func state(_ mode: AlarmMode, thr: Int? = 1000, thrMin: Int? = nil, params: String? = nil) -> EngineState {
        var d = EngineDriver(mode, thr: thr, thrMin: thrMin, params: params)
        d.fix(0, d: 300_000)
        var s = d.state
        s.maxTripDurationS = 172_800   // keep the deadline out of the way
        return s
    }

    @Test("U82 predictedAlarmAt: DISTANCE, TIME, SMART (both branches, slow), LOST, battery, null cases, deadline")
    func u82() {
        let n: Int64 = 1_000_000_000 + 1_000_000
        var s = Self.state(.distance)
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 9000, v: 12.5, k: 1), now: n).withBattery == n + 640_000)
        s = Self.state(.time, thr: nil, thrMin: 10)
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 9000, v: 15, k: 1.2), now: n).withBattery == n + 140_000)
        s = Self.state(.smart, thr: nil); s.slow = false
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 9000, v: 15, k: 1.2), now: n).withBattery == n + 140_000)
        s = Self.state(.smart, thr: nil, params: #"{"smartTargetS": 300, "smartSlowSpeedKmh": 5}"#); s.slow = false
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 2000, v: 3, k: 1.5), now: n).withBattery == n + 500_000)
        s = Self.state(.smart, thr: nil); s.slow = true
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 4000, v: 2, k: 1), now: n).withBattery == n + 750_000)
        // (f) LOST: constant at L + 120 s and L + 180 s.
        var l = establishedAt(.distance, ground: 15, closing: 12.5, d: 30_000)
        l.state.gps = .lost
        l.state.cvGuard = []
        let lMs = l.state.last!.fixAtMs
        for dt: Int64 in [120_000, 180_000] {
            let e = Estimator.estimate(l.state, now: lMs + dt)
            #expect(ModeRules.predictedAlarmAt(l.state, e, now: lMs + dt).withBattery == lMs + 1_220_000)
        }
        // (g) battery.
        s = Self.state(.distance)
        s.battery = BatteryState(levelPct: 20, charging: false, segT0: n, segL0: 20, armed: true, riskEmitted: false, choice: nil, choicePct: nil)
        let g = ModeRules.predictedAlarmAt(s, makeE(dNow: 406_000, v: 12.5, k: 1), now: n)
        #expect(g.withBattery == n + 27_000_000 && g.noBattery == n + 32_400_000)
        // (h)
        let fresh = EngineDriver()
        #expect(ModeRules.predictedAlarmAt(fresh.state, nil, now: fresh.startMs + 10).withBattery == fresh.startMs + 14_400_000)
        s = Self.state(.distance); s.alarm.atMs = n
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 9000, v: 12.5, k: 1), now: n).withBattery == nil)
        s = Self.state(.time, thr: nil, thrMin: 15)
        #expect(ModeRules.predictedAlarmAt(s, makeE(dNow: 1300, v: 0.4, k: 2), now: n).withBattery == n + 5_000_000)
    }
}

@Suite("PreAlertRuleTests")
struct PreAlertRuleTests {
    @Test("U19 DISTANCE zone: thr 500 / 1000 / 10 000 → 3000 / 5000 / 50 000 m")
    func u19() {
        for (thr, zone) in [(500, 3000.0), (1000, 5000.0), (10_000, 50_000.0)] {
            let s = EngineDriver(.distance, thr: thr).state
            #expect(PreAlertRule.inZone(s, makeE(dNow: zone, v: 10, k: 1)))
            #expect(!PreAlertRule.inZone(s, makeE(dNow: zone.nextUp, v: 10, k: 1)))
        }
    }

    @Test("U20 TIME 20 zone at eta 1800; TIME 30 never; SMART at eta 1800")
    func u20() {
        let t20 = EngineDriver(.time, thr: nil, thrMin: 20).state
        #expect(PreAlertRule.inZone(t20, makeE(dNow: 1, v: 10, k: 1, eta: 1800)))
        #expect(!PreAlertRule.inZone(t20, makeE(dNow: 1, v: 10, k: 1, eta: 1800.5)))
        let t30 = EngineDriver(.time, thr: nil, thrMin: 30).state
        #expect(!PreAlertRule.inZone(t30, makeE(dNow: 1, v: 10, k: 1, eta: 10)))
        let sm = EngineDriver(.smart, thr: nil).state
        #expect(PreAlertRule.inZone(sm, makeE(dNow: 1, v: 10, k: 1, eta: 1800)))
        #expect(!PreAlertRule.inZone(sm, makeE(dNow: 1, v: 10, k: 1, eta: 1801)))
    }

    @Test("U21 trip starting at d 4 km (DISTANCE 1000) or with preAlertEnabled = false: no PreAlert, Alarm still comes")
    func u21() {
        for pre in [true, false] {
            var d = EngineDriver(.distance, thr: 1000, preAlert: pre)
            d.drive(from: 0, d0: pre ? 4000 : 8000, v: 15, count: 300)
            let all = d.allEvents()
            #expect(all.named("preAlert").isEmpty)
            #expect(all.alarms.first?.reason == .distance)
        }
    }

    @Test("U22 one Step with both the pre-alert zone and the alarm condition → only Alarm")
    func u22() {
        var d = EngineDriver()
        d.fix(0, d: 6000, spd: 15)
        #expect(d.state.preAlertArmed)
        d.fix(100, d: 900, spd: 15)
        #expect(d.events.alarms.count == 1 && d.events.named("preAlert").isEmpty)
    }

    @Test("U64 armed only at the first fix: start at 4 km, out to 6 km and back → no PreAlert; start at 6 km → PreAlert at 5 km")
    func u64() {
        var a = EngineDriver()
        a.fix(0, d: 4000, spd: 10); a.fix(100, d: 5000, spd: 10); a.fix(200, d: 6000, spd: 10)
        a.fix(300, d: 5000, spd: 10); a.fix(400, d: 4000, spd: 10)
        #expect(a.allEvents().named("preAlert").isEmpty)
        var b = EngineDriver()
        b.fix(0, d: 6000, spd: 10); b.fix(60, d: 5400, spd: 10); b.fix(100, d: 4990, spd: 10)
        #expect(b.events.named("preAlert").count == 1)
        #expect(b.allEvents().named("preAlert").count == 1)
    }
}
