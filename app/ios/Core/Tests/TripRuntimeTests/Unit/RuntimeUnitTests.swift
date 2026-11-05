import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Runtime behaviour with fakes (docs/specs/T17.md IU12–IU44).
@Suite("RuntimeUnit")
struct RuntimeUnitTests {
    static func started(_ w: World, meta: TripMeta = TestData.meta()) async -> StartOutcome {
        await w.listen()
        let r = await w.runtime.start(meta: meta, destLat: TestData.destLat, destLng: TestData.destLng)
        await w.settle()
        return r
    }

    /// Fixes every 5 s at `km` south until `until` returns true or `max` fixes.
    static func drive(_ w: World, km: Double, max: Int = 20, until: () -> Bool) async {
        for _ in 0..<max {
            if until() { return }
            await w.advance(by: 5_000)
            await w.emit(TestData.fix(kmSouth: km, wall: w.time.wallMs()))
        }
    }

    static func ringing(_ w: World) async {
        await drive(w, km: 0.5) { w.seen.firstAlarm() != nil }
    }

    static func nowAlarms(_ w: World) -> [SystemAlarmRequest] { w.alarms.scheduledRequests().filter { $0.kind == .now } }

    @Test("IU17 start: TripStateUpdate before the answer, ledger, one fallback at the deadline, a timer")
    func iu17() async {
        let w = World()
        await w.listen()
        let r = await w.runtime.start(meta: TestData.meta(), destLat: TestData.destLat, destLng: TestData.destLng)
        #expect(r == .started)
        #expect(w.seen.entries.first?.view.phase == .acquiring)  // published before start returned
        #expect(w.store.currentLedger.activeTripId == "t1")
        let fb = w.alarms.scheduledRequests().filter { $0.kind == .fallback }
        #expect(fb.count == 1)
        #expect(fb.first?.fireAtWallMs == w.seen.entries.first?.view.fallbackAtMs)
        await w.settle()
        #expect(w.timer.due != nil)
        #expect(await w.runtime.mode() == .tracking)
        #expect(w.store.activeTrip != nil)
    }

