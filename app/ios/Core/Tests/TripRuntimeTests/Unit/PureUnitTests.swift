import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

@Suite("RuntimePure")
struct PureUnitTests {
    @Test("IU01 trip clock: elapsed-based, never goes back")
    func iu01() {
        let t = VirtualTime(wallBase: 1_000_000, elapsedBase: 50_000)
        var c = TripClock(anchor: .now(t))
        t.v = 30_000
        t.shiftWall(-10_000)
        #expect(c.now(t) == 1_030_000)
        #expect(c.now(t) >= 1_030_000)
        t.setElapsed(70_000)  // elapsed went back (impossible on one boot): still not smaller
        #expect(c.now(t) == 1_030_000)
    }

    @Test("IU02 anchor validity: boot id, nil fallback, wall drift 300 s")
    func iu02() {
        let t = VirtualTime(wallBase: 1_000_000, elapsedBase: 50_000, boot: "A")
        let a = ClockAnchor.now(t)
        t.setBoot("B")
        #expect(!TripClock.anchorValid(a, t, driftMaxMs: 300_000))
        t.setBoot(nil)
        t.setElapsed(10_000)
        #expect(!TripClock.anchorValid(a, t, driftMaxMs: 300_000))
        t.setBoot("A")
        t.setElapsed(50_000)
        t.setWall(1_000_000 + 301_000)
        #expect(!TripClock.anchorValid(a, t, driftMaxMs: 300_000))
        t.setWall(1_000_000 + 299_000)
        #expect(TripClock.anchorValid(a, t, driftMaxMs: 300_000))
    }

    @Test("IU03 toWall / toTrip")
    func iu03() {
        let t = VirtualTime(wallBase: 2_000_000)
        var c = TripClock(anchor: ClockAnchor(wallMs: 1_000_000, elapsedMs: t.elapsedMs(), bootSessionId: "A"))
        #expect(c.toWall(1_060_000, t) == 2_060_000)
        #expect(c.toWall(990_000, t) == 2_000_000)
        #expect(c.toTrip(wall: 1_995_000, t) == 995_000)
    }

    @Test("IU04 FixMapper: age, invalid speed, drops, future timestamp")
    func iu04() {
        let ok = FixMapper.map(RawFix(lat: 16, lng: 107, horizontalAccuracyM: 12, speedMps: -1, timestampWallMs: 1_000_000 - 84_873),
                               nowWallMs: 1_000_000, nowTripMs: 500_000)
        #expect(ok?.fixAtMs == Int64(415_127))  // 500 000 − 84 873
        #expect(ok?.atMs == 500_000)
        #expect(ok?.speedMps == nil)
        for bad in [RawFix(lat: 16, lng: 107, horizontalAccuracyM: -1, speedMps: 1, timestampWallMs: 0),
                    RawFix(lat: 16, lng: 107, horizontalAccuracyM: 0, speedMps: 1, timestampWallMs: 0),
                    RawFix(lat: .nan, lng: 107, horizontalAccuracyM: 5, speedMps: 1, timestampWallMs: 0)] {
            #expect(FixMapper.map(bad, nowWallMs: 1_000_000, nowTripMs: 1) == nil)
        }
        let future = FixMapper.map(RawFix(lat: 16, lng: 107, horizontalAccuracyM: 5, speedMps: 3, timestampWallMs: 2_000_000),
                                   nowWallMs: 1_000_000, nowTripMs: 7)
        #expect(future?.fixAtMs == 7)
    }

    @Test("IU05 FixThrottle forwards the same samples as Kotlin FixFeed.nextSampleT")
    func iu05() {
        func interval(_ t: Int) -> Int64 { t < 600 ? 5_000 : t < 1800 ? 30_000 : t < 3000 ? 180_000 : 360_000 }
        var th = FixThrottle(slackMs: 500)
        var mine: [Int] = []
        for t in stride(from: 0, through: 3600, by: 5) {
            // Core Location jitter: the fix timestamp is up to 400 ms off the 5 s grid.
            let jitter = Int64((t / 5) % 3) * 200 - 200
            let f = LocationFix(atMs: Int64(t) * 1000, fixAtMs: Int64(t) * 1000 + jitter, lat: 0, lng: 0, accuracyM: 5, speedMps: nil)
            if th.forward(f, intervalMs: interval(t)) { mine.append(t) }
        }
        // Kotlin FixFeed: deliver t when t ≥ last + intervalS.
        var kotlin: [Int] = []
        var last: Int?
        for t in stride(from: 0, through: 3600, by: 5) where last == nil || t >= last! + Int(interval(t) / 1000) {
            kotlin.append(t)
            last = t
        }
        #expect(mine == kotlin)
    }

