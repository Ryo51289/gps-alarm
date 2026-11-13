import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T23.8 C1 tester additions (docs/test-reports/T23.8-C1.md): risk areas outside CU01–CU30.
/// - CU28 with ticks between the first two fixes (review C1 round 2 nit #3): dNow slides before the stop is detected.
/// - minSpeedForEtaMps rule of §5.6a against the real engine (orchestrator note after review C1 round 2).
/// - Evaluator edges: midnight windows, time zone change between events, revision change, clock set back.
/// - Guard and codec boundaries.
@Suite("T23.8 commute tester edges")
struct CommuteTesterEdgeTests {
    static let destLat = 21.0
    static let destLng = 105.8
    static let t0: Int64 = 1_800_000_000_000

    /// One fix `distanceM` south of the destination at t0 + 1 s, then 1 Hz ticks for `gapS` seconds, then stationary 1 Hz
    /// fixes (speed 0, accuracy 10 m) at the same place until 10 minutes. Returns every Alarm event.
    static func alarms(_ m: TripMeta, distanceM: Double, gapS: Int) throws -> [TripEvent.Alarm] {
        let params = EngineParamsFactory.fromOverrides(m.engineParamsJson)
        var step = try TripEngine.start(config: m.config(destLat: destLat, destLng: destLng), params: params, nowMs: t0)
        var out: [TripEvent.Alarm] = []
        func collect(_ s: Step) {
            for case let .alarm(a) in s.events { out.append(a) }
        }
        collect(step)
        let lat = destLat - distanceM / Geo.kMetresPerDegLat
        func fix(_ t: Int64) -> EngineInput {
            .locationFix(LocationFix(atMs: t, fixAtMs: t, lat: lat, lng: destLng, accuracyM: 10, speedMps: 0))
        }
        step = TripEngine.reduce(step.state, fix(t0 + 1_000))
        collect(step)
        for i in 2...600 {
            let t = t0 + Int64(i) * 1_000
            step = TripEngine.reduce(step.state, i <= gapS + 1 ? .tick(atMs: t) : fix(t))
            collect(step)
        }
        return out
    }

    /// Closing speed before the speed is established: hint speed / routeFactorPrior (the slide rate of dNow).
    static func hintClosingMps(_ m: TripMeta) -> Double {
        let p = EngineParamsFactory.fromOverrides(m.engineParamsJson)
        return Double(CommuteRouteValidator.hintKmh(m.vehicleHint, p)) / 3.6 / p.routeFactorPrior
    }

    // MARK: CU28 with ticks (review nit #3)

    @Test("CU28+ticks: first fix 200 m inside the margin (R + 800 m), ticks for 5/10/30/45 s before the 2nd fix: no Alarm")
    func cu28WithTicks() throws {
        let c = CommuteConstants.default
        let inside = c.abThresholdMarginM - c.regionRadiusM  // the user entered A 200 m on the B side of its centre
        for (name, m, _, _) in CommuteUnitTests.reachTable {
            let r = CommuteRouteValidator.stationaryReachM(m)
            // 30 s = samplingMediumIntervalS (tier while the speed is not established); 45 s = spec §5.6a margin note.
            for gap in [5, 10, 30, 45] {
                let got = try Self.alarms(m, distanceM: r + inside, gapS: gap)
                #expect(got.isEmpty, "\(name) gap \(gap) s: alarmed \(got.map(\.reason)) at \(got.map { $0.atMs - Self.t0 })")
            }
        }
    }

    @Test("CU28+ticks sanity: ticks do slide dNow — at R + 50 m an Alarm comes before the 2nd fix when the slide > 50 m")
    func ticksSlide() throws {
        for (name, m, _, _) in CommuteUnitTests.reachTable where name == "smart bus" || name == "smart coach"
            || name == "distance 1000" {
            let r = CommuteRouteValidator.stationaryReachM(m)
            let gap = 30
            #expect(Self.hintClosingMps(m) * Double(gap) > 50, "\(name)")
            let got = try Self.alarms(m, distanceM: r + 50, gapS: gap)
            let first = try #require(got.first, "\(name): no Alarm although dNow slid past R")
            #expect(first.atMs - Self.t0 <= Int64(gap + 1) * 1_000, "\(name): Alarm only after the 2nd fix")
        }
    }

