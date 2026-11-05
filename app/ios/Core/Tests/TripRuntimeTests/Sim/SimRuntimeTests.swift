import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T18.1 runtime tests with fakes (docs/specs/T18.1.md): SIU11–SIU13, SIU15, SIU16, SIU19, SIU20.
@Suite("SimRuntime")
struct SimRuntimeTests {
    static let bus: TraceCase = (try? RuntimeFixtures.read("bus_hn_brt01"))!

    static func simMeta(_ id: String = "bus_hn_brt01", speed: Double = 60, tripId: String = "s1") -> TripMeta {
        TestData.meta(tripId).with(simulation: SimSpec(traceId: id, speedFactor: speed))
    }

    /// A started simulated trip of bus_hn_brt01 (dest of the trace), listener attached.
    static func startedBus(speed: Double = 60, store: FixtureTraceStore = FixtureTraceStore(), startWall: Int64? = nil)
        async -> World {
        let w = World(startWall: startWall ?? bus.startMs, traces: store)
        await w.listen()
        let r = await w.runtime.start(meta: simMeta(speed: speed), destLat: bus.destLat, destLng: bus.destLng)
        #expect(r == .started)
        await w.settle()
        return w
    }

    static func ringNowSteps(_ w: World) -> Int {
        w.seen.events.filter { if case let .alarm(a) = $0 { return a.ringNow }; return false }.count
    }

    // MARK: SIU11