    @Test("IU06 LocationRequestMapper")
    func iu06() {
        let p = EngineParams.defaults
        #expect(LocationRequestMapper.spec(SamplingPolicy(tier: .sparse, intervalS: 180, minIntervalS: 90, accuracy: .balanced), p)
            == LocationRequestSpec(accuracy: .hundredMeters, intervalMs: 180_000))
        #expect(LocationRequestMapper.spec(SamplingPolicy(tier: .sparse, intervalS: 360, minIntervalS: 180, accuracy: .balanced), p)
            .intervalMs == 360_000)
        #expect(LocationRequestMapper.spec(SamplingPolicy(tier: .medium, intervalS: 30, minIntervalS: 15, accuracy: .high), p)
            == LocationRequestSpec(accuracy: .nearestTenMeters, intervalMs: 30_000))
        #expect(LocationRequestMapper.spec(SamplingPolicy(tier: .dense, intervalS: 5, minIntervalS: 2, accuracy: .high), p)
            == LocationRequestSpec(accuracy: .best, intervalMs: 5_000))
    }

    @Test("IU07 TripConfigValidator messages = Android TripConfigValidator.kt")
    func iu07() {
        let m = TestData.meta()
        func meta(tripId: String = "t1", name: String = "Ga", mode: AlarmMode = .distance, d: Int? = 1000, t: Int? = nil,
                  sound: String = "default", volume: Double = 0.5, params: String? = nil) -> TripMeta {
            TripMeta(tripId: tripId, destinationName: name, mode: mode, distanceThresholdM: d, timeThresholdMin: t,
                     preAlertEnabled: false, vehicleHint: .bus,
                     alarm: RingSettings(soundId: sound, volume: volume, rampUp: false, vibration: "off", flash: false,
                                         preferHeadphones: false, dismissMethod: "swipe"),
                     engineParamsJson: params)
        }
        func v(_ x: TripMeta, lat: Double = 16, lng: Double = 107, sim: SimulationInput? = nil) -> String? {
            TripConfigValidator.validate(x, destLat: lat, destLng: lng, simulation: sim)
        }
        #expect(v(m) == nil)
        #expect(v(meta(tripId: "a b")) == "tripId: format")
        #expect(v(meta(tripId: String(repeating: "a", count: 65))) == "tripId: format")
        #expect(v(meta(name: "  ")) == "destinationName: empty")
        #expect(v(meta(name: String(repeating: "x", count: 201))) == "destinationName: too long")
        #expect(v(meta(), lat: 90.0001) == "destLat: out of range")
        #expect(v(meta(), lng: 180) == "destLng: out of range")
        #expect(v(meta(d: nil)) == "distanceThresholdM: required")
        #expect(v(meta(mode: .time, d: nil, t: 61)) == "timeThresholdMin: out of range")
        #expect(v(meta(sound: "")) == "alarm.soundId: empty")
        #expect(v(meta(volume: 1.01)) == "alarm.volume: out of range")
        #expect(v(meta(), sim: SimulationInput(traceAsset: "x", speedFactor: 0.5)) == "simulation.speedFactor: out of range")
        let emoji = "😀"  // 2 UTF-16 units
        let at = String(repeating: "a", count: 16_382) + emoji
        #expect(v(meta(params: at)) == nil)
        #expect(v(meta(params: at + "a")) == "engineParamsJson: too long")
        for msg in [v(meta(name: String(repeating: "x", count: 201))), v(meta(), lat: 90.0001)] {
            #expect(!(msg ?? "").contains("90.0001") && !(msg ?? "").contains("xxx"))
        }
    }

    static func step(events: [TripEvent], phase: TripPhase = .alarming, wake: Int64? = nil,
                     fb: FallbackStatus = .confirmed) -> Step {
        let base = EngineDriverLite.view
        let view = TripView(
            tripId: "t1", atMs: base.atMs, phase: phase, gps: .ok, locationCause: .available, distanceM: 800,
            routeDistanceEstM: nil, distanceErrorM: nil, isEstimated: false, etaS: 60, etaMinS: nil, etaMaxS: nil, speedKmh: 40,
            progress: nil, alarmMarkerProgress: nil, predictedAlarmAtMs: nil, samplingPolicy: nil, fallbackAtMs: nil,
            fallbackStatus: fb, batteryPct: nil, batteryRisk: false, preAlertFired: false, alarmAtMs: nil, alarmReason: nil,
            alarmRinging: true, snoozeCount: 0, snoozeUntilMs: nil, overshootPastM: nil, outcome: nil, vehicleGuess: .train,
            travelledM: 0, droppedFixes: 0, wakeAtMs: wake)
        return Step(state: EngineDriverLite.state, events: events, view: view)
    }

    static func planInput(_ step: Step, current: Int64?, facts: RingFacts = .none, now: Int64 = 1_000_000,
                          mode: TrackingMode = .tracking) -> PlanInput {
        var l = AlarmLedger.empty
        if let c = current {
            l.current = AlarmSlotRec(alarmId: "A", kind: .fallback, generation: 1, targetAtMs: c, targetAtWallMs: c,
                                     setAtWallMs: 0, channel: .alarmKit)
        }
        return PlanInput(prevView: nil, step: step, meta: TestData.meta(), mode: mode, facts: facts, ledger: l,
                         timerDueTripMs: nil, params: .defaults, nowWallMs: now, nowTripMs: now, liveSlot: l.current)
    }

    static let alarmEv = TripEvent.alarm(.init(atMs: 1_000_000, reason: .distance, ringNow: true, snoozeAllowed: true,
                                                distanceM: 900, etaS: 60, batteryPct: nil))
    static let denseEv = TripEvent.samplingPolicyChanged(.init(atMs: 1_000_000, policy: SamplingPolicy(
        tier: .dense, intervalS: 5, minIntervalS: 2, accuracy: .high)))
    static let supersededEv = TripEvent.fallbackAlarmChanged(.init(atMs: 1_000_000, fallbackAtMs: nil, cause: .superseded))

    @Test("IU08 plan: guard, persistNow, ringNow, sampling, timer, persist, publish; SUPERSEDED cancels nothing")
    func iu08() {
        let fx = EffectPlanner.plan(Self.planInput(Self.step(events: [Self.alarmEv, Self.denseEv, Self.supersededEv]),
                                                   current: 1_000_000 + 3 * 3_600_000))
        #expect(fx == [.armRingGuard(guardAtWallMs: 1_030_000), .persistNow(budgetMs: 300),
                       .ringNow(RingRequest(tripId: "t1", reason: .distance, snoozeAllowed: true, distanceM: 900, etaS: 60,
                                            batteryPct: nil, atWallMs: 1_000_000)),
                       .applySampling(LocationRequestSpec(accuracy: .best, intervalMs: 5_000)),
                       .setTimer(dueTripMs: 1_060_000), .persist, .publish])
    }

    @Test("IU09 plan: slot already within 30 s → no guard")
    func iu09() {
        let fx = EffectPlanner.plan(Self.planInput(Self.step(events: [Self.alarmEv]), current: 1_020_000))
        #expect(!fx.contains { if case .armRingGuard = $0 { return true }; return false })
    }

    @Test("IU10 plan: fallback ringing → FallbackFired(toTrip(W)), no ringNow")
    func iu10() {
        let facts = RingFacts(ringingNow: true, ringingKind: .fallback, ringStartedAtWallMs: 990_000, ringingAlarmId: "A")
        let fx = EffectPlanner.plan(Self.planInput(Self.step(events: [Self.alarmEv]), current: 990_000, facts: facts))
        #expect(fx.contains(.feed(.fallbackFired(atMs: 1_000_000, firedAtMs: 990_000))))
        #expect(!fx.contains { if case .ringNow = $0 { return true }; return false })
    }

    @Test("IU11 plan: fallback rang and stopped (not ringing now) → ringNow")
    func iu11() {
        let fx = EffectPlanner.plan(Self.planInput(Self.step(events: [Self.alarmEv]), current: nil))
        #expect(fx.contains { if case .ringNow = $0 { return true }; return false })
    }

    @Test("IU19 StoredTripCodec round trip; version 2 / bad JSON → error")
    func iu19() throws {
        var s = EngineDriverLite.state
        for i in 0..<30 {
            s = TripEngine.reduce(s, .locationFix(LocationFix(atMs: 1_000 + Int64(i) * 5_000, fixAtMs: 1_000 + Int64(i) * 5_000,
                                                                 lat: 16.0 + Double(i) * 0.001, lng: 107, accuracyM: 8,
                                                                 speedMps: 15))).state
        }
        let t = StoredTrip(meta: TestData.meta(), anchor: ClockAnchor(wallMs: 1, elapsedMs: 2, bootSessionId: nil),
                           engineSnapshot: TripEngine.encodeSnapshot(s), savedAtWallMs: 5)
        let back = try StoredTripCodec.decode(StoredTripCodec.encode(t))
        #expect(back == t)
        #expect(Array(back.engineSnapshot.utf8) == Array(t.engineSnapshot.utf8))
        let v2 = String(decoding: StoredTripCodec.encode(t), as: UTF8.self).replacingOccurrences(of: "\"runtimeVersion\":1",
                                                                                               with: "\"runtimeVersion\":2")
        #expect(throws: StoredTripError.version) { try StoredTripCodec.decode(Data(v2.utf8)) }
        #expect(throws: StoredTripError.corrupt) { try StoredTripCodec.decode(Data("{x".utf8)) }
        let store = FakeStore(log: OpLog())
        store.setActiveRaw(Data(v2.utf8))
        #expect(throws: StoredTripError.self) { try store.readActive() }
        #expect(store.activeTrip == nil)
    }

    @Test("IU21 fromEnded == fromEvent(TripEnded)")
    func iu21() throws {
        for (kind, n) in [(UserActionKind.stopTrip, 40), (.stopTrip, 1), (.stopTrip, 200)] {
            var s = EngineDriverLite.state
            for i in 0..<n {
                s = TripEngine.reduce(s, .locationFix(LocationFix(atMs: 1_000 + Int64(i) * 5_000, fixAtMs: 1_000 + Int64(i) * 5_000,
                                                                     lat: 16.0 + Double(i) * 0.0003, lng: 107, accuracyM: 8,
                                                                     speedMps: 7))).state
            }
            let step = TripEngine.reduce(s, .userAction(atMs: 2_000_000, action: kind))
            var ended: TripEvent.TripEnded?
            for case let .tripEnded(e) in step.events { ended = e }
            let e = try #require(ended)
            #expect(FinishedRecordBuilder.fromEnded(step.state) == FinishedRecordBuilder.fromEvent(tripId: "t1", e))
        }
    }

    @Test("IU27 LedgerReconciler: adopt newest slot, cancel older + ended trips")
    func iu27() {
        func a(_ id: String, _ trip: String, _ kind: SystemAlarmKind, _ g: Int64, _ s: SystemAlarmState) -> SystemAlarmInfo {
            SystemAlarmInfo(id: id, tripId: trip, kind: kind, generation: g, state: s, fireAtWallMs: 5_000, channel: .alarmKit)
        }
        var l = AlarmLedger.empty
        l.endedTripIds = ["old"]
        l.nextGeneration = 7
        let list = [a("g7", "t1", .fallback, 7, .scheduled), a("g8", "t1", .fallback, 8, .scheduled),
                    a("o1", "old", .fallback, 3, .scheduled), a("o2", "old", .now, 4, .alerting)]
        let r = LedgerReconciler.reconcile(l, list: list, activeTripId: "t1", nowWallMs: 4_000, toTrip: { $0 - 1_000 })
        #expect(r.ledger.current?.alarmId == "g8")
        #expect(r.ledger.current?.targetAtMs == 4_000)
        #expect(r.ledger.nextGeneration == 9)
        #expect(Set(r.actions) == Set([.cancel(id: "g7", channel: .alarmKit), .cancel(id: "o1", channel: .alarmKit),
                                       .stop(id: "o2", channel: .alarmKit)]))
    }

    @Test("IU28 RestorePlanner table (a)–(h)")
    func iu28() throws {
        var s = EngineDriverLite.state
        s = TripEngine.reduce(s, .tick(atMs: 2_000)).state
        let f0 = try #require(EngineFacts.read(s))
        let fb = try #require(f0.fallbackTargetAtMs)
        func info(_ l: AlarmLedger = .empty, events: [RingEventRec] = [], list: [SystemAlarmInfo]? = [], now: Int64,
                  facts: EngineFacts = f0) -> RestoreInfo {
            RestorePlanner.plan(facts, ledger: l, events: events, list: list, nowTripMs: now, toTrip: { $0 })
        }
        let ev = RingEventRec(tripId: "t1", alarmId: "X", kind: .fallback, action: .dismiss, atWallMs: fb + 5_000)
        #expect(info(events: [ev], now: fb + 9_000).status == .dismissed)
        #expect(info(events: [ev], now: fb + 9_000).dismissedAtMs == fb + 5_000)
        let ring = SystemAlarmInfo(id: "X", tripId: "t1", kind: .fallback, generation: 1, state: .alerting, fireAtWallMs: fb,
                                   channel: .alarmKit)
        #expect(info(list: [ring], now: fb + 1_000) == RestoreInfo(status: .rang, firedAtMs: fb))
        var lf = AlarmLedger.empty
        lf.lastFired = FiredRec(alarmId: "X", kind: .fallback, generation: 1, firedAtMs: f0.nowMs + 10, firedAtWallMs: 0)
        #expect(info(lf, now: fb + 1).status == .rang)
        var live = AlarmLedger.empty
        live.current = AlarmSlotRec(alarmId: "S", kind: .fallback, generation: 1, targetAtMs: fb, targetAtWallMs: fb,
                                    setAtWallMs: 0, channel: .alarmKit)
        let slot = SystemAlarmInfo(id: "S", tripId: "t1", kind: .fallback, generation: 1, state: .scheduled, fireAtWallMs: fb,
                                   channel: .alarmKit)
        #expect(info(live, list: [slot], now: f0.nowMs + 1).status == .pending)
        #expect(info(live, list: [], now: fb) == RestoreInfo(status: .rang, firedAtMs: fb))
        #expect(info(live, list: [], now: fb - 1).status == .missing)
        let noFb = EngineFacts(tripId: "t1", nowMs: 1, startedAtMs: 1, phase: .tracking, fallbackTargetAtMs: nil, alarmAtMs: nil,
                               alarmReason: nil, alarmLastReason: nil, alarmRinging: false, snoozeCount: 0, dismissedAtMs: nil,
                               movingTimeS: 0, movingDistM: 0, vehicleHint: .train, vehicleBusMaxAvgKmh: 30, ended: nil)
        #expect(info(now: 5, facts: noFb).status == .pending)
        #expect(info(list: nil, now: 5).status == .unknown)
    }

    @Test("IU24 interpreter: fallback alerting while now scheduled → FallbackFired once, cancel the rest")
    func iu24() {
        func a(_ id: String, _ kind: SystemAlarmKind, _ s: SystemAlarmState) -> SystemAlarmInfo {
            SystemAlarmInfo(id: id, tripId: "t1", kind: kind, generation: 1, state: s, fireAtWallMs: 100, channel: .alarmKit)
        }
        let prev = [a("F", .fallback, .scheduled), a("N", .now, .scheduled), a("G", .guardSlot, .scheduled)]
        let cur = [a("F", .fallback, .alerting), a("N", .now, .scheduled), a("G", .guardSlot, .scheduled)]
        let acts = AlarmUpdateInterpreter.interpret(tripId: "t1", prev: prev, cur: cur, ledger: .empty, expectedStops: [],
                                                    nowWallMs: 200)
        #expect(acts.filter { if case .fallbackFired = $0 { return true }; return false }.count == 1)
        #expect(acts.contains(.cancel(id: "N", channel: .alarmKit)) && acts.contains(.cancel(id: "G", channel: .alarmKit)))
        let again = AlarmUpdateInterpreter.interpret(tripId: "t1", prev: cur, cur: cur, ledger: .empty, expectedStops: [],
                                                     nowWallMs: 300)
        #expect(!again.contains { if case .fallbackFired = $0 { return true }; return false })
    }

    @Test("IU25 interpreter: now alerting cancels scheduled slots only, never an alerting one")
    func iu25() {
        func a(_ id: String, _ kind: SystemAlarmKind, _ s: SystemAlarmState) -> SystemAlarmInfo {
            SystemAlarmInfo(id: id, tripId: "t1", kind: kind, generation: 1, state: s, fireAtWallMs: 100, channel: .alarmKit)
        }
        let prev = [a("N", .now, .scheduled), a("G", .guardSlot, .scheduled), a("F", .fallback, .scheduled), a("X", .fallback, .alerting)]
        let cur = [a("N", .now, .alerting), a("G", .guardSlot, .scheduled), a("F", .fallback, .scheduled), a("X", .fallback, .alerting)]
        let acts = AlarmUpdateInterpreter.interpret(tripId: "t1", prev: prev, cur: cur, ledger: .empty, expectedStops: [],
                                                    nowWallMs: 200)
        #expect(acts.contains(.nowSeenAlerting(id: "N")))
        #expect(acts.contains(.cancel(id: "G", channel: .alarmKit)) && acts.contains(.cancel(id: "F", channel: .alarmKit)))
        #expect(!acts.contains(.cancel(id: "X", channel: .alarmKit)) && !acts.contains(.stop(id: "X", channel: .alarmKit)))
        let gone = AlarmUpdateInterpreter.interpret(tripId: "t1", prev: cur, cur: [], ledger: .empty, expectedStops: ["X"],
                                                    nowWallMs: 900)
        #expect(gone.contains(.checkGone(id: "N", goneAtWallMs: 900)))
        #expect(!gone.contains(.checkGone(id: "X", goneAtWallMs: 900)))
    }

    @Test("IU34 NativeCopy = ARB (existing keys), locale choice")
    func iu34() throws {
        func arb(_ lang: String) throws -> [String: Any] {
            let d = try Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.l10nDir)/app_\(lang).arb"))
            return try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        }
        let vi = try arb("vi"), en = try arb("en")
        for (key, pair) in NativeCopy.table {
            #expect(vi[key] as? String == pair.vi, "vi \(key)")
            #expect(en[key] as? String == pair.en, "en \(key)")
        }
        #expect(NativeCopy.localeTag(stored: "en", preferredLanguages: ["vi-VN"]) == "en")
        #expect(NativeCopy.localeTag(stored: nil, preferredLanguages: ["en-US"]) == "en")
        #expect(NativeCopy.localeTag(stored: "fr", preferredLanguages: ["vi-VN"]) == "vi")
        #expect(NativeCopy.alarmTitle(.distance, destinationName: "Ga Huế", locale: "vi") == "Sắp tới Ga Huế")
        #expect(NativeCopy.alarmTitle(.timeout, destinationName: " ", locale: "en") == "Check if you've reached your stop")
        #expect(NativeCopy.alarmTitle(.overshoot, destinationName: "X", locale: "vi") == "Có thể bạn đã đi quá X")
    }

    @Test("IU35 NoticeFormatter vi/en")
    func iu35() {
        #expect(NoticeFormatter.distance(850.4, "vi") == "850 m")
        #expect(NoticeFormatter.distance(1_249, "vi") == "1,2 km")
        #expect(NoticeFormatter.distance(12_345, "vi") == "12,3 km")
        #expect(NoticeFormatter.distance(1_249, "en") == "1.2 km")
        #expect(NoticeFormatter.distance(1_000, "en") == "1 km")
        #expect(NoticeFormatter.minutes(59) == 1)
        #expect(NoticeFormatter.minutes(600) == 10)
        #expect(NativeCopy.notice(.preAlert(distanceM: 3_000, etaS: nil, byDistance: false), destinationName: "A", locale: "vi").body
            == "Sắp tới A — còn khoảng 3 km")
        #expect(NativeCopy.notice(.preAlert(distanceM: 3_000, etaS: 600, byDistance: false), destinationName: "A", locale: "vi").body
            == "Sắp tới A — còn khoảng 10 phút")
    }

    @Test("IU36 privacy: descriptions redact, no print( in sources, diagnostics off by default")
    func iu36() throws {
        let fix = RawFix(lat: 16.4637211, lng: 107.5912345, horizontalAccuracyM: 5, speedMps: 1, timestampWallMs: 0)
        let t = StoredTrip(meta: TestData.meta(name: "Ga Bí Mật"), anchor: ClockAnchor(wallMs: 0, elapsedMs: 0, bootSessionId: nil),
                           engineSnapshot: "{\"lat\":16.4637211}", savedAtWallMs: 0)
        let req = SystemAlarmRequest(id: "i", tripId: "t1", kind: .now, generation: 1, fireAtWallMs: 0, title: "Sắp tới Ga Bí Mật",
                                     channel: .alarmKit)
        for s in [String(describing: fix), String(reflecting: fix), String(describing: t), String(reflecting: t),
                  String(describing: t.meta), String(reflecting: t.meta), String(describing: req)] {
            #expect(!s.contains("16.46") && !s.contains("107.59") && !s.contains("Bí Mật"), "\(s)")
        }
        for dir in ["Sources/TripRuntime", "Sources/NapStopIOS"] {
            let path = "\(RTPaths.packageDir)/\(dir)"
            for f in try FileManager.default.contentsOfDirectory(atPath: path) where f.hasSuffix(".swift") {
                let text = try String(contentsOfFile: "\(path)/\(f)", encoding: .utf8)
                #expect(!text.contains("print("), "\(dir)/\(f)")
                #expect(!text.contains("NSLog("), "\(dir)/\(f)")
            }
        }
        var made = 0
        let j = RuntimeOptions().journal { made += 1; return RecordingJournal() }
        #expect(made == 0 && j is NoJournal)
        _ = RuntimeOptions(diagnostics: true).journal { made += 1; return RecordingJournal() }
        #expect(made == 1)
    }

    @Test("IU45 BridgeMapper: Pigeon names, state first, native-only events dropped")
    func iu45() {
        let st = Self.step(events: [Self.alarmEv, Self.denseEv, Self.supersededEv], fb: .notSet)
        let u = BridgeMapper.updates(tripId: "t1", view: st.view, batteryChoice: .batteryAlarmAt5, events: st.events)
        #expect(u.count == 2)
        guard case let .state(s) = u[0] else { Issue.record("state first"); return }
        #expect(s.fallbackStatus == .notSet && s.batteryChoice == .alarmAt5 && s.samplingTier == nil)
        guard case let .alarm(_, _, reason, ringNow, _, _, _, _) = u[1] else { Issue.record("alarm"); return }
        #expect(reason == .distance && ringNow)
        #expect(BridgeMapper.batteryChoice(.dismiss) == nil)
        for c in [BatteryChoiceDTO.maxSaving, .alarmAt5, .alarmEarlier] {
            #expect(BridgeMapper.batteryChoice(BridgeMapper.batteryAction(c)) == c)
        }
    }
}

/// A started engine for the pure tests (DISTANCE 1000 to TestData.dest at trip ms 1 000).
enum EngineDriverLite {
    static let start0: Step = {
        let cfg = TestData.meta().config(destLat: TestData.destLat, destLng: TestData.destLng)
        return try! TripEngine.start(config: cfg, params: .defaults, nowMs: 1_000)
    }()
    static var state: EngineState { start0.state }
    static var view: TripView { start0.view }
    static func start() -> Step { start0 }
}