    // MARK: minSpeedForEtaMps rule (§5.6a, orchestrator note)

    @Test("§5.6a minSpeedForEtaMps rule vs engine: TIME 60 bus 10 km/h (min 3.0) has R = 300; 11 km/h has the ETA reach")
    func minSpeedRuleEngine() throws {
        let slow = CS.template("B", mode: .time, distanceM: nil, timeMin: 60,
                               params: #"{"expectedSpeedKmhBus":10,"minSpeedForEtaMps":3.0}"#)
        #expect(CommuteRouteValidator.stationaryReachM(slow) == 300)
        #expect(CommuteRouteValidator.requiredSeparationM(CS.route(templateB: slow, templateA: slow)) == 2_000)
        // The engine agrees: nothing at 350 m (nor at the formula without the rule, 8 287 m − 50), Alarm at 250 m.
        #expect(try Self.alarms(slow, distanceM: 350, gapS: 0).isEmpty)
        #expect(try Self.alarms(slow, distanceM: 8_237, gapS: 0).isEmpty)
        let near = try #require(try Self.alarms(slow, distanceM: 250, gapS: 0).first)
        #expect(near.reason == .time)
        #expect(near.atMs - Self.t0 <= 5_000)

        let fast = CS.template("B", mode: .time, distanceM: nil, timeMin: 60,
                               params: #"{"expectedSpeedKmhBus":11,"minSpeedForEtaMps":3.0}"#)
        let r = CommuteRouteValidator.stationaryReachM(fast)
        #expect(abs(r - 9_115.740_741) < 1e-5)
        #expect(CommuteRouteValidator.requiredSeparationM(CS.route(templateB: fast, templateA: fast)) == 10_116)
        #expect(try Self.alarms(fast, distanceM: r + 50, gapS: 0).isEmpty)
        let hit = try #require(try Self.alarms(fast, distanceM: r - 50, gapS: 0).first)
        #expect(hit.reason == .time)
        #expect(hit.atMs - Self.t0 <= 5_000)
    }

    // MARK: Evaluator — midnight windows

    static let everyDay = 127

    @Test("window [23:45, 24:00): 23:45 and 23:59:59 start with that day's key; 00:00 next day is outside")
    func lateWindow() {
        let route = CS.route(towardB: CS.window(1_425, 1_440, mask: Self.everyDay))
        #expect(CommuteUnitTests.eval(at: "2026-11-17T23:45:00+07:00", route: route).0
            == .start(.towardB, dateKey: "2026-11-17"))
        #expect(CommuteUnitTests.eval(at: "2026-11-17T23:59:59+07:00", route: route).0
            == .start(.towardB, dateKey: "2026-11-17"))
        #expect(CommuteUnitTests.eval(at: "2026-11-18T00:00:00+07:00", route: route).0 == .skip(.outsideWindow))
        #expect(CommuteUnitTests.eval(at: "2026-11-17T23:44:59+07:00", route: route).0 == .skip(.outsideWindow))
    }

