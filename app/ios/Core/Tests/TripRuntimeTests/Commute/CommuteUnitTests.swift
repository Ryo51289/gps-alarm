import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T23.8 C1 (docs/specs/T23.8.md §7): CU01–CU14 evaluator and LocalClock, CU16 separation, CU17–CU18 departure guard,
/// CU19 redaction, CU20 store codec. The shared-fixture versions are in CommuteFixtureTests (CU15, CU27).
@Suite("T23.8 commute pure logic")
struct CommuteUnitTests {
    static let outside = CommuteState(revision: 1, lastState: [.a: .outside, .b: .outside])

    static func eval(_ point: CommutePoint = .a, _ state: RegionState = .inside, at iso: String,
                     route: CommuteRoute = CS.route(), from s: CommuteState = outside, processedAt: String? = nil,
                     offsetS: Int = 7 * 3600, access: LocationAccess = CS.fullAccess, tripActive: Bool = false,
                     osSupported: Bool = true, denied: Bool = false, rev: Int? = nil) -> (TriggerDecision, CommuteState) {
        let at = CS.ms(iso)
        let e = RegionEvent(identifier: CommuteRegionId.make(revision: rev ?? route.revision, point: point), state: state,
                            dateWallMs: at, authorizationDenied: denied)
        return CommuteTriggerEvaluator.evaluate(
            e, route: route, state: s,
            ctx: CS.ctx(now: processedAt.map(CS.ms) ?? at, offsetS: offsetS, access: access, tripActive: tripActive,
                        osSupported: osSupported))
    }

    // MARK: Evaluator

    @Test("CU01 entry into A on Tuesday 07:30 (+7) starts towardB")
    func cu01() {
        let (d, s) = Self.eval(at: "2026-11-17T07:30:00+07:00")
        #expect(d == .start(.towardB, dateKey: "2026-11-17"))
        #expect(s.lastState[.a] == .inside)
        #expect(s.firedKeys.isEmpty)  // consumed by the controller only after `.started` (D7)
    }

    @Test("CU02 06:59:59 and 08:00:00 are outside [07:00, 08:00)")
    func cu02() {
        #expect(Self.eval(at: "2026-11-17T06:59:59+07:00").0 == .skip(.outsideWindow))
        #expect(Self.eval(at: "2026-11-17T08:00:00+07:00").0 == .skip(.outsideWindow))
        #expect(Self.eval(at: "2026-11-17T07:00:00+07:00").0 == .start(.towardB, dateKey: "2026-11-17"))
    }

    @Test("CU03 Sunday is not Monday–Friday")
    func cu03() {
        #expect(Self.eval(at: "2026-11-22T07:30:00+07:00").0 == .skip(.weekday))
    }

    @Test("CU04 first determination inside never starts; state becomes inside")
    func cu04() {
        let (d, s) = Self.eval(at: "2026-11-17T07:30:00+07:00", from: CommuteState(revision: 1))
        #expect(d == .skip(.firstDetermination))
        #expect(s.lastState[.a] == .inside)
    }

    @Test("CU05 out and in again the same day: alreadyFiredToday")
    func cu05() {
        let (d1, s1) = Self.eval(at: "2026-11-17T07:30:00+07:00")
        guard case let .start(dir, key) = d1 else { Issue.record("expected start"); return }
        let fired = s1.markingFired(dir, dateKey: key)
        let (d2, s2) = Self.eval(.a, .outside, at: "2026-11-17T07:40:00+07:00", from: fired)
        #expect(d2 == .skip(.notEntry))
        #expect(Self.eval(at: "2026-11-17T07:50:00+07:00", from: s2).0 == .skip(.alreadyFiredToday))
    }

    @Test("CU06 trip active: skip without day key; after the trip a new entry starts")
    func cu06() {
        let (d1, s1) = Self.eval(at: "2026-11-17T07:30:00+07:00", tripActive: true)
        #expect(d1 == .skip(.tripActive))
        #expect(s1.firedKeys.isEmpty)
        let (_, s2) = Self.eval(.a, .outside, at: "2026-11-17T07:35:00+07:00", from: s1)
        #expect(Self.eval(at: "2026-11-17T07:40:00+07:00", from: s2).0 == .start(.towardB, dateKey: "2026-11-17"))
    }

    @Test("CU07 towardA off / route off")
    func cu07() {
        let offA = CS.route(towardA: CS.window(1050, 1170, enabled: false))
        #expect(Self.eval(.b, at: "2026-11-17T17:40:00+07:00", route: offA).0 == .skip(.directionDisabled))
        #expect(Self.eval(.b, at: "2026-11-17T17:40:00+07:00", route: CS.route(enabled: false)).0 == .skip(.routeDisabled))
        #expect(Self.eval(.b, at: "2026-11-17T17:40:00+07:00").0 == .start(.towardA, dateKey: "2026-11-17"))
    }