    @Test("SIU11 bad id, missing asset, broken GPX, slow store: simulation-unavailable + code; nothing started or written")
    func siu11() async throws {
        func attempt(_ id: String, _ setup: (FixtureTraceStore) -> Void = { _ in }) async -> (StartOutcome, World) {
            let store = FixtureTraceStore()
            setup(store)
            let w = World(traces: store)
            let r = await w.runtime.start(meta: Self.simMeta(id), destLat: TestData.destLat, destLng: TestData.destLng)
            await w.settle()
            return (r, w)
        }
        let cases: [(String, (FixtureTraceStore) -> Void, String)] = [
            ("stub/normal", { _ in }, "TraceIdInvalid"),
            ("../x", { _ in }, "TraceIdInvalid"),
            ("no_such", { _ in }, "TraceNotFound"),
            ("broken_trace", { $0.extra["broken_trace"] = Data("<gpx><trk><trkseg><trkpt lat=\"1\"".utf8) }, "TraceInvalid"),
        ]
        for (id, setup, code) in cases {
            let (r, w) = await attempt(id, setup)
            #expect(r == .rejected(code: "simulation-unavailable", message: code, details: nil), "\(id)")
            Self.expectNothing(w, id)
        }
        let (_, wBad) = await attempt("../x")
        #expect(wBad.traces is FixtureTraceStore && (wBad.traces as! FixtureTraceStore).opens.isEmpty, "the id is checked before any read")

        // The store hangs: TraceLoadTimeout after SIM_TRACE_LOAD_BUDGET_MS on the runtime sleeper.
        let store = FixtureTraceStore()
        let hold = DispatchSemaphore(value: 0)
        store.hold = hold
        let w = World(traces: store)
        let runtime = w.runtime!
        let pending = Task { await runtime.start(meta: Self.simMeta(), destLat: TestData.destLat, destLng: TestData.destLng) }
        var spins = 0
        while (store.opens.isEmpty || w.sleeper.pendingCount == 0) && spins < 5_000 {
            spins += 1
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        w.time.v += 3_000
        w.sleeper.fireDue()
        let r = await pending.value
        hold.signal()
        #expect(r == .rejected(code: "simulation-unavailable", message: "TraceLoadTimeout", details: nil))
        await w.settle()
        Self.expectNothing(w, "timeout")
        // The gate is free again.
        let ok = await w.runtime.start(meta: TestData.meta("r2"), destLat: TestData.destLat, destLng: TestData.destLng)
        #expect(ok == .started)
        w.sleeper.releaseAll()
    }

    static func expectNothing(_ w: World, _ label: String) {
        #expect(w.location.startCount == 0, "\(label): location")
        #expect(w.store.writeActiveCount == 0 && w.store.activeTrip == nil, "\(label): snapshot")
        #expect(w.store.currentLedger.activeTripId == nil, "\(label): ledger")
        #expect(w.alarms.scheduledRequests().isEmpty, "\(label): alarms")
        #expect(w.timer.due == nil, "\(label): timer")
    }

    // MARK: SIU12

    @Test("SIU12 simulated start: ACQUIRING published, keep-alive session once, no system alarm, ledger + meta simulated")
    func siu12() async throws {
        let store = FixtureTraceStore()
        let w = World(startWall: Self.bus.startMs, traces: store)
        await w.listen()
        let r = await w.runtime.start(meta: Self.simMeta(), destLat: Self.bus.destLat, destLng: Self.bus.destLng)
        #expect(r == .started)
        #expect(w.seen.entries.first?.view.phase == .acquiring)
        #expect(w.location.startCount == 1)
        #expect(w.location.currentSpec == .keepAlive)
        #expect(w.alarms.scheduledRequests().isEmpty, "the fallback slot is virtual")
        #expect(w.store.currentLedger.activeSimulated)
        #expect(store.opens == ["bus_hn_brt01"])
        let cur = try #require(await w.runtime.current())
        #expect(cur.meta.simulation == SimSpec(traceId: "bus_hn_brt01", speedFactor: 60))
        await w.settle()
        #expect(w.store.activeTrip?.anchor.speed == 60)
        #expect(w.store.activeTrip?.meta.simulation == SimSpec(traceId: "bus_hn_brt01", speedFactor: 60))
        #expect(w.timer.due != nil, "the next virtual event is armed")
        #expect(w.journal.all.contains { $0.ev == "sim" && $0.fields["trace"] == "bus_hn_brt01" })
        w.sleeper.releaseAll()
    }

    // MARK: SIU13

    @Test("SIU13 a simulated trip gets no BatterySample / LocationAvailability; real fixes are dropped")
    func siu13() async throws {
        let w = await Self.startedBus()
        await SimRun(world: w).run(maxV: 5_000) { false }  // 300 s of trip
        let before = w.seen.entries.count
        #expect(before > 10)
        w.env.batteryReading = BatteryReading(levelPct: 80, charging: false)
        w.runtime.submitBattery(BatteryReading(levelPct: 80, charging: false))
        let sink = try #require(w.location.sink)
        sink.locationSession(availabilityChanged: .permissionRevoked)
        sink.locationSession(didReceive: TestData.fix(kmSouth: 0.1, wall: w.time.wallMs()))
        await w.settle()
        #expect(w.seen.entries.count == before, "no Step from battery, availability or a real fix")
        w.env.batteryReading = BatteryReading(levelPct: 4, charging: false)
        w.env.access = LocationAccess(whenInUseOrAlways: false, fullAccuracy: false, servicesEnabled: true)
        await SimRun(world: w).run(maxV: 10_000) { false }
        #expect(w.seen.entries.count > before)
        #expect(w.seen.entries.allSatisfy { $0.view.batteryPct == nil && $0.view.locationCause == .available })
        #expect(!w.seen.events.contains { $0.fixtureName == "lowBatteryRisk" || $0.fixtureName == "gpsLost" })
        #expect(w.journal.all.contains { $0.ev == "sim_loc" && $0.fields["availability"] == "PERMISSION_REVOKED" })
        w.sleeper.releaseAll()
    }

    // MARK: SIU15

    @Test("SIU15 virtual fallback due while TRACKING: one AlarmKit fallback at nowWall + 5 s, lastFired, one FallbackFired")
    func siu15() async throws {
        let w = await Self.startedBus(speed: 10)
        await SimRun(world: w).run(maxV: 30_000) { false }  // 300 s of trip
        let last = try #require(w.seen.entries.last?.view)
        #expect(last.phase == .tracking)
        #expect(w.alarms.scheduledRequests().isEmpty)
        // The engine never lets its slot fire on a fixture trace (it alarms or moves it first): force the virtual slot due.
        await w.runtime.setSimFallbackDueForTesting(last.atMs)
        let before = w.seen.entries.count
        let journal = w.journal
        await SimRun(world: w).run(maxV: w.time.v + 10_000) { journal.all.contains { $0.ev == "fb_fired" } }
        let fbFired = w.journal.all.filter { $0.ev == "fb_fired" }
        #expect(fbFired.count == 1 && fbFired.first?.fields["src"] == "sim")
        let fb = w.alarms.scheduledRequests().filter { $0.kind == .fallback }
        #expect(fb.count == 1)
        let schedWall = try #require(w.alarms.schedules.first { $0.kind == .fallback }?.wall)
        #expect(fb.first?.fireAtWallMs == schedWall + 5_000)
        #expect(w.store.currentLedger.lastFired?.alarmId == fb.first?.id)
        #expect(w.store.currentLedger.lastFired?.firedAtMs == last.atMs)
        // FallbackFired was the next engine input, at the trip time of the slot.
        let next = try #require(w.seen.entries.dropFirst(before).first)
        #expect(next.view.atMs == last.atMs)
        #expect(next.view.phase != .tracking, "the engine took the fallback ring (\(next.view.phase.jsonName))")
        // The alarm alerts 5 s later: the interpreter does not feed it a second time.
        await SimRun(world: w).run(maxV: w.time.v + 10_000) { false }
        #expect(w.alarms.all.contains { $0.id == fb.first?.id && $0.state == .alerting })
        #expect(w.journal.all.filter { $0.ev == "fb_fired" }.count == 1)
        #expect(!w.alarms.scheduledRequests().contains { $0.kind == .guardSlot })
        w.sleeper.releaseAll()
    }

    // MARK: SIU16

    @Test("SIU16 simulated trip ALARMING, process dies: the next load ends it quietly (background and active) (= SM16)",
          arguments: [AppActivity.background, AppActivity.active])
    func siu16(_ state: AppActivity) async throws {
        let w = await Self.startedBus(speed: 600)
        let seen = w.seen
        await SimRun(world: w).run(maxV: 60_000) { seen.firstAlarm() != nil }
        #expect(w.seen.firstAlarm()?.ringNow == true)
        await SimRun(world: w).run(maxV: w.time.v + 6_000) { false }  // the "now" alarm alerts
        #expect(w.alarms.all.contains { $0.tripId == "s1" && $0.state == .alerting })
        let starts = w.location.startCount
        let nowSchedules = Self.nowCount(w)
        let shown = w.notifier.shownNow.count
        w.app.state = state
        w.newProcess()
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(Self.nowCount(w) == nowSchedules, "no ring")
        #expect(w.location.startCount == starts, "no location")
        #expect(w.store.finished["s1"]?.endReason == "USER_STOP")
        #expect(!w.alarms.all.contains { $0.tripId == "s1" }, "every alarm of the trip stopped/cancelled")
        #expect(w.notifier.shownNow.count == shown, "no notice")
        #expect(w.store.activeTrip == nil)
        #expect(w.store.currentLedger.activeTripId == nil && !w.store.currentLedger.activeSimulated)
        #expect(w.store.currentLedger.endedTripIds.contains("s1"))
        w.app.state = .active
        #expect(await w.runtime.current() == nil)
        #expect(await w.runtime.mode() == .idle)
        #expect(w.journal.all.contains { $0.ev == "sim_end" && $0.fields["cause"] == "processDied" })
        w.sleeper.releaseAll()
    }

    static func nowCount(_ w: World) -> Int { w.alarms.scheduledRequests().filter { $0.kind == .now }.count }

    @Test("SIU16 snapshot lost + ledger activeSimulated: forgotten, no notice (= SM17)")
    func siu16Lost() async throws {
        let w = await Self.startedBus()
        await SimRun(world: w).run(maxV: 2_000) { false }
        w.store.setActiveRaw(nil)
        let shown = w.notifier.shownNow.count
        w.newProcess()
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(w.notifier.shownNow.count == shown)
        #expect(!w.notifier.shownNow.contains(.interrupted))
        #expect(w.store.currentLedger.activeTripId == nil && !w.store.currentLedger.activeSimulated)
        #expect(w.store.currentLedger.endedTripIds.contains("s1"))
        #expect(await w.runtime.current() == nil)
        w.sleeper.releaseAll()
    }

    @Test("SIU16 terminate snapshot of a simulated trip: no interrupted notice")
    func siu16Terminate() async throws {
        let w = await Self.startedBus()
        await SimRun(world: w).run(maxV: 2_000) { false }
        let snap = try #require(w.runtime.terminateSnapshot(wallMs: w.time.wallMs()))
        #expect(!snap.interrupted)
        #expect(snap.trip.meta.simulation != nil)
        await w.runtime.onWillTerminate()
        #expect(!w.notifier.shownNow.contains(.interrupted))
        w.sleeper.releaseAll()
    }

    // MARK: SIU19

    @Test("SIU19 dismiss while virtual events are due: they run first, then DISMISS at ≥ their time (D5)")
    func siu19() async throws {
        let w = await Self.startedBus(speed: 600)
        let seen = w.seen
        await SimRun(world: w).run(maxV: 60_000) { seen.firstAlarm() != nil }
        let alarm = try #require(w.seen.firstAlarm())
        await SimRun(world: w).run(maxV: w.time.v + 1_000) { false }
        let before = w.seen.entries.count
        let lastAt = try #require(w.seen.entries.last?.view.atMs)
        // 1× after the alarm: 20 s with no timer delivered = due samples/wakes not yet handled.
        w.time.v += 20_000
        await w.runtime.userAction(tripId: "s1", .dismiss)
        await w.settle()
        let added = Array(w.seen.entries.dropFirst(before))
        #expect(added.count >= 4, "≥ 3 due events then the dismiss (got \(added.count))")
        let dismissStep = try #require(added.last)
        #expect(dismissStep.events.contains { $0.fixtureName == "tripEnded" })
        let caught = added.dropLast()
        #expect(caught.allSatisfy { !$0.events.contains { $0.fixtureName == "tripEnded" } })
        #expect(zip(caught, caught.dropFirst()).allSatisfy { $0.view.atMs <= $1.view.atMs })
        #expect(caught.allSatisfy { $0.view.atMs > lastAt && $0.view.atMs <= lastAt + 20_000 })
        #expect(dismissStep.view.atMs >= (caught.last?.view.atMs ?? 0))
        #expect(alarm.atMs < dismissStep.view.atMs)
        #expect(w.store.finished["s1"] != nil)
        w.sleeper.releaseAll()
    }

    // MARK: D6b

    @Test("D6b \"now\" scheduled but never alerting: the virtual slot is dropped at T_ring, the guard still rings at +30 s real")
    func d6bGuardSurvives() async throws {
        let w = World(startWall: Self.bus.startMs, traces: FixtureTraceStore())
        w.alarms.neverAlert = { $0.kind == .now }
        await w.listen()
        #expect(await w.runtime.start(meta: Self.simMeta(speed: 600), destLat: Self.bus.destLat, destLng: Self.bus.destLng)
            == .started)
        await w.settle()
        let seen = w.seen
        await SimRun(world: w).run(maxV: 60_000) { seen.firstAlarm() != nil }
        #expect(w.seen.firstAlarm()?.ringNow == true)
        #expect(Self.nowCount(w) == 1)
        let ringV = w.time.v
        await SimRun(world: w).run(maxV: ringV + 29_000) { false }
        // D6b: the "now" alarm counts as alerting on the trip clock: the pending virtual slot is gone, nothing alerts.
        #expect(w.journal.all.contains { $0.ev == "sim_fallback" && $0.fields["cause"] == "nowAlerting" })
        #expect(!w.alarms.all.contains { $0.state == .alerting })
        #expect(!w.journal.all.contains { $0.ev == "fb_fired" })
        #expect(Self.nowCount(w) == 1, "not before the guard time")
        await SimRun(world: w).run(maxV: ringV + 31_000) { false }
        #expect(w.journal.all.contains { $0.ev == "sim_guard" && $0.fields["ring"] == "true" })
        #expect(Self.nowCount(w) == 2, "the in-process guard (real time) rang \"now\" again")
        #expect(!w.log.ops.contains { $0.hasPrefix("schedule.guardSlot") || $0.hasPrefix("schedule.fallback") })
        w.sleeper.releaseAll()
    }