    @Test("IU18 start refusals: codes, details order; no files, no alarms, idle")
    func iu18() async {
        func attempt(_ setup: (World) -> Void) async -> (StartOutcome, World) {
            let w = World()
            setup(w)
            let r = await w.runtime.start(meta: TestData.meta(), destLat: TestData.destLat, destLng: TestData.destLng)
            await w.settle()
            return (r, w)
        }
        let cases: [((World) -> Void, StartOutcome)] = [
            ({ $0.app.state = .background }, .rejected(code: "not-foreground", message: nil, details: nil)),
            ({ $0.env.access = LocationAccess(whenInUseOrAlways: true, fullAccuracy: false, servicesEnabled: true) },
             .rejected(code: "permission-missing", message: nil, details: ["precise"])),
            ({ $0.env.access = LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: false) },
             .rejected(code: "permission-missing", message: nil, details: ["locationServices"])),
            ({ $0.env.access = LocationAccess(whenInUseOrAlways: false, fullAccuracy: false, servicesEnabled: true) },
             .rejected(code: "permission-missing", message: nil, details: ["location"])),
            ({ $0.env.channels = ChannelAccess(alarmKit: .denied, notifications: false) },
             .rejected(code: "permission-missing", message: nil, details: ["alarmChannel"])),
            ({ $0.location.startError = .backgroundModeMissing },
             .rejected(code: "start-failed", message: "BackgroundModeMissing", details: nil)),
        ]
        for (setup, expected) in cases {
            let (r, w) = await attempt(setup)
            #expect(r == expected)
            #expect(w.store.activeTrip == nil && w.alarms.all.isEmpty && w.store.currentLedger.activeTripId == nil)
            #expect(await w.runtime.mode() == .idle)
        }
        let (r, w) = await attempt { $0.env.channels = ChannelAccess(alarmKit: .notDetermined, notifications: true) }
        #expect(r == .started)
        #expect(w.alarms.scheduledRequests().allSatisfy { $0.channel == .notification })
    }

    @Test("IU16 second start refused at once while the first waits; third start works after the first fails")
    func iu16() async {
        let w = World()
        w.location.holdStart = true
        let rt = w.runtime!
        let first = Task { await rt.start(meta: TestData.meta(), destLat: TestData.destLat, destLng: TestData.destLng) }
        while !w.location.isHeld { await Task.yield() }
        let second = await rt.start(meta: TestData.meta("t2"), destLat: TestData.destLat, destLng: TestData.destLng)
        #expect(second == .rejected(code: "trip-active", message: nil, details: nil))
        w.location.startError = .notAuthorized
        w.location.resumeStart()
        #expect(await first.value == .rejected(code: "permission-missing", message: nil, details: ["location"]))
        #expect(w.location.startCount == 1)
        w.location.startError = nil
        #expect(await rt.start(meta: TestData.meta("t3"), destLat: TestData.destLat, destLng: TestData.destLng) == .started)
    }

    @Test("ring: persistNow before the now alarm, guard slot armed, then cancelled when now alerts")
    func ringFlow() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        let a = w.seen.firstAlarm()
        #expect(a?.ringNow == true)
        #expect(Self.nowAlarms(w).count == 1)
        let ops = w.log.ops
        let ringIdx = ops.firstIndex { $0.hasPrefix("schedule.now") }!
        #expect(ops[..<ringIdx].contains("schedule.guard.alarmKit"))
        #expect(ops[..<ringIdx].lastIndex(of: "writeActive") != nil)
        await w.advance(by: 6_000)  // now alarm alerting
        #expect(w.alarms.all.filter { $0.state == .alerting }.map(\.kind) == [.now])
        #expect(!w.alarms.all.contains { $0.kind == .guardSlot })
        #expect(w.store.currentLedger.now?.seenAlerting == true)
    }

    @Test("IU12 now on AlarmKit fails, notification channel works: no AlarmSilenced")
    func iu12() async {
        let w = World()
        w.alarms.fail = { $0.kind == .now && $0.channel == .alarmKit }
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        #expect(Self.nowAlarms(w).map(\.channel) == [.notification])
        #expect(w.seen.entries.last?.view.alarmRinging == true)
    }

    @Test("IU13 both channels fail: AlarmSilenced, guard ≤ now + 30 s, ringFailed, retry guard after 30 s")
    func iu13() async {
        let w = World()
        w.alarms.fail = { $0.kind == .now }
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        #expect(Self.nowAlarms(w).isEmpty)
        #expect(w.seen.entries.last?.view.alarmRinging == false)
        let g = w.alarms.all.first { $0.kind == .guardSlot }
        #expect(g != nil && g!.fireAtWallMs! <= w.time.wallMs() + 30_000)
        #expect(w.notifier.shownNow.contains(.ringFailed))
        // The guard rings and goes (no one answers): a new guard slot follows within RING_RETRY_MS + 60 s.
        w.alarms.silenceAfterMs = 10_000
        let guards0 = w.alarms.scheduledRequests().filter { $0.kind == .guardSlot }.count
        await w.advance(by: 120_000)
        #expect(w.alarms.scheduledRequests().filter { $0.kind == .guardSlot }.count > guards0)
    }

    @Test("IU14 + IU40 snooze: stop the ringing alarm, slot at until + 30 s, SNOOZE_END rings, second snooze no-op")
    func iu14() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        await w.advance(by: 6_000)
        let nowId = Self.nowAlarms(w).first!.id
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        #expect(w.alarms.stops.contains(nowId))
        let v = w.seen.entries.last!.view
        #expect(v.phase == .snoozed)
        let until = v.snoozeUntilMs!
        #expect(w.alarms.all.contains { $0.kind == .fallback && $0.fireAtWallMs == until + 30_000 })
        await w.advance(by: 4_000)
        #expect(!w.seen.events.contains { if case let .alarm(a) = $0 { return a.reason != .distance }; return false })
        await w.advance(to: until - w.startWall + 1_000)
        #expect(w.seen.events.contains { if case let .alarm(a) = $0 { return a.reason == .snoozeEnd }; return false })
        #expect(Self.nowAlarms(w).count == 2)
        let before = w.seen.entries.count
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        #expect(w.seen.entries.suffix(from: before).allSatisfy { $0.view.phase != .snoozed })
    }

    @Test("IU15 TripEnded(DISMISSED): stop alerting, cancel scheduled, writeFinished before deleteActive, idle")
    func iu15() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        await w.advance(by: 6_000)
        await w.runtime.userAction(tripId: "t1", .dismiss)
        await w.settle()
        let ops = w.log.ops
        #expect(ops.firstIndex(of: "writeFinished")! < ops.lastIndex(of: "deleteActive")!)
        #expect(w.alarms.all.isEmpty)
        #expect(w.store.finished["t1"]?.outcome == "ON_TIME")
        #expect(w.store.currentLedger.endedTripIds.contains("t1"))
        #expect(!w.location.isRunningNow)
        #expect(await w.runtime.mode() == .idle)
        #expect(await w.runtime.current() == nil)
        #expect(w.timer.due == nil)
    }

    @Test("IU20 persistNow returns after its budget while the write is slow; the write still completes")
    func iu20() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let gate = DispatchSemaphore(value: 0)
        w.store.writeGate = gate
        let count0 = w.store.writeActiveCount
        let rt = w.runtime!
        let pending0 = w.sleeper.pendingCount
        let t = Task { await rt.onWillTerminate() }  // persistNow(1 000)
        while w.sleeper.pendingCount == pending0 { await Task.yield() }
        w.time.v += 1_000
        w.sleeper.fireDue()
        await t.value
        #expect(w.store.writeActiveCount == count0)
        gate.signal()
        w.store.writeGate = nil
        for _ in 0..<1000 where w.store.writeActiveCount == count0 { await Task.yield(); usleep(100) }
        #expect(w.store.writeActiveCount == count0 + 1)
    }

    @Test("IU22 new slot before cancelling the old one; schedule failure keeps the old slot and reports ok=false")
    func iu22() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let a = w.store.currentLedger.current!.alarmId
        w.log.clear()
        await w.runtime.onClockChanged()  // re-schedules the current slot (new id)
        await w.settle()
        let ops = w.log.ops
        #expect(ops.firstIndex(of: "schedule.fallback.alarmKit")! < ops.firstIndex(of: "cancel")!)
        let b = w.store.currentLedger.current!.alarmId
        #expect(a != b && w.alarms.cancels.contains(a))
        w.alarms.fail = { _ in true }
        await w.runtime.onClockChanged()
        await w.settle()
        #expect(w.store.currentLedger.current?.alarmId == b)
        #expect(w.alarms.all.contains { $0.id == b })
        #expect(w.seen.entries.last?.view.fallbackStatus == .failed)
        #expect(w.notifier.shownNow.contains(.fallbackFailed))
    }

    @Test("IU23 old slot rings while re-scheduling: one ring, new slot cancelled, FallbackFired once")
    func iu23() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let a = w.store.currentLedger.current!.alarmId
        let alarms = w.alarms
        alarms.onSchedule = { r in if r.kind == .fallback { alarms.setState(a, .alerting) } }
        await w.runtime.onClockChanged()
        alarms.onSchedule = nil
        await w.settle()
        let fired = w.seen.events.filter { if case let .alarm(x) = $0 { return x.reason == .fallback || x.ringNow }; return false }
        #expect(w.alarms.all.filter { $0.state == .alerting }.count == 1)
        #expect(!w.alarms.all.contains { $0.state == .scheduled && $0.kind == .fallback })
        #expect(w.store.currentLedger.lastFired?.alarmId == a)
        #expect(fired.count <= 1)
        #expect(Self.nowAlarms(w).isEmpty)
    }

    @Test("IU26 alerting alarm vanishes without a StopIntent → AlarmSilenced after 3 s; with one → nothing")
    func iu26() async {
        for withIntent in [false, true] {
            let w = World()
            #expect(await Self.started(w) == .started)
            await Self.ringing(w)
            await w.advance(by: 6_000)
            let id = Self.nowAlarms(w).first!.id
            if withIntent {
                try? w.store.appendRingEvent(RingEventRec(tripId: "other", alarmId: id, kind: .now, action: .dismiss,
                                                          atWallMs: w.time.wallMs()))
            }
            w.alarms.setState(id, nil)
            await w.settle()
            await w.advance(by: 3_500)
            #expect(w.seen.entries.last?.view.alarmRinging == withIntent)
        }
    }

    /// Far trip, process dies, the fallback slot rings and the user taps Stop 5 s later (iOS 26.1 removes it before
    /// perform); returns the slot and P2 launched in the background, ensureLoaded done (StopIntent not yet).
    static func diedAndStopped(_ w: World) async -> AlarmSlotRec {
        #expect(await Self.started(w) == .started)
        await Self.drive(w, km: 30, max: 6) { false }
        let slot = w.store.currentLedger.current!
        w.kill()
        await w.advance(to: slot.targetAtWallMs - w.startWall)
        await w.advance(by: 5_000)
        w.alarms.setState(slot.alarmId, nil)
        w.location.lastKnownFix = TestData.fix(kmSouth: 0.2, wall: w.time.wallMs())
        w.relaunch(.background)
        // D13: a listener attached now (Flutter) is answered only once the restore is done.
        let world = w
        Task { await world.listen() }
        await w.runtime.ensureLoaded()
        return slot
    }

    static func stopIntent(_ w: World, _ slot: AlarmSlotRec) async {
        let rec = RingEventRec(tripId: "t1", alarmId: slot.alarmId, kind: slot.kind, action: .dismiss, atWallMs: w.time.wallMs())
        try? w.store.appendRingEvent(rec)  // StopIntent step (1)
        await w.runtime.onStopIntent(rec)
        await w.settle()
    }

    static func order(_ w: World, _ a: String, _ b: String) -> Bool {
        let evs = w.journal.all.map(\.ev)
        guard let i = evs.lastIndex(of: a), let j = evs.lastIndex(of: b) else { return false }
        return i < j
    }

    @Test("IU30 S3 bug #1: ensureLoaded in the background, StopIntent 40 ms / 1 900 ms later → no location, no now, DISMISSED, one ring")
    func iu30() async {
        for d: Int64 in [40, 1_900] {
            let w = World()
            let slot = await Self.diedAndStopped(w)
            let starts0 = w.location.startCount
            let now0 = Self.nowAlarms(w).count
            await w.advance(by: d)
            await Self.stopIntent(w, slot)
            await w.advance(by: 60_000)
            #expect(w.location.startCount == starts0)
            #expect(Self.nowAlarms(w).count == now0)
            #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
            #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1)
            #expect(Self.order(w, "stop_intent", "restore"), "D13: restore waits for the StopIntent")
            #expect(w.store.readRingEvents().isEmpty)
        }
    }

    @Test("IU30b StopIntent after the settle time: restore first (headless, R2 step 1 → silenced), still no now, one ring")
    func iu30b() async {
        let w = World()
        let slot = await Self.diedAndStopped(w)
        let now0 = Self.nowAlarms(w).count
        await w.advance(by: 2_100)
        #expect(await w.runtime.mode() == .headless)
        #expect(w.seen.entries.last?.view.alarmRinging == false)
        await Self.stopIntent(w, slot)
        await w.advance(by: 60_000)
        #expect(Self.order(w, "restore", "stop_intent"))
        #expect(Self.nowAlarms(w).count == now0)
        #expect(w.store.finished["t1"] != nil)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1)
    }

    @Test("IU30c Flutter calls while the background restore waits (D13) answer only after the StopIntent")
    func iu30c() async {
        let w = World()
        let slot = await Self.diedAndStopped(w)
        await w.advance(by: 100)
        let rt = w.runtime!
        let answered = Counter()
        let cur = Task { () -> Bool in
            let c = await rt.current()
            answered.inc()
            return c == nil
        }
        let lis = Task {
            _ = await rt.addListener { _, _, _, _ in }
            answered.inc()
        }
        await w.advance(by: 1_800)
        for _ in 0..<50 { await Task.yield() }
        #expect(answered.value == 0)
        await Self.stopIntent(w, slot)
        #expect(await cur.value)
        await lis.value
        #expect(answered.value == 2)
        #expect(Self.order(w, "stop_intent", "restore"))
    }

    @Test("IU46 now alerting cancels the guard and the ledger forgets it; the next ringNow Step arms a guard first")
    func iu46() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        await w.advance(by: 6_000)
        #expect(w.store.currentLedger.current == nil && w.store.currentLedger.stale == nil)
        let live = EffectPlanner.liveSlot(w.store.currentLedger, list: w.alarms.all)
        #expect(live == nil)
        let over = TripEvent.alarm(.init(atMs: 1_000_000, reason: .overshoot, ringNow: true, snoozeAllowed: false, distanceM: nil,
                                          etaS: nil, batteryPct: nil))
        let p = PlanInput(prevView: nil, step: PureUnitTests.step(events: [over]), meta: TestData.meta(), mode: .tracking,
                          facts: .none, ledger: w.store.currentLedger, timerDueTripMs: nil, params: .defaults,
                          nowWallMs: 1_000_000, nowTripMs: 1_000_000, liveSlot: live)
        let fx = EffectPlanner.plan(p)
        let g = fx.firstIndex(of: .armRingGuard(guardAtWallMs: 1_030_000))
        let r = fx.firstIndex { if case .ringNow = $0 { return true }; return false }
        #expect(g != nil && r != nil && g! < r!)
    }

    @Test("IU48 clock change while ALARMING with the guard cancelled: nothing is scheduled")
    func iu48() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.ringing(w)
        await w.advance(by: 6_000)
        let n = w.alarms.scheduledRequests().count
        w.time.shiftWall(600_000)
        await w.runtime.onClockChanged()
        await w.settle()
        #expect(w.alarms.scheduledRequests().count == n)
    }

    @Test("IU31 + IU32 background relaunch without StopIntent: settle 2 s → headless + interrupted once; app active → tracking")
    func iu31() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.drive(w, km: 30, max: 6) { false }
        w.newProcess()
        w.app.state = .background
        w.time.v += 60_000
        await w.runtime.ensureLoaded()
        let starts0 = w.location.startCount
        await w.advance(by: 2_100)
        #expect(await w.runtime.mode() == .headless)
        #expect(w.notifier.shownNow.filter { $0 == .interrupted }.count == 1)
        #expect(w.location.startCount == starts0)
        await w.runtime.onAppActive()
        await w.settle()
        #expect(await w.runtime.mode() == .tracking)
        #expect(w.location.startCount == starts0 + 1)
        #expect(w.notifier.clearedNow.contains(.interrupted))
    }

    @Test("IU33 StopIntent of an unknown/ended trip: cancel that alarm, endedTripIds, active trip untouched")
    func iu33() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let rec = RingEventRec(tripId: "ghost", alarmId: "zzz", kind: .fallback, action: .dismiss, atWallMs: w.time.wallMs())
        await w.runtime.onStopIntent(rec)
        await w.settle()
        #expect(w.alarms.cancels.contains("zzz"))
        #expect(w.store.currentLedger.endedTripIds.contains("ghost"))
        #expect(await w.runtime.current()?.meta.tripId == "t1")
    }

    @Test("IU37 addListener replays one state; nothing after TripEnded")
    func iu37() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let late = Seen()
        _ = await w.runtime.addListener { _, view, choice, events in late.add(.init(view: view, choice: choice, events: events)) }
        await w.settle()
        #expect(late.entries.count == 1)
        await w.runtime.userAction(tripId: "t1", .stopTrip)
        await w.settle()
        let n = late.entries.count
        await w.advance(by: 120_000)
        await w.runtime.userAction(tripId: "t1", .dismiss)
        await w.settle()
        #expect(late.entries.count == n)
    }

    @Test("IU39 timer: Tick at the real delivery time; awake tick ≤ 60 s after the last step")
    func iu39() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let due = w.timer.due!
        #expect(due.v <= 60_000)
        w.time.v = due.v + 3_000
        w.timer.consume()
        let n = w.seen.entries.count
        await w.runtime.onTimer(generation: due.gen)
        await w.settle()
        #expect(w.seen.entries.count > n)
        #expect(w.seen.entries.last!.view.atMs == w.tripMs(atV: due.v + 3_000))
        await w.runtime.onTimer(generation: due.gen - 1)  // stale generation: ignored
    }

    @Test("IU41 pendingFinished sorted, ack, survives a new process")
    func iu41() async {
        let w = World()
        for (id, at) in [("c", 30), ("a", 10), ("b", 20)] {
            try? w.store.writeFinished(FinishedRecord(tripId: id, outcome: "CANCELLED", endReason: "USER_STOP", endedAtMs: Int64(at),
                                                      startedAtMs: 0, alarmAtMs: nil, alarmReason: nil, dismissedAtMs: nil,
                                                      snoozeCount: 0, travelledM: 0, vehicleGuess: "BUS"))
        }
        #expect(await w.runtime.pendingFinished().map(\.tripId) == ["a", "b", "c"])
        await w.runtime.ackFinished(["b", "zz"])
        w.newProcess()
        #expect(await w.runtime.pendingFinished().map(\.tripId) == ["a", "c"])
    }

    @Test("IU43 snapshot writes failing never delay the ring; warnings name the type only")
    func iu43() async {
        func alarmAt(_ failing: Bool) async -> (Int64?, [String]) {
            let w = World()
            #expect(await Self.started(w) == .started)
            await Self.drive(w, km: 3, max: 4) { false }
            if failing { w.store.failWriteActive = { ScheduleFailure() } }
            await Self.ringing(w)
            return (w.seen.firstAlarm()?.atMs, w.warns)
        }
        let base = await alarmAt(false)
        let failing = await alarmAt(true)
        #expect(base.0 != nil && base.0 == failing.0)
        #expect(failing.1.count >= 2 && failing.1.allSatisfy { $0 == "snapshot write failed (ScheduleFailure)" })
    }

    @Test("IU44 availability: revoked → PERMISSION_REVOKED, back → AVAILABLE; services off; reduced accuracy is fine")
    func iu44() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        #expect(LocationAccess(whenInUseOrAlways: true, fullAccuracy: false, servicesEnabled: true).availability == .available)
        w.location.sink?.locationSession(availabilityChanged: .permissionRevoked)
        await w.settle()
        #expect(w.seen.entries.last?.view.locationCause == .permissionRevoked)
        w.location.sink?.locationSession(availabilityChanged: .available)
        await w.settle()
        #expect(w.seen.entries.last?.view.locationCause == .available)
        w.env.access = LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: false)
        await w.advance(by: 61_000)  // read at onTimer
        #expect(w.seen.entries.last?.view.locationCause == .servicesOff)
    }

    @Test("IU38 clock change: the slot moves to toWall(target) on the new wall, new before old")
    func iu38() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let old = w.store.currentLedger.current!
        w.time.shiftWall(600_000)
        await w.runtime.onClockChanged()
        await w.settle()
        let cur = w.store.currentLedger.current!
        #expect(cur.alarmId != old.alarmId && cur.targetAtMs == old.targetAtMs)
        #expect(cur.targetAtWallMs == old.targetAtWallMs + 600_000)
        #expect(w.alarms.cancels.contains(old.alarmId))
    }

    @Test("V2-2 (1) unreadable list at ring time: ring + guard (no stale ringingNow); (2) snooze before the now alarm rang forgets it")
    func v22() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.drive(w, km: 3, max: 3) { false }
        w.alarms.listUnreadable = true
        await Self.ringing(w)
        w.alarms.listUnreadable = false
        #expect(Self.nowAlarms(w).count == 1)
        #expect(w.alarms.scheduledRequests().contains { $0.kind == .guardSlot })
        let w2 = World()
        #expect(await Self.started(w2) == .started)
        await Self.ringing(w2)
        #expect(w2.store.currentLedger.now != nil)
        await w2.runtime.userAction(tripId: "t1", .snooze)  // within the 5 s lead: the now alarm never rang
        await w2.settle()
        #expect(w2.store.currentLedger.now == nil)
        #expect(Self.nowAlarms(w2).allSatisfy { r in !w2.alarms.all.contains { $0.id == r.id } })
    }

    @Test("V2-6 cancelSlots with an unreadable list still cancels the ledger slots")
    func v26() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        let slot = w.store.currentLedger.current!
        w.alarms.listUnreadable = true
        await w.runtime.userAction(tripId: "t1", .stopTrip)
        await w.settle()
        w.alarms.listUnreadable = false
        #expect(w.alarms.cancels.contains(slot.alarmId))
        #expect(!w.alarms.all.contains { $0.tripId == "t1" })
    }

    @Test("#9 unreadable engine facts at restore: restored as UNKNOWN, the trip can be stopped, a new trip can start")
    func review9() async {
        let w = World()
        #expect(await Self.started(w) == .started)
        await Self.drive(w, km: 30, max: 4) { false }
        w.newProcess()
        await w.runtime.setFactsReaderForTesting { _ in nil }
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(w.journal.all.last { $0.ev == "restore" }?.fields["status"] == "UNKNOWN")
        #expect(await w.runtime.current()?.meta.tripId == "t1")
        await w.runtime.userAction(tripId: "t1", .stopTrip)
        await w.settle()
        #expect(w.store.finished["t1"]?.endReason == "USER_STOP")
        #expect(await w.runtime.start(meta: TestData.meta("t2"), destLat: TestData.destLat, destLng: TestData.destLng) == .started)
    }

    @Test("IU42 battery read at onTimer: one sample per change, LOW_BATTERY rings once")
    func iu42() async {
        let w = World()
        w.env.batteryReading = BatteryReading(levelPct: 8, charging: false)
        #expect(await Self.started(w) == .started)
        await Self.drive(w, km: 40, max: 4) { false }
        for level in stride(from: 8, through: 3, by: -1) {
            w.env.batteryReading = BatteryReading(levelPct: level, charging: false)
            await w.advance(by: 60_000)
            await w.emit(TestData.fix(kmSouth: 40, wall: w.time.wallMs()))
        }
        let low = w.seen.events.filter { if case let .alarm(a) = $0 { return a.reason == .lowBattery }; return false }
        #expect(low.count == 1)
        #expect(Self.nowAlarms(w).count == 1)
        let levels = w.seen.entries.compactMap(\.view.batteryPct)
        #expect(Set(levels).count <= 6)
    }
}