    @Test("CU08 overlapping windows: B reached during the towardB trip, still in B afterwards → no towardA until out and in")
    func cu08() {
        let r = CS.route(towardB: CS.window(420, 1200), towardA: CS.window(420, 1200))
        var (d, s) = Self.eval(at: "2026-11-17T07:30:00+07:00", route: r)
        #expect(d == .start(.towardB, dateKey: "2026-11-17"))
        s = s.markingFired(.towardB, dateKey: "2026-11-17")
        (d, s) = Self.eval(.b, at: "2026-11-17T08:10:00+07:00", route: r, from: s, tripActive: true)
        #expect(d == .skip(.tripActive))
        (d, s) = Self.eval(.b, at: "2026-11-17T08:30:00+07:00", route: r, from: s)
        #expect(d == .skip(.notEntry))
        (d, s) = Self.eval(.b, .outside, at: "2026-11-17T09:00:00+07:00", route: r, from: s)
        #expect(d == .skip(.notEntry))
        (d, s) = Self.eval(.b, at: "2026-11-17T17:00:00+07:00", route: r, from: s)
        #expect(d == .start(.towardA, dateKey: "2026-11-17"))
    }

    @Test("CU09 same wall ms: +7 → 07:30 starts, +9 → 09:30 outside the window")
    func cu09() {
        #expect(Self.eval(at: "2026-11-17T00:30:00Z").0 == .start(.towardB, dateKey: "2026-11-17"))
        #expect(Self.eval(at: "2026-11-17T00:30:00Z", offsetS: 9 * 3600).0 == .skip(.outsideWindow))
    }

    @Test("CU10 event at 07:58 processed 08:04 starts; processed 08:09 is stale; exactly 10 min is not")
    func cu10() {
        let at = "2026-11-17T07:58:00+07:00"
        #expect(Self.eval(at: at, processedAt: "2026-11-17T08:04:00+07:00").0 == .start(.towardB, dateKey: "2026-11-17"))
        #expect(Self.eval(at: at, processedAt: "2026-11-17T08:08:00+07:00").0 == .start(.towardB, dateKey: "2026-11-17"))
        let (d, s) = Self.eval(at: at, processedAt: "2026-11-17T08:09:00+07:00")
        #expect(d == .skip(.stale))
        #expect(s.lastState[.a] == .inside)  // the region state is still learnt
    }

    @Test("CU11 the same (identifier, date, state) twice: duplicate, state unchanged")
    func cu11() {
        let (_, s1) = Self.eval(at: "2026-11-17T07:30:00+07:00")
        let (d2, s2) = Self.eval(at: "2026-11-17T07:30:00+07:00", from: s1)
        #expect(d2 == .skip(.duplicate))
        #expect(s2 == s1)
        // Same date, other state: not a duplicate.
        #expect(Self.eval(.a, .outside, at: "2026-11-17T07:30:00+07:00", from: s1).0 == .skip(.notEntry))
    }

    @Test("CU12 identifier of revision 3 with route revision 4: staleRevision, state untouched")
    func cu12() {
        let s = CommuteState(revision: 4, lastState: [.a: .outside])
        let (d, out) = Self.eval(at: "2026-11-17T07:30:00+07:00", route: CS.route(revision: 4), from: s, rev: 3)
        #expect(d == .skip(.staleRevision))
        #expect(out == s)
    }