    @Test("window [00:00, 00:15): 00:00 starts with the new day's key; 23:59:59 the day before is outside")
    func earlyWindow() {
        let route = CS.route(towardB: CS.window(0, 15, mask: Self.everyDay))
        #expect(CommuteUnitTests.eval(at: "2026-11-18T00:00:00+07:00", route: route).0
            == .start(.towardB, dateKey: "2026-11-18"))
        #expect(CommuteUnitTests.eval(at: "2026-11-17T23:59:59+07:00", route: route).0 == .skip(.outsideWindow))
        #expect(CommuteUnitTests.eval(at: "2026-11-18T00:15:00+07:00", route: route).0 == .skip(.outsideWindow))
    }

    @Test("weekday is the local day of the event: Sunday-only window at the Saturday/Sunday/Monday midnights")
    func weekdayAtMidnight() {
        let late = CS.route(towardB: CS.window(1_380, 1_440, mask: 64))  // Sunday 23:00–24:00
        #expect(CommuteUnitTests.eval(at: "2026-11-22T23:59:59+07:00", route: late).0
            == .start(.towardB, dateKey: "2026-11-22"))
        #expect(CommuteUnitTests.eval(at: "2026-11-21T23:30:00+07:00", route: late).0 == .skip(.weekday))
        let early = CS.route(towardB: CS.window(0, 60, mask: 64))  // Sunday 00:00–01:00
        #expect(CommuteUnitTests.eval(at: "2026-11-22T00:00:00+07:00", route: early).0
            == .start(.towardB, dateKey: "2026-11-22"))
        #expect(CommuteUnitTests.eval(at: "2026-11-23T00:00:00+07:00", route: early).0 == .skip(.weekday))
        // Same instant 2026-11-21T17:30Z: +7 → Sunday 00:30 (starts), +6 → Saturday 23:30 (weekday).
        #expect(CommuteUnitTests.eval(at: "2026-11-21T17:30:00Z", route: early).0 == .start(.towardB, dateKey: "2026-11-22"))
        #expect(CommuteUnitTests.eval(at: "2026-11-21T17:30:00Z", route: early, offsetS: 6 * 3600).0 == .skip(.weekday))
    }

    @Test("rapid in/out/in across midnight in a 24 h-wrapping setup: one start per local day")
    func flapAcrossMidnight() {
        let route = CS.route(towardB: CS.window(1_380, 1_440, mask: Self.everyDay),
                             towardA: CS.window(0, 60, mask: Self.everyDay))
        let (d1, s1) = CommuteUnitTests.eval(at: "2026-11-17T23:50:00+07:00", route: route)
        guard case let .start(dir, key) = d1 else { Issue.record("expected start"); return }
        let fired = s1.markingFired(dir, dateKey: key)
        let (d2, s2) = CommuteUnitTests.eval(.a, .outside, at: "2026-11-17T23:55:00+07:00", route: route, from: fired)
        #expect(d2 == .skip(.notEntry))
        #expect(CommuteUnitTests.eval(at: "2026-11-17T23:58:00+07:00", route: route, from: s2).0
            == .skip(.alreadyFiredToday))
        // 00:01 the next day: towardB's window [23:00, 24:00) no longer applies.
        #expect(CommuteUnitTests.eval(at: "2026-11-18T00:01:00+07:00", route: route, from: s2).0 == .skip(.outsideWindow))
    }

    // MARK: Evaluator — time zone change between events

    @Test("time zone change: west in the same local day = no second start; east into the next local day = new key (spec)")
    func timeZoneChange() {
        let route = CS.route(towardB: CS.window(420, 1_140, mask: Self.everyDay))  // 07:00–19:00
        let (d1, s1) = CommuteUnitTests.eval(at: "2026-11-17T07:30:00+07:00", route: route)
        #expect(d1 == .start(.towardB, dateKey: "2026-11-17"))
        let fired = s1.markingFired(.towardB, dateKey: "2026-11-17")
        let (_, out) = CommuteUnitTests.eval(.a, .outside, at: "2026-11-17T01:00:00Z", route: route, from: fired)
        // Now at UTC−10: 2026-11-17T03:00Z = 2026-11-16 17:00 local — the previous local day: a new key (accepted, §5.3).
        #expect(CommuteUnitTests.eval(at: "2026-11-17T03:00:00Z", route: route, from: out, offsetS: -10 * 3600).0
            == .start(.towardB, dateKey: "2026-11-16"))
        // At UTC+9: 2026-11-17T03:00Z = 12:00 on the 17th: same local day → alreadyFiredToday.
        #expect(CommuteUnitTests.eval(at: "2026-11-17T03:00:00Z", route: route, from: out, offsetS: 9 * 3600).0
            == .skip(.alreadyFiredToday))
        // At UTC+14 the same instant is 17:00 on the 17th: still the same key.
        #expect(CommuteUnitTests.eval(at: "2026-11-17T03:00:00Z", route: route, from: out, offsetS: 14 * 3600).0
            == .skip(.alreadyFiredToday))
        // The event's time decides, not the processing time: 18:55 (+7) processed 19:04 is still inside 07:00–19:00.
        #expect(CommuteUnitTests.eval(at: "2026-11-18T11:55:00Z", route: route, processedAt: "2026-11-18T12:04:00Z").0
            == .start(.towardB, dateKey: "2026-11-18"))
    }

    @Test("LocalClock at extreme offsets and around the epoch")
    func localClockExtremes() {
        let utc = CS.ms("2026-11-17T12:00:00Z")
        #expect(LocalClock.local(utc, offsetS: 14 * 3600).dateKey == "2026-11-18")
        #expect(LocalClock.local(utc, offsetS: 14 * 3600).minuteOfDay == 120)
        #expect(LocalClock.local(utc, offsetS: -12 * 3600).dateKey == "2026-11-17")
        #expect(LocalClock.local(utc, offsetS: -12 * 3600).minuteOfDay == 0)
        let e = LocalClock.local(0, offsetS: -3_600)  // 1969-12-31 23:00, Wednesday
        #expect(e.dateKey == "1969-12-31")
        #expect(e.weekdayIndex == 2)
        #expect(e.minuteOfDay == 1_380)
        // Half-hour and 45-minute offsets (India +5:30, Nepal +5:45).
        #expect(LocalClock.local(utc, offsetS: 19_800).minuteOfDay == 17 * 60 + 30)
        #expect(LocalClock.local(utc, offsetS: 20_700).minuteOfDay == 17 * 60 + 45)
        // Last millisecond of a day.
        let last = CS.ms("2026-11-17T23:59:59+07:00") + 999
        #expect(LocalClock.local(last, offsetS: 7 * 3600).dateKey == "2026-11-17")
        #expect(LocalClock.local(last + 1, offsetS: 7 * 3600).dateKey == "2026-11-18")
        #expect(LocalClock.local(last + 1, offsetS: 7 * 3600).minuteOfDay == 0)
    }

    // MARK: Evaluator — revision change

    @Test("revision change: old-revision event is staleRevision and does not leak; new revision starts from unknown; day keys kept")
    func revisionChange() {
        let route2 = CS.route(revision: 2)
        let old = CommuteState(revision: 1, lastState: [.a: .outside, .b: .outside],
                               lastEventAtMs: [.a: CS.ms("2026-11-17T06:00:00+07:00")], firedKeys: ["towardB@2026-11-17"])
        // Event of revision 1 delivered after the route moved to revision 2.
        let (d0, s0) = CommuteUnitTests.eval(at: "2026-11-17T07:30:00+07:00", route: route2, from: old, rev: 1)
        #expect(d0 == .skip(.staleRevision))
        #expect(s0.revision == 2)
        #expect(s0.lastState.isEmpty && s0.lastEventAtMs.isEmpty)
        #expect(s0.firedKeys == ["towardB@2026-11-17"])
        // First event of revision 2: never starts (D6) although the old state said "outside".
        let (d1, s1) = CommuteUnitTests.eval(at: "2026-11-17T07:31:00+07:00", route: route2, from: old)
        #expect(d1 == .skip(.firstDetermination))
        let (_, s2) = CommuteUnitTests.eval(.a, .outside, at: "2026-11-17T07:35:00+07:00", route: route2, from: s1)
        // Out and in again: the day key of revision 1 still holds (one start per direction per day, D7).
        #expect(CommuteUnitTests.eval(at: "2026-11-17T07:40:00+07:00", route: route2, from: s2).0 == .skip(.alreadyFiredToday))
        // Without the key the same sequence starts.
        let fresh = CommuteState(revision: 1, lastState: [.a: .outside])
        let (_, f1) = CommuteUnitTests.eval(at: "2026-11-17T07:31:00+07:00", route: route2, from: fresh)
        let (_, f2) = CommuteUnitTests.eval(.a, .outside, at: "2026-11-17T07:35:00+07:00", route: route2, from: f1)
        #expect(CommuteUnitTests.eval(at: "2026-11-17T07:40:00+07:00", route: route2, from: f2).0
            == .start(.towardB, dateKey: "2026-11-17"))
        // A revision that went down (reinstall with an older stored state) is a change too.
        let ahead = CommuteState(revision: 9, lastState: [.a: .outside])
        #expect(CommuteUnitTests.eval(at: "2026-11-17T07:31:00+07:00", route: route2, from: ahead).0
            == .skip(.firstDetermination))
        // An event of a future revision (route not yet synced) is ignored as well.
        #expect(CommuteUnitTests.eval(at: "2026-11-17T07:31:00+07:00", route: route2, rev: 3).0 == .skip(.staleRevision))
    }

    // MARK: Evaluator — clock set back / forward

    @Test("clock set back by a day: a future day key does not block today; a future lastEventAtMs does not block the entry")
    func clockSetBack() {
        let future = CommuteState(revision: 1, lastState: [.a: .inside, .b: .outside],
                                  lastEventAtMs: [.a: CS.ms("2026-11-18T07:30:00+07:00")],
                                  firedKeys: ["towardB@2026-11-18"])
        let (d1, s1) = CommuteUnitTests.eval(.a, .outside, at: "2026-11-17T07:10:00+07:00", from: future)
        #expect(d1 == .skip(.notEntry))
        #expect(s1.lastState[.a] == .outside)
        #expect(CommuteUnitTests.eval(at: "2026-11-17T07:20:00+07:00", from: s1).0 == .start(.towardB, dateKey: "2026-11-17"))
        // The future key survives loading (within 8 days) and blocks only its own day.
        let back = try? CommuteStoreCodec.decodeState(try CommuteStoreCodec.encodeState(future), todayKey: "2026-11-17")
        #expect(back?.firedKeys == ["towardB@2026-11-18"])
    }

    @Test("clock set back: a duplicate (same date, same state) is still a duplicate; an older event dated in the future too")
    func clockSetBackDuplicates() {
        let at = "2026-11-17T09:00:00+07:00"
        let s = CommuteState(revision: 1, lastState: [.a: .outside], lastEventAtMs: [.a: CS.ms(at)])
        #expect(CommuteUnitTests.eval(.a, .outside, at: at, from: s, processedAt: "2026-11-17T07:00:00+07:00").0
            == .skip(.duplicate))
        // Event dated after now (age < 0): not stale (review C1 #7), still has to pass the window.
        #expect(CommuteUnitTests.eval(at: "2026-11-17T07:30:00+07:00", processedAt: "2026-11-17T07:00:00+07:00").0
            == .start(.towardB, dateKey: "2026-11-17"))
    }

    @Test("stale boundary: age exactly 10 min starts, 10 min + 1 ms is stale")
    func staleBoundary() {
        let at = CS.ms("2026-11-17T07:30:00+07:00")
        let e = RegionEvent(identifier: "nc.r1.A", state: .inside, dateWallMs: at)
        let ok = CommuteTriggerEvaluator.evaluate(e, route: CS.route(), state: CommuteUnitTests.outside,
                                                  ctx: CS.ctx(now: at + 600_000))
        #expect(ok.0 == .start(.towardB, dateKey: "2026-11-17"))
        let stale = CommuteTriggerEvaluator.evaluate(e, route: CS.route(), state: CommuteUnitTests.outside,
                                                     ctx: CS.ctx(now: at + 600_001))
        #expect(stale.0 == .skip(.stale))
    }

    @Test("towardA (entry into B) follows the same rules: window, weekday, its own day key")
    func towardAPath() {
        let (d1, s1) = CommuteUnitTests.eval(.b, .inside, at: "2026-11-17T17:30:00+07:00")
        #expect(d1 == .start(.towardA, dateKey: "2026-11-17"))
        let fired = s1.markingFired(.towardA, dateKey: "2026-11-17")
        let (_, s2) = CommuteUnitTests.eval(.b, .outside, at: "2026-11-17T17:40:00+07:00", from: fired)
        #expect(CommuteUnitTests.eval(.b, .inside, at: "2026-11-17T17:50:00+07:00", from: s2).0 == .skip(.alreadyFiredToday))
        // towardB's key does not block towardA.
        let other = CommuteUnitTests.outside.markingFired(.towardB, dateKey: "2026-11-17")
        #expect(CommuteUnitTests.eval(.b, .inside, at: "2026-11-17T17:30:00+07:00", from: other).0
            == .start(.towardA, dateKey: "2026-11-17"))
        #expect(CommuteUnitTests.eval(.b, .inside, at: "2026-11-17T19:30:00+07:00").0 == .skip(.outsideWindow))
        #expect(CommuteUnitTests.eval(.b, .inside, at: "2026-11-21T17:30:00+07:00").0 == .skip(.weekday))
    }

    // MARK: Guard, codec

    @Test("guard: elapsed clock reset (reboot, elapsed < armedAt) never stops the trip; progress counts from the first fix")
    func guardEdges() {
        let g = DepartureGuardState(tripId: "t", armedAtElapsedMs: 10_000_000)
        #expect(!DepartureGuard.step(g, distanceM: 5_000, elapsedMs: 0).stop)
        #expect(!DepartureGuard.step(g, distanceM: nil, elapsedMs: 9_999_999).stop)
        #expect(DepartureGuard.step(g, distanceM: nil, elapsedMs: 12_700_000).stop)
        // First fix only after 30 min, 300 m of progress at 44 min: departed, never stopped.
        var s = DepartureGuardState(tripId: "t", armedAtElapsedMs: 0)
        s = DepartureGuard.step(s, distanceM: nil, elapsedMs: 1_800_000).0
        s = DepartureGuard.step(s, distanceM: 6_000, elapsedMs: 1_800_001).0
        let (s2, stop2) = DepartureGuard.step(s, distanceM: 5_700, elapsedMs: 2_640_000)
        #expect(s2.departed && !stop2)
        #expect(!DepartureGuard.step(s2, distanceM: 9_000, elapsedMs: 10_000_000).stop)
        // Moving away first, then back below the start by < 300 m: not departed; at 45:00 stop.
        var a = DepartureGuardState(tripId: "t", armedAtElapsedMs: 0)
        for (t, d) in [(0, 5_000), (600_000, 5_800), (1_200_000, 4_750)] {
            a = DepartureGuard.step(a, distanceM: d, elapsedMs: Int64(t)).0
        }
        #expect(!a.departed)
        #expect(DepartureGuard.step(a, distanceM: 4_750, elapsedMs: 2_700_000).stop)
        // Overflowing arithmetic never traps and never stops.
        let neg = DepartureGuardState(tripId: "t", armedAtElapsedMs: Int64.min)
        #expect(!DepartureGuard.step(neg, distanceM: nil, elapsedMs: Int64.max).stop)
    }

    @Test("codec pruning: exactly 8 days either side kept, 9 dropped; a malformed todayKey keeps everything")
    func pruneBoundaries() throws {
        let keys = ["towardB@2026-11-09", "towardB@2026-11-08", "towardA@2026-11-25", "towardA@2026-11-26",
                    "towardA@2026-11-17"]
        let s = CommuteState(revision: 1, firedKeys: keys, failureNoticeKeys: keys)
        let back = try CommuteStoreCodec.decodeState(try CommuteStoreCodec.encodeState(s), todayKey: "2026-11-17")
        let kept = ["towardB@2026-11-09", "towardA@2026-11-25", "towardA@2026-11-17"]
        #expect(back.firedKeys == kept)
        #expect(back.failureNoticeKeys == kept)
        // Across a year boundary and a leap day.
        let y = CommuteState(revision: 1, firedKeys: ["towardB@2027-12-24", "towardB@2027-12-23", "towardB@2028-03-01"])
        #expect(y.pruned(todayKey: "2028-01-01", keepDays: 8).firedKeys == ["towardB@2027-12-24"])
        #expect(y.pruned(todayKey: "2028-02-22", keepDays: 8).firedKeys == ["towardB@2028-03-01"])  // 2028-02 has 29 days
        #expect(s.pruned(todayKey: "garbage", keepDays: 8) == s)
    }
}
