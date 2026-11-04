import Testing
@testable import Trip

@Suite("GpsMonitorTests")
struct GpsMonitorTests {
    @Test("U23 DENSE, last fix t0: Tick t0+59 nothing, t0+60 GpsLost(NO_FIX_TIMEOUT)")
    func u23() {
        var d = EngineDriver()
        d.drive(from: 0, d0: 5000, v: 12, count: 10)
        #expect(d.view.samplingPolicy?.tier == .dense && d.state.policyIntervalAtLastFixS == 5)
        let t0 = 45.0
        d.tick(t0 + 59); #expect(d.events.named("gpsLost").isEmpty)
        d.tick(t0 + 60); #expect(d.events.compactMap(\.asGpsLost).first?.cause == .noFixTimeout)
    }

    @Test("U24 just switched SPARSE → DENSE, last fix requested at 180 s: no GpsLost until 540 s after it (C2)")
    func u24() {
        var d = EngineDriver()
        d.drive(from: 0, d0: 200_000, v: 20, count: 40)
        d.state.policy = SamplingPlanner.policyFor(.sparse, d.state.params, maxSaving: false)
        d.fix(375, d: 200_000 - 20 * 375, spd: 20)
        #expect(d.state.policyIntervalAtLastFixS == 180)
        d.state.policy = SamplingPlanner.policyFor(.dense, d.state.params, maxSaving: false)
        d.tick(375 + 170); d.tick(375 + 539)
        #expect(d.allEvents(from: d.steps.count - 2).named("gpsLost").isEmpty)
        d.tick(375 + 540)
        #expect(d.events.compactMap(\.asGpsLost).first?.lastFixAgeS == 540)
    }

    @Test("U25 lost, etaS 1260, closingV 15: Alarm(GPS_LOST) at the first 5 s tick with etaS < 1200 (65 s later)")
    func u25() {
        var d = establishedAt(.distance, ground: 15, closing: 15, d: 18_600)
        d.state.gps = .lost; d.state.cvGuard = []
        let t0 = Double(d.state.nowMs - d.startMs) / 1000
        #expect(approx(d.estimate!.etaS, 1260, 1e-9))
        var t = t0 + 5
        while t < t0 + 200 {
            d.tick(t)
            if !d.events.alarms.isEmpty { break }
            t += 5
        }
        #expect(t == t0 + 65 && d.events.alarms.first?.reason == .gpsLost)
    }

    @Test("U26 lost 120 s, acc 8, closingV 15: isEstimated, distanceErrorM 458, distanceM 1800 lower")
    func u26() {
        var d = establishedAt(.distance, ground: 15, closing: 15, d: 50_000)
        d.state.cvGuard = []
        let t0 = Double(d.state.nowMs - d.startMs) / 1000
        d.tick(t0)
        let d0 = d.view.distanceM!
        d.state.gps = .lost
        d.tick(t0 + 120)
        #expect(d.view.isEstimated && d.view.distanceErrorM == 458 && d.view.distanceM == d0 - 1800)
    }

    @Test("U27 LocationAvailability(PERMISSION_REVOKED) when etaS = 900 → GpsLost + Alarm(GPS_LOST) in the same Step")
    func u27() {
        var d = establishedAt(.distance, ground: 15, closing: 15, d: 880 * 15)
        d.state.cvGuard = []
        d.avail(Double(d.state.nowMs - d.startMs) / 1000, .permissionRevoked)
        #expect(d.events.compactMap(\.asGpsLost).first?.cause == .permissionRevoked)
        #expect(d.events.alarms.map(\.reason) == [.gpsLost])
    }

    @Test("U28 while lost a rejected fix does not recover; a good fix does")
    func u28() {
        var d = EngineDriver()
        d.drive(from: 0, d0: 50_000, v: 15, count: 20)
        d.tick(95 + 120)
        #expect(d.view.gps == .lost)
        d.fix(230, d: 10_000, spd: 15)
        #expect(d.events.named("gpsRecovered").isEmpty && d.view.gps == .lost)
        d.fix(240, d: 50_000 - 15 * 240, spd: 15)
        #expect(d.events.named("gpsRecovered").count == 1 && d.view.gps == .ok)
    }

    @Test("U63 lost, DISTANCE 1000: (a) eta 1100, dNow 5000 alarm; (b) eta 1300, dNow 900 alarm; (c) eta 1300, dNow 5000 none")
    func u63() {
        var s = EngineDriver().state
        s.gps = .lost
        let now = s.nowMs
        #expect(ModeRules.alarmReason(s, makeE(dNow: 5000, v: 10, k: 1, eta: 1100), now: now, passedClosest: false) == .gpsLost)
        #expect(ModeRules.alarmReason(s, makeE(dNow: 900, v: 10, k: 1, eta: 1300), now: now, passedClosest: false) == .gpsLost)
        #expect(ModeRules.alarmReason(s, makeE(dNow: 5000, v: 10, k: 1, eta: 1300), now: now, passedClosest: false) == nil)
    }