    @Test("CU13 not Always / deny flag; then precise, services, iOS < 17")
    func cu13() {
        let wiu = LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: true, always: false)
        let at = "2026-11-17T07:30:00+07:00"
        #expect(Self.eval(at: at, access: wiu).0 == .skip(.notAlways))
        #expect(Self.eval(at: at, denied: true).0 == .skip(.notAlways))
        let reduced = LocationAccess(whenInUseOrAlways: true, fullAccuracy: false, servicesEnabled: true, always: true)
        #expect(Self.eval(at: at, access: reduced).0 == .skip(.notPrecise))
        let off = LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: false, always: true)
        #expect(Self.eval(at: at, access: off).0 == .skip(.servicesOff))
        #expect(Self.eval(at: at, access: wiu, osSupported: false).0 == .skip(.unsupportedOs))
        // Default stays false for every existing caller (T17 unchanged).
        #expect(!LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: true).always)
    }

    @Test("CU14 LocalClock: 23:59:59 / 00:00:00 change the date key; weekdays incl. leap day 2028-02-29")
    func cu14() {
        let a = LocalClock.local(CS.ms("2026-11-17T23:59:59+07:00"), offsetS: 7 * 3600)
        #expect(a == LocalTime(weekdayIndex: 1, minuteOfDay: 1439, dateKey: "2026-11-17"))
        let b = LocalClock.local(CS.ms("2026-11-18T00:00:00+07:00"), offsetS: 7 * 3600)
        #expect(b == LocalTime(weekdayIndex: 2, minuteOfDay: 0, dateKey: "2026-11-18"))
        #expect(LocalClock.local(CS.ms("2028-02-29T12:00:00Z"), offsetS: 0).dateKey == "2028-02-29")
        #expect(LocalClock.local(CS.ms("2028-02-29T12:00:00Z"), offsetS: 0).weekdayIndex == 1)  // Tuesday
        #expect(LocalClock.local(CS.ms("2028-02-29T23:59:59Z"), offsetS: 1).dateKey == "2028-03-01")
        #expect(LocalClock.local(CS.ms("2027-02-28T23:59:59Z"), offsetS: 1).dateKey == "2027-03-01")
        #expect(LocalClock.local(CS.ms("2100-02-28T23:59:59Z"), offsetS: 1).dateKey == "2100-03-01")
        #expect(LocalClock.local(0, offsetS: 0) == LocalTime(weekdayIndex: 3, minuteOfDay: 0, dateKey: "1970-01-01"))
        #expect(LocalClock.local(-1, offsetS: 0) == LocalTime(weekdayIndex: 2, minuteOfDay: 1439, dateKey: "1969-12-31"))
        #expect(LocalClock.local(CS.ms("2026-11-16T00:00:00Z"), offsetS: -5 * 3600).dateKey == "2026-11-15")
        // Every day of 2026–2029 against Foundation's Gregorian calendar in UTC.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var t = CS.ms("2026-01-01T12:00:00Z")
        let end = CS.ms("2030-01-01T00:00:00Z")
        while t < end {
            let d = Date(timeIntervalSince1970: Double(t) / 1000)
            let c = cal.dateComponents([.year, .month, .day, .weekday], from: d)
            let l = LocalClock.local(t, offsetS: 0)
            let key = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
            #expect(l.dateKey == key)
            #expect(l.weekdayIndex == (c.weekday! + 5) % 7)  // Calendar: 1 = Sunday
            #expect(LocalClock.dayNumber(dateKey: key) == t / 86_400_000)
            t += 86_400_000
        }
    }

    @Test("dayNumber rejects malformed and impossible keys")
    func dayNumber() {
        #expect(LocalClock.dayNumber(dateKey: "1970-01-01") == 0)
        for bad in ["", "2026-1-01", "2026-13-01", "2026-02-29", "2027-04-31", "2026-00-10", "2026-11-00", "0000-01-01",
                    "2026/11/17", "2026-11-17x", "２０２６-11-17"] {
            #expect(LocalClock.dayNumber(dateKey: bad) == nil, "\(bad)")
        }
        #expect(LocalClock.dayNumber(dateKey: "2028-02-29") != nil)
    }

    @Test("region identifiers round-trip; only the canonical form parses")
    func identifiers() {
        #expect(CommuteRegionId.make(revision: 7, point: .b) == "nc.r7.B")
        #expect(CommuteRegionId.parse("nc.r7.B")! == (7, .b))
        #expect(CommuteRegionId.parse("nc.r0.A")! == (0, .a))
        for bad in ["nc.r7", "nc.r.A", "nc.r07.A", "nc.r+7.A", "nc.r-7.A", "nc.7.A", "xx.r7.A", "nc.r7.A.x", "nc.r7.b",
                    "nc.r99999999999999999999.A"] {
            #expect(CommuteRegionId.parse(bad) == nil, "\(bad)")
        }
    }

    @Test("a state of an older revision is rebased: region states forgotten, day keys kept")
    func rebase() {
        let s = CommuteState(revision: 1, lastState: [.a: .outside], lastEventAtMs: [.a: 5], firedKeys: ["towardB@2026-11-17"])
        let (d, out) = Self.eval(at: "2026-11-18T07:30:00+07:00", route: CS.route(revision: 2), from: s)
        #expect(d == .skip(.firstDetermination))
        #expect(out.revision == 2)
        #expect(out.firedKeys == ["towardB@2026-11-17"])
        #expect(s.rebased(to: 1) == s)
    }

    @Test("failure notice: once per direction per day")
    func failureNotice() {
        let s = CommuteState(revision: 1)
        let (s1, n1) = s.markingFailureNotice(.towardB, dateKey: "2026-11-17")
        let (s2, n2) = s1.markingFailureNotice(.towardB, dateKey: "2026-11-17")
        let (_, n3) = s2.markingFailureNotice(.towardA, dateKey: "2026-11-17")
        #expect(n1 && !n2 && n3)
        #expect(s2.failureNoticeKeys == ["towardB@2026-11-17"])
        #expect(s1.markingFired(.towardB, dateKey: "x").markingFired(.towardB, dateKey: "x").firedKeys == ["towardB@x"])
    }

    // MARK: Validator

    @Test("CU16 A–B 1 500 m with DISTANCE 1 000 (needs 2 000) and 2 500 m with DISTANCE 2 000 (needs 3 000): tooClose")
    func cu16() {
        // 1 m of latitude = 1 / 111 195.08 degree on the meridian.
        let r1 = CS.route(bLat: 21.0 + 1_500 / 111_195.08)
        #expect(abs(CommuteRouteValidator.distanceM(r1.aLat, r1.aLng, r1.bLat, r1.bLng) - 1_500) < 0.01)
        #expect(CommuteRouteValidator.requiredSeparationM(r1) == 2_000)
        #expect(CommuteRouteValidator.validate(r1) == "route: tooClose")
        let r2 = CS.route(bLat: 21.0 + 2_500 / 111_195.08, templateB: CS.template("B", distanceM: 2_000),
                          templateA: CS.template("A", distanceM: 2_000))
        #expect(CommuteRouteValidator.requiredSeparationM(r2) == 3_000)
        #expect(CommuteRouteValidator.validate(r2) == "route: tooClose")
        let r3 = CS.route(bLat: 21.0 + 3_001 / 111_195.08, templateB: CS.template("B", distanceM: 2_000),
                          templateA: CS.template("A", distanceM: 2_000))
        #expect(CommuteRouteValidator.validate(r3) == nil)
        let time = CS.template("B", mode: .time, distanceM: nil, timeMin: 15)
        #expect(CommuteRouteValidator.requiredSeparationM(CS.route(templateB: time, templateA: time)) == 5_075)
        #expect(CommuteRouteValidator.validate(CS.route(templateB: time, templateA: time)) == "route: tooClose")
        #expect(CommuteRouteValidator.validate(CS.route()) == nil)
        // Review C1 #1: SMART bus on 2 200 m would alarm at the pickup point (needs 3 686 m).
        let smart = CS.template("B", mode: .smart, distanceM: nil)
        let r4 = CS.route(bLat: 21.0 + 2_200 / 111_195.08, templateB: smart, templateA: smart)
        #expect(CommuteRouteValidator.validate(r4) == "route: tooClose")
        let sep = CommuteRouteValidator.separation(r4)
        #expect(sep.requiredM == 3_686)
        #expect(sep.actualM == 2_199 || sep.actualM == 2_200)  // floor of ~2 200 m (ULP of the latitude)
        let r5 = CS.route(bLat: 21.0 + 3_800 / 111_195.08, templateB: smart, templateA: smart)
        #expect(CommuteRouteValidator.validate(r5) == nil)
    }

    @Test("validator: names too long, simulated template, NaN coordinate")
    func validatorExtra() {
        let long = String(repeating: "x", count: 201)
        let r = CommuteRoute(revision: 1, enabled: true, nameA: long, nameB: "B", aLat: 21, aLng: 105.8, bLat: 21.045,
                             bLng: 105.8, towardB: CS.window(), towardA: CS.window(1050, 1170),
                             templateTowardB: CS.template("B"), templateTowardA: CS.template("A"))
        #expect(CommuteRouteValidator.validate(r) == "nameA: tooLong")
        let sim = CS.template("B").with(simulation: SimSpec(traceId: "x", speedFactor: 10))
        #expect(CommuteRouteValidator.validate(CS.route(templateB: sim)) == "templateTowardB.simulation: notAllowed")
        #expect(CommuteRouteValidator.validate(CS.route(bLat: .nan)) == "bLat: outOfRange")
    }

    // MARK: Departure guard

    static func runGuard(_ samples: [(Int64, Int?)]) -> [(DepartureGuardState, Bool)] {
        var s = DepartureGuardState(tripId: "t1", armedAtElapsedMs: 1_000)
        return samples.map { (t, d) in
            let (n, stop) = DepartureGuard.step(s, distanceM: d, elapsedMs: 1_000 + t)
            s = n
            return (n, stop)
        }
    }

    @Test("CU17 5 000 → 4 650 m within 20 min: departed, never stopped at 45 min")
    func cu17() {
        var samples: [(Int64, Int?)] = []
        for i in 0...20 { samples.append((Int64(i) * 60_000, 5_000 - i * 350 / 20)) }
        samples.append((45 * 60_000, 4_900))
        samples.append((90 * 60_000, nil))
        let out = Self.runGuard(samples)
        #expect(out.allSatisfy { !$0.1 })
        #expect(!out[17].0.departed)  // 297 m of progress
        #expect(out[18].0.departed)  // 315 m
        #expect(out.last!.0.departed)
        #expect(out.last!.0.startDistanceM == 5_000)
        #expect(out.last!.0.minDistanceM == 4_685)  // frozen once departed (§5.4: departed → no more updates)
    }

    @Test("CU18 5 000 ± 50 m for 45 min, or no fix at all: false at 44:59, true at 45:00")
    func cu18() {
        var samples: [(Int64, Int?)] = []
        var t: Int64 = 0
        var k = 0
        while t < 2_699_000 {
            samples.append((t, 5_000 + (k % 2 == 0 ? 50 : -50)))
            t += 5_000
            k += 1
        }
        samples.append((2_699_000, 5_050))
        samples.append((2_700_000, 4_950))
        let out = Self.runGuard(samples)
        #expect(out.dropLast().allSatisfy { !$0.1 })
        #expect(out.last!.1)
        #expect(!out.last!.0.departed)
        let none = Self.runGuard([(0, nil), (2_699_000, nil), (2_700_000, nil)])
        #expect(none.map(\.1) == [false, false, true])
        #expect(none.last!.0.startDistanceM == nil)
    }

    @Test("guard: exactly 300 m of progress departs; 299 m does not")
    func guardThreshold() {
        #expect(Self.runGuard([(0, 5_000), (60_000, 4_700)]).last!.0.departed)
        #expect(!Self.runGuard([(0, 5_000), (60_000, 4_701)]).last!.0.departed)
        // Moving away never counts as progress.
        #expect(!Self.runGuard([(0, 5_000), (60_000, 5_400)]).last!.0.departed)
    }

    // MARK: Redaction, store

    @Test("CU19 descriptions carry no coordinates, place names or distances")
    func cu19() {
        let r = CS.route()
        let g = DepartureGuardState(tripId: "t1", armedAtElapsedMs: 5, startDistanceM: 4_321, minDistanceM: 4_123)
        let s = CommuteState(revision: 3, lastState: [.a: .inside], lastEventAtMs: [.a: 9], firedKeys: ["towardB@2026-11-17"],
                             guardTrip: g)
        let rec = AutoStartRecord(tripId: "t1", direction: .towardB, revision: 3, startedAtWallMs: 1_000)
        let texts = [String(describing: r), "\(r)", String(reflecting: r), "\(s)", String(reflecting: s), "\(g)",
                     String(reflecting: g), "\(rec)", String(reflecting: rec)]
        for t in texts {
            for banned in ["21.0", "105.8", "21.045", "Trạm", "4321", "4123", "4_321"] {
                #expect(!t.contains(banned), "\(t) contains \(banned)")
            }
        }
        #expect("\(r)" == "CommuteRoute(<redacted>)")
    }

    @Test("CU20 state round-trips; day keys older than 8 days and malformed keys are dropped on load")
    func cu20() throws {
        let g = DepartureGuardState(tripId: "t9", armedAtElapsedMs: 77, startDistanceM: 5_000, minDistanceM: 4_900)
        let s = CommuteState(revision: 5, lastState: [.a: .outside, .b: .inside], lastEventAtMs: [.a: 1, .b: 2],
                             firedKeys: ["towardB@2026-11-09", "towardB@2026-11-08", "towardA@2026-11-17", "junk",
                                         "towardX@2026-11-17", "towardB@2026-11-25", "towardB@2026-11-26"],
                             failureNoticeKeys: ["towardA@2026-11-01", "towardA@2026-11-16"], guardTrip: g)
        let data = try CommuteStoreCodec.encodeState(s)
        let back = try CommuteStoreCodec.decodeState(data, todayKey: "2026-11-17")
        #expect(back.revision == 5)
        #expect(back.lastState == s.lastState)
        #expect(back.lastEventAtMs == s.lastEventAtMs)
        #expect(back.guardTrip == g)
        #expect(back.firedKeys == ["towardB@2026-11-09", "towardA@2026-11-17", "towardB@2026-11-25"])
        #expect(back.failureNoticeKeys == ["towardA@2026-11-16"])
        // Points are object keys ("A", "B"), not an array of pairs.
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"lastState\":{\"A\":\"outside\",\"B\":\"inside\"}"))
    }

    @Test("store codec: route and auto-start records round-trip; version and corruption detected")
    func codec() throws {
        let r = CS.route(templateB: CS.template("B", mode: .time, distanceM: nil, timeMin: 20))
        #expect(try CommuteStoreCodec.decodeRoute(try CommuteStoreCodec.encodeRoute(r)) == r)
        let recs = [AutoStartRecord(tripId: "a", direction: .towardB, revision: 1, startedAtWallMs: 10),
                    AutoStartRecord(tripId: "b", direction: .towardA, revision: 2, startedAtWallMs: 20)]
        #expect(try CommuteStoreCodec.decodeAutoStarts(try CommuteStoreCodec.encodeAutoStarts(recs)) == recs)
        #expect(throws: CommuteStoreError.version) {
            try CommuteStoreCodec.decodeAutoStarts(Data("{\"version\":2,\"records\":[]}".utf8))
        }
        #expect(throws: CommuteStoreError.corrupt) { try CommuteStoreCodec.decodeAutoStarts(Data("{".utf8)) }
        #expect(throws: CommuteStoreError.corrupt) {
            try CommuteStoreCodec.decodeState(Data("{\"version\":1,\"state\":{}}".utf8), todayKey: "2026-11-17")
        }
        let bad = String(decoding: try CommuteStoreCodec.encodeRoute(r), as: UTF8.self).replacingOccurrences(of: "\"bus\"",
                                                                                                         with: "\"tram\"")
        #expect(throws: CommuteStoreError.corrupt) { try CommuteStoreCodec.decodeRoute(Data(bad.utf8)) }
    }

    /// §5.6a table: template → (R, requiredSeparationM). Shared with CommuteSeparationEngineTests (CU28).
    static let reachTable: [(String, TripMeta, Double, Int)] = [
        ("distance 1000", CS.template("B"), 1_000, 2_000),
        ("distance 3000 x 1.5", CS.template("B", distanceM: 3_000, params: #"{"distanceModeFactor":1.5}"#), 4_500, 5_500),
        ("time 5 bus", CS.template("B", mode: .time, distanceM: nil, timeMin: 5), 1_296.296_296, 2_297),
        ("time 10 bus", CS.template("B", mode: .time, distanceM: nil, timeMin: 10), 2_685.185_185, 3_686),
        ("time 15 bus", CS.template("B", mode: .time, distanceM: nil, timeMin: 15), 4_074.074_074, 5_075),
        ("smart bus", CS.template("B", mode: .smart, distanceM: nil), 2_685.185_185, 3_686),
        ("smart train", CS.template("B", mode: .smart, distanceM: nil, vehicle: .train), 7_384.259_259, 8_385),
        ("smart coach", CS.template("B", mode: .smart, distanceM: nil, vehicle: .coach), 8_055.555_556, 9_056),
        ("smart unknown", CS.template("B", mode: .smart, distanceM: nil, vehicle: .unknown), 8_055.555_556, 9_056),
        ("smart bus slow 25", CS.template("B", mode: .smart, distanceM: nil, params: #"{"smartSlowSpeedKmh":25}"#),
         4_166.666_667, 5_167),
        ("smart bus target 1200", CS.template("B", mode: .smart, distanceM: nil, params: #"{"smartTargetS":1200}"#),
         5_462.962_963, 6_463),
        // Hint speed below minSpeedForEtaMps: no ETA before the speed is established, only the arrived radius.
        ("time 10 bus 5 km/h, no ETA", CS.template("B", mode: .time, distanceM: nil, timeMin: 10,
                                                   params: #"{"expectedSpeedKmhBus":5,"minSpeedForEtaMps":3.0}"#), 300, 2_000),
    ]

    @Test("§5.6a stationary reach R and requiredSeparationM of every template of the table")
    func reachTableValues() {
        for (name, m, r, need) in Self.reachTable {
            #expect(abs(CommuteRouteValidator.stationaryReachM(m) - r) < 1e-5, "\(name)")
            #expect(CommuteRouteValidator.requiredSeparationM(CS.route(templateB: m, templateA: m)) == need, "\(name)")
        }
        // The larger of the two templates wins, whatever the direction.
        let d = CS.template("A")
        let t = CS.template("A", mode: .smart, distanceM: nil, vehicle: .train)
        #expect(CommuteRouteValidator.requiredSeparationM(CS.route(templateB: d, templateA: t)) == 8_385)
        #expect(CommuteRouteValidator.requiredSeparationM(CS.route(templateB: t, templateA: d)) == 8_385)
        // Malformed overrides: default params, like the engine.
        let bad = CS.template("B", mode: .smart, distanceM: nil, params: "{not json")
        #expect(CommuteRouteValidator.stationaryReachM(bad) == CommuteRouteValidator.stationaryReachM(
            CS.template("B", mode: .smart, distanceM: nil)))
    }

    @Test("CU29 unknown keeps the last known state: outside→unknown→inside starts; inside→unknown→inside does not")
    func cu29() {
        let (d1, s1) = Self.eval(.a, .unknown, at: "2026-11-17T07:20:00+07:00")
        #expect(d1 == .skip(.notEntry))
        #expect(s1 == Self.outside)  // neither lastState nor lastEventAtMs changed
        #expect(Self.eval(at: "2026-11-17T07:30:00+07:00", from: s1).0 == .start(.towardB, dateKey: "2026-11-17"))

        let inside = CommuteState(revision: 1, lastState: [.a: .inside], lastEventAtMs: [.a: CS.ms("2026-11-17T07:00:00+07:00")])
        let (d2, s2) = Self.eval(.a, .unknown, at: "2026-11-17T07:20:00+07:00", from: inside)
        #expect(d2 == .skip(.notEntry))
        #expect(s2 == inside)
        #expect(Self.eval(at: "2026-11-17T07:30:00+07:00", from: s2).0 == .skip(.notEntry))

        let (d3, s3) = Self.eval(.a, .unknown, at: "2026-11-17T07:20:00+07:00", from: CommuteState(revision: 1))
        #expect(d3 == .skip(.notEntry))
        #expect(s3.lastState[.a] == nil)
        #expect(Self.eval(at: "2026-11-17T07:30:00+07:00", from: s3).0 == .skip(.firstDetermination))
        // An unknown twice with the same date is never a duplicate (nothing recorded) and stays notEntry.
        #expect(Self.eval(.a, .unknown, at: "2026-11-17T07:20:00+07:00", from: s3).0 == .skip(.notEntry))
    }

    @Test("CU30 an older event delivered late is outOfOrder (state and date unchanged) unless the clock was set back")
    func cu30() {
        let (d1, s1) = Self.eval(at: "2026-11-17T07:30:00+07:00")
        #expect(d1 == .start(.towardB, dateKey: "2026-11-17"))
        let (d2, s2) = Self.eval(.a, .outside, at: "2026-11-17T07:20:00+07:00", from: s1,
                                 processedAt: "2026-11-17T07:31:00+07:00")
        #expect(d2 == .skip(.outOfOrder))
        #expect(s2 == s1)
        #expect(s2.lastEventAtMs[.a] == CS.ms("2026-11-17T07:30:00+07:00"))
        #expect(Self.eval(at: "2026-11-17T07:40:00+07:00", from: s2).0 == .skip(.notEntry))
        // Older unknown: outOfOrder comes first.
        #expect(Self.eval(.a, .unknown, at: "2026-11-17T07:20:00+07:00", from: s1,
                          processedAt: "2026-11-17T07:31:00+07:00").0 == .skip(.outOfOrder))
        // Same date, other state: a new event, not out of order.
        #expect(Self.eval(.a, .outside, at: "2026-11-17T07:30:00+07:00", from: s1).0 == .skip(.notEntry))
        // Exactly at the processing time: the recorded date is not in the future, still out of order.
        #expect(Self.eval(.a, .outside, at: "2026-11-17T07:20:00+07:00", from: s1,
                          processedAt: "2026-11-17T07:30:00+07:00").0 == .skip(.outOfOrder))

        // Clock set back: the recorded date lies after the processing time → the older event is taken.
        let future = CommuteState(revision: 1, lastState: [.a: .inside, .b: .outside],
                                  lastEventAtMs: [.a: CS.ms("2026-11-17T09:00:00+07:00")])
        let (d3, s3) = Self.eval(.a, .outside, at: "2026-11-17T07:20:00+07:00", from: future)
        #expect(d3 == .skip(.notEntry))
        #expect(s3.lastState[.a] == .outside)
        #expect(s3.lastEventAtMs[.a] == CS.ms("2026-11-17T07:20:00+07:00"))
        #expect(Self.eval(at: "2026-11-17T07:30:00+07:00", from: s3).0 == .start(.towardB, dateKey: "2026-11-17"))
    }

    @Test("D17: DepartureGuardState of a C1 state file (no alarmedBeforeDeparture key) reads as false; the flag round-trips")
    func guardDecodeOldFile() throws {
        let old = #"{"version":1,"state":{"revision":2,"lastState":{"A":"outside"},"lastEventAtMs":{"A":5},"#
            + #""firedKeys":[],"failureNoticeKeys":[],"guardTrip":{"tripId":"t1","armedAtElapsedMs":7,"#
            + #""startDistanceM":5000,"minDistanceM":4900,"departed":false}}}"#
        let s = try CommuteStoreCodec.decodeState(Data(old.utf8), todayKey: "2026-11-17")
        let g = try #require(s.guardTrip)
        #expect(g == DepartureGuardState(tripId: "t1", armedAtElapsedMs: 7, startDistanceM: 5_000, minDistanceM: 4_900))
        #expect(!g.alarmedBeforeDeparture)
        // Without a fix yet (nil distances omitted).
        let noFix = #"{"version":1,"state":{"revision":2,"lastState":{},"lastEventAtMs":{},"firedKeys":[],"#
            + #""failureNoticeKeys":[],"guardTrip":{"tripId":"t2","armedAtElapsedMs":0,"departed":true}}}"#
        let g2 = try #require(try CommuteStoreCodec.decodeState(Data(noFix.utf8), todayKey: "2026-11-17").guardTrip)
        #expect(g2.startDistanceM == nil && g2.departed && !g2.alarmedBeforeDeparture)
        // Flag set → written and read back; description shows the flag, no distance.
        var flagged = g
        flagged.alarmedBeforeDeparture = true
        let back = try CommuteStoreCodec.decodeState(
            try CommuteStoreCodec.encodeState(CommuteState(revision: 2, guardTrip: flagged)), todayKey: "2026-11-17")
        #expect(back.guardTrip == flagged)
        #expect("\(flagged)".contains("alarmedBeforeDeparture=true"))
        #expect(!"\(flagged)".contains("5000") && !"\(flagged)".contains("4900"))
        // The step function never touches the flag.
        #expect(DepartureGuard.step(flagged, distanceM: 4_000, elapsedMs: 10).0.alarmedBeforeDeparture)
        // Missing mandatory key → corrupt.
        let broken = #"{"version":1,"state":{"revision":2,"lastState":{},"lastEventAtMs":{},"firedKeys":[],"#
            + #""failureNoticeKeys":[],"guardTrip":{"tripId":"t2","armedAtElapsedMs":0}}}"#
        #expect(throws: CommuteStoreError.corrupt) {
            try CommuteStoreCodec.decodeState(Data(broken.utf8), todayKey: "2026-11-17")
        }
    }

    @Test("store codec: an encoding failure throws .encode instead of returning empty bytes (review C1 #6)")
    func codecEncodeFailure() {
        #expect(throws: CommuteStoreError.encode) { try CommuteStoreCodec.encodeRoute(CS.route(bLat: .nan)) }
        #expect(throws: CommuteStoreError.encode) { try CommuteStoreCodec.encodeRoute(CS.route(bLat: .infinity)) }
        #expect("\(CommuteStoreError.encode)" == "commuteStore: encode")
    }

    @Test("test helper CS.int: whole numbers only (review C1 #5)")
    func intHelper() throws {
        #expect(CS.int(420) == 420)
        #expect(CS.int(420.0) == 420)
        #expect(CS.int(420.5) == nil)
        #expect(CS.int(NSNumber(value: 420.5)) == nil)
        #expect(CS.int(Double.nan) == nil)
        #expect(CS.int("420") == nil)
        #expect(CS.int(nil) == nil)
        let o = try JSONSerialization.jsonObject(with: Data(#"{"a":420,"b":420.5,"c":1794880800000}"#.utf8))
        let d = try #require(o as? [String: Any])
        #expect(CS.int(d["a"]) == 420)
        #expect(CS.int(d["b"]) == nil)
        #expect(CS.int64(d["c"]) == 1_794_880_800_000)
    }

    @Test("§5.6 constants")
    func constants() {
        let c = CommuteConstants.default
        #expect(c.regionRadiusM == 200 && c.eventMaxStaleMs == 600_000 && c.departTimeoutMs == 2_700_000)
        #expect(c.departMinProgressM == 300 && c.minAbM == 2_000 && c.abThresholdMarginM == 1_000)
        #expect(c.windowMinMin == 15 && c.windowMaxMin == 720 && c.firedKeepDays == 8 && c.minIosMajor == 17)
        #expect(c.monitorName == "napstop.commute")
    }
}