    // MARK: SIU22

    @Test("SIU22 rearm: a due timer delivered 1 s late is not re-armed by 10 other commands; its delivery is handled")
    func siu22() async throws {
        let w = await Self.startedBus(speed: 1)
        await SimRun(world: w).run(maxV: 60_000) { false }
        let due = try #require(w.timer.due)
        let sets = w.timer.sets.count
        let before = w.seen.entries.count
        w.time.v = due.v + 1_000  // due, not delivered yet
        let sink = try #require(w.location.sink)
        for i in 0..<10 {
            sink.locationSession(didReceive: TestData.fix(kmSouth: 3, wall: w.time.wallMs() - Int64(i)))  // dropped (D9)
            await w.runtime.drain()
        }
        #expect(w.timer.sets.count == sets, "the due timer was re-armed \(w.timer.sets.count - sets) times")
        #expect(w.timer.due?.gen == due.gen)
        #expect(w.seen.entries.count == before)
        w.timer.consume()
        await w.runtime.onTimer(generation: due.gen)
        await w.settle()
        #expect(w.seen.entries.count > before, "the first delivery was handled (same generation)")
        w.sleeper.releaseAll()
    }

    // MARK: SIU20

    @Test("SIU20 the ring guard of a simulated trip is in process: no system alarm; when due it tries \"now\" again")
    func siu20() async throws {
        let w = World(startWall: Self.bus.startMs, traces: FixtureTraceStore())
        w.alarms.fail = { $0.kind == .now }
        await w.listen()
        #expect(await w.runtime.start(meta: Self.simMeta(speed: 600), destLat: Self.bus.destLat, destLng: Self.bus.destLng)
            == .started)
        await w.settle()
        let seen = w.seen
        await SimRun(world: w).run(maxV: 60_000) { seen.firstAlarm() != nil }
        #expect(w.seen.firstAlarm()?.ringNow == true)
        let attempts = w.log.ops.filter { $0.hasPrefix("schedule.now") }.count
        #expect(attempts == 2, "AlarmKit then notification")
        #expect(w.notifier.shownNow.contains(.ringFailed))
        let ringV = w.time.v
        await SimRun(world: w).run(maxV: ringV + 29_000) { false }
        #expect(w.log.ops.filter { $0.hasPrefix("schedule.now") }.count == attempts, "not before the guard time")
        await SimRun(world: w).run(maxV: ringV + 31_000) { false }
        #expect(w.log.ops.filter { $0.hasPrefix("schedule.now") }.count == attempts + 2, "the guard tried \"now\" again")
        #expect(!w.log.ops.contains { $0.hasPrefix("schedule.guardSlot") || $0.hasPrefix("schedule.fallback") },
                "no system alarm for the guard")
        // Channels work again: the next guard rings.
        w.alarms.fail = nil
        await SimRun(world: w).run(maxV: ringV + 100_000) { false }
        #expect(w.alarms.scheduledRequests().contains { $0.kind == .now })
        #expect(!w.log.ops.contains { $0.hasPrefix("schedule.guardSlot") })
        w.sleeper.releaseAll()
    }
}