    @Test("U71 lost while stopped at 60 km (train 15 m/s, k 1.2): GpsLost at lostAfterS, predicted constant ± 1 ms, Alarm(GPS_LOST) at tick 3660")
    func u71() {
        // T10.6 §6 (D1): GPS lost 2 280 s before the alarm; this test checks dead reckoning while stopped, not the "long loss"
        // rule W (with W on the alarm is GPS_LOST earlier, U119–U121), so W is off.
        var d = EngineDriver(params: #"{"gpsLostLongS": 0}"#)
        d.drive(from: 0, d0: 61_875, v: 15, k: 1.2, count: 30)   // ends at t 145, d 60 062.5, established
        d.fix(160, d: 60_000, spd: 0)
        #expect(d.state.stopStartMs != nil && approx(d.state.dSmooth, 60_000, 1e-6))
        #expect(d.state.cvGuard.allSatisfy { $0 <= d.estimate!.closingV + 1e-9 })
        let lost = Double(GpsMonitor.lostAfterS(d.state))
        var p: Int64? = nil, lostT: Double? = nil, alarmT: Double? = nil
        var e = 60.0
        while e <= 5000 {
            d.tick(160 + e)
            if lostT == nil, !d.events.named("gpsLost").isEmpty { lostT = e }
            if !d.events.alarms.isEmpty { alarmT = e; break }
            if lostT != nil {
                if let p0 = p { #expect((d.view.predictedAlarmAtMs! - p0).magnitude <= 1) } else { p = d.view.predictedAlarmAtMs }
            }
            e += 60
        }
        #expect(lostT == (lost / 60).rounded(.up) * 60)
        #expect(alarmT == 3660 && d.events.alarms.first?.reason == .gpsLost)
    }

    @Test("U86 ACQUIRING + SERVICES_OFF then first fix; OK + PERMISSION_REVOKED then SERVICES_OFF then fix (I7)")
    func u86() {
        var a = EngineDriver()
        a.avail(10, .servicesOff)
        #expect(a.events.compactMap(\.asGpsLost).map(\.cause) == [.servicesOff])
        a.tick(130)
        #expect(a.events.named("gpsLost").isEmpty)   // NEVER_ACQUIRED not emitted twice
        a.fix(140, d: 20_000)
        #expect(a.events.named("gpsRecovered").count == 1)
        var b = EngineDriver()
        b.fix(0, d: 20_000); b.fix(5, d: 19_950)
        b.avail(10, .permissionRevoked)
        #expect(b.events.compactMap(\.asGpsLost).map(\.cause) == [.permissionRevoked])
        b.avail(15, .servicesOff)
        #expect(b.events.named("gpsLost").isEmpty && b.view.locationCause == .servicesOff)
        b.fix(20, d: 19_850)
        #expect(b.events.named("gpsRecovered").count == 1 && b.view.locationCause == .available)
        let names = b.allEvents().filter { $0.fixtureName.hasPrefix("gps") }.map(\.fixtureName)
        #expect(names == ["gpsLost", "gpsRecovered"])
    }
}

@Suite("BatteryRuleTests")
struct BatteryRuleTests {
    static func ninehours() -> EngineDriver {
        var d = establishedAt(.distance, ground: 12.5, closing: 12.5, d: 406_000)
        d.state.maxTripDurationS = 172_800
        return d
    }
    static func now(_ d: EngineDriver) -> Double { Double(d.state.nowMs - d.startMs) / 1000 }

    @Test("U29 battery 20 %, prior 2 %/h, predicted alarm in 9 h → LowBatteryRisk(20, 450, 555) once")
    func u29() {
        var d = Self.ninehours()
        let t = Self.now(d)
        d.battery(t, 20)
        #expect(d.events.compactMap { if case let .lowBatteryRisk(r) = $0 { return r } else { return nil } }
            == [TripEvent.LowBatteryRisk(atMs: d.ms(t), levelPct: 20, availableMin: 450, neededMin: 555)])
        #expect(d.view.batteryRisk)
        d.battery(t, 20)
        #expect(d.events.isEmpty)
    }

    @Test("U30 charging 6 % then 5 %: no risk, no alarm")
    func u30() {
        var d = Self.ninehours()
        let t = Self.now(d)
        d.battery(t, 6, charging: true); d.battery(t, 5, charging: true)
        #expect(d.allEvents(from: 1).filter { $0.fixtureName == "lowBatteryRisk" || $0.fixtureName == "alarm" }.isEmpty)
        #expect(!d.view.batteryRisk)
    }

    @Test("U31 TRACKING 6 % then 5 % → Alarm(LOW_BATTERY, batteryPct 5); (b) BATTERY_ALARM_AT_5 chosen at 20 % → same")
    func u31() {
        for chooseAt5 in [false, true] {
            var d = Self.ninehours()
            let t = Self.now(d)
            if chooseAt5 { d.battery(t, 20); d.user(t, .batteryAlarmAt5) }
            d.battery(t, 6)
            #expect(d.events.alarms.isEmpty)
            d.battery(t, 5)
            #expect(d.events.alarms.map(\.reason) == [.lowBattery] && d.events.alarms.first?.batteryPct == 5)
        }
    }

    @Test("U32 BATTERY_ALARM_EARLIER at 18 % → alarm at 15 %; MAX_SAVING → SPARSE 360, MEDIUM 60, DENSE 5; (b) AT_5 before risk → no risk; (c) MAX_SAVING then EARLIER → SPARSE 180")
    func u32() {
        var d = Self.ninehours()
        let t = Self.now(d)
        d.battery(t, 18); d.user(t, .batteryAlarmEarlier)
        #expect(d.state.battery.choicePct == 15)
        d.battery(t, 16); #expect(d.events.alarms.isEmpty)
        d.battery(t, 15); #expect(d.events.alarms.map(\.reason) == [.lowBattery])
        let p = EngineParams.defaults
        #expect(SamplingPlanner.policyFor(.sparse, p, maxSaving: true) == SamplingPolicy(tier: .sparse, intervalS: 360, minIntervalS: 180, accuracy: .balanced))
        #expect(SamplingPlanner.policyFor(.medium, p, maxSaving: true).intervalS == 60)
        #expect(SamplingPlanner.policyFor(.dense, p, maxSaving: true).intervalS == 5)
        var m = Self.ninehours()
        m.user(Self.now(m), .batteryMaxSaving)
        #expect(m.view.samplingPolicy?.intervalS == 360)
        // (b)
        var b = Self.ninehours(), plain = Self.ninehours()
        b.user(Self.now(b), .batteryAlarmAt5)
        b.battery(Self.now(b), 20); plain.battery(Self.now(plain), 20)
        #expect(b.allEvents().named("lowBatteryRisk").isEmpty && !plain.allEvents().named("lowBatteryRisk").isEmpty)
        #expect(b.view.samplingPolicy == plain.view.samplingPolicy)
        // (c)
        m.user(Self.now(m), .batteryAlarmEarlier)
        #expect(m.view.samplingPolicy?.intervalS == 180)
    }

    @Test("U33 observed rate: 21 → 20 % in 30 min = 2 %/h; 21 → 21 → prior")
    func u33() {
        var d = Self.ninehours()
        let t = Self.now(d)
        d.battery(t, 21); d.battery(t + 1800, 20)
        #expect(BatteryRule.observedRate(d.state, now: d.ms(t + 1800)) == 2.0)
        var e = Self.ninehours()
        e.battery(t, 21); e.battery(t + 1800, 21)
        #expect(BatteryRule.observedRate(e.state, now: e.ms(t + 1800)) == nil)
        #expect(BatteryRule.rate(e.state, now: e.ms(t + 1800)) == 2.0)
    }

    @Test("U65 21 → 20 % after 1 199 999 ms → null (prior); after 1 200 000 ms → 3 %/h")
    func u65() {
        var s = EngineDriver().state
        s.battery = BatteryState(levelPct: 20, charging: false, segT0: 0, segL0: 21, armed: true, riskEmitted: false, choice: nil, choicePct: nil)
        #expect(BatteryRule.observedRate(s, now: 1_199_999) == nil)
        #expect(BatteryRule.observedRate(s, now: 1_200_000) == 3.0)
    }

    @Test("U79 (a) lost + 5 % → LOW_BATTERY (not GPS_LOST); (b) 13 % + EARLIER → threshold 12; (c) start at 4 %, then 3 % → no alarm")
    func u79() {
        var a = Self.ninehours()
        a.state.gps = .lost; a.state.cvGuard = []
        let t = Self.now(a)
        a.battery(t, 6); a.battery(t, 5)
        #expect(a.events.alarms.map(\.reason) == [.lowBattery])
        var b = Self.ninehours()
        b.battery(t, 20); b.battery(t, 13); b.user(t, .batteryAlarmEarlier)
        #expect(b.state.battery.choicePct == 12)
        b.battery(t, 13); #expect(b.events.alarms.isEmpty)
        b.battery(t, 12); #expect(b.events.alarms.map(\.reason) == [.lowBattery])
        var c = Self.ninehours()
        c.battery(t, 4); c.battery(t, 3)
        #expect(c.allEvents().alarms.isEmpty)
    }
}
