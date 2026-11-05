import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Tester T17 (docs/test-reports/T17.md): boundaries and risk areas outside the spec test table. Pure tests first, then
/// runtime tests with the fakes of `Support/`.
@Suite("TesterT17Pure")
struct TesterT17PureTests {
    static func slot(_ id: String, _ at: Int64, kind: SystemAlarmKind = .fallback) -> AlarmSlotRec {
        AlarmSlotRec(alarmId: id, kind: kind, generation: 1, targetAtMs: at, targetAtWallMs: at, setAtWallMs: 0, channel: .alarmKit)
    }

    static func info(_ id: String, _ s: SystemAlarmState, kind: SystemAlarmKind = .fallback, at: Int64 = 0) -> SystemAlarmInfo {
        SystemAlarmInfo(id: id, tripId: "t1", kind: kind, generation: 1, state: s, fireAtWallMs: at, channel: .alarmKit)
    }

    static func nowRec(_ fire: Int64, confirmed: Bool = true, seen: Bool = false) -> NowRingRec {
        NowRingRec(alarmId: "N", generation: 2, fireAtWallMs: fire, reason: "DISTANCE", confirmed: confirmed, seenAlerting: seen,
                   channel: .alarmKit)
    }

    @Test("R1 window is closed [now, now + lag]: both ends need no guard, one ms outside does")
    func guardWindowEdges() {
        let now: Int64 = 1_000_000, guardAt = now + 30_000
        func needs(_ at: Int64) -> Bool {
            EffectPlanner.needsGuard(live: Self.slot("A", at), nowWallMs: now, guardAtWallMs: guardAt)
        }
        #expect(!needs(now))
        #expect(!needs(guardAt))
        #expect(needs(now - 1))
        #expect(needs(guardAt + 1))
        #expect(EffectPlanner.needsGuard(live: nil, nowWallMs: now, guardAtWallMs: guardAt))
    }

    @Test("R1 lower bound: a slot still `scheduled` but past its time (AlarmKit late, [AK-FAN]) does not count → guard")
    func lateScheduledSlotNeedsGuard() {
        let now: Int64 = 1_000_000, guardAt = now + 30_000
        var l = AlarmLedger.empty
        l.current = Self.slot("A", now - 5_000)
        let live = EffectPlanner.liveSlot(l, list: [Self.info("A", .scheduled, at: now - 5_000)])
        #expect(live?.alarmId == "A")
        #expect(EffectPlanner.needsGuard(live: live, nowWallMs: now, guardAtWallMs: guardAt))
        // Through the planner: Alarm(ringNow) with that live slot → armRingGuard before ringNow.
        let p = PlanInput(prevView: nil, step: PureUnitTests.step(events: [PureUnitTests.alarmEv]), meta: TestData.meta(),
                          mode: .tracking, facts: .none, ledger: l, timerDueTripMs: nil, params: .defaults, nowWallMs: now,
                          nowTripMs: now, liveSlot: live)
        let fx = EffectPlanner.plan(p)
        let g = fx.firstIndex(of: .armRingGuard(guardAtWallMs: guardAt))
        let r = fx.firstIndex { if case .ringNow = $0 { return true }; return false }
        #expect(g != nil && r != nil && g! < r!)
    }

    @Test("RingFactsReader: confirmed now counts as ringing up to fireAt + grace inclusive; not after, not when seen/unconfirmed")
    func ringFactsGraceEdge() {
        let fire: Int64 = 2_000_000, grace = RuntimeConstants.default.nowAlertGraceMs
        var l = AlarmLedger.empty
        l.now = Self.nowRec(fire)
        #expect(RingFactsReader.facts(tripId: "t1", list: [], ledger: l, nowWallMs: fire + grace).ringingNow)
        #expect(!RingFactsReader.facts(tripId: "t1", list: [], ledger: l, nowWallMs: fire + grace + 1).ringingNow)
        l.now = Self.nowRec(fire, seen: true)
        #expect(!RingFactsReader.facts(tripId: "t1", list: [], ledger: l, nowWallMs: fire).ringingNow)
        l.now = Self.nowRec(fire, confirmed: false)
        #expect(!RingFactsReader.facts(tripId: "t1", list: [], ledger: l, nowWallMs: fire).ringingNow)
        // An alerting alarm of another trip is not "ours".
        let other = SystemAlarmInfo(id: "X", tripId: "t0", kind: .fallback, generation: 1, state: .alerting, fireAtWallMs: fire,
                                    channel: .alarmKit)
        #expect(!RingFactsReader.facts(tripId: "t1", list: [other], ledger: .empty, nowWallMs: fire).ringingNow)
    }

    @Test("RestoreRingPolicy edges: grace end, cover window end (lag + 1 s), cover at now, unreadable list before the cover")
    func restorePolicyEdges() {
        let now: Int64 = 10_000_000, lag: Int64 = 30_000, grace: Int64 = 20_000
        func d(_ l: AlarmLedger, _ list: [SystemAlarmInfo]?, alarmWall: Int64) -> RestoreRingDecision {
            RestoreRingPolicy.decide(info: RestoreInfo(status: .pending), ledger: l, list: list, nowWallMs: now, lagMs: lag,
                                     graceMs: grace, alarmWallMs: alarmWall)
        }
        // Step 2 with an unreadable list: strictly before fireAt + grace → wait; at the end → silenced.
        var a = AlarmLedger.empty
        a.now = Self.nowRec(now - grace + 1)
        #expect(d(a, nil, alarmWall: now - grace + 1) == .none)
        a.now = Self.nowRec(now - grace)
        #expect(d(a, nil, alarmWall: now - grace) == .silenced(atWallMs: now - grace))
        // Step 3 cover window: target ≤ alarmWall + lag + 1 000 covers; one ms more does not (→ ring, step 4).
        let alarmWall = now - 100_000
        var b = AlarmLedger.empty
        b.current = Self.slot("G", alarmWall + lag + 1_000, kind: .guardSlot)
        #expect(d(b, [], alarmWall: alarmWall) == .silenced(atWallMs: alarmWall + lag + 1_000))
        b.current = Self.slot("G", alarmWall + lag + 1_001, kind: .guardSlot)
        #expect(d(b, [], alarmWall: alarmWall) == .ring)
        // Cover exactly at now, gone from the list → silenced at its time.
        var c = AlarmLedger.empty
        c.current = Self.slot("G", now, kind: .guardSlot)
        #expect(d(c, [], alarmWall: now - lag) == .silenced(atWallMs: now))
        // Unreadable list, cover still in the future → wait for it.
        c.current = Self.slot("G", now + 1, kind: .guardSlot)
        #expect(d(c, nil, alarmWall: now - lag + 1) == .none)
        // Far current, near stale → the stale slot is the cover.
        var e = AlarmLedger.empty
        e.current = Self.slot("F", now + 3_600_000)
        e.stale = Self.slot("G", now + 10_000, kind: .guardSlot)
        #expect(d(e, [Self.info("G", .scheduled, kind: .guardSlot)], alarmWall: now - 15_000) == .none)
    }
}

@Suite("TesterT17Runtime")
struct TesterT17RuntimeTests {
    typealias U = RuntimeUnitTests

    static func tripAlarms(_ w: World, _ trip: String = "t1") -> [SystemAlarmInfo] { w.alarms.all.filter { $0.tripId == trip } }

    @Test("AlarmKit drops the now alarm before it rings: the guard slot wakes the user ≤ lag after the decision, once")
    func nowDroppedGuardWakes() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        let decidedWall = w.time.wallMs()
        guard let n = U.nowAlarms(w).first else { Issue.record("no now alarm"); return }
        #expect(Self.tripAlarms(w).contains { $0.kind == .guardSlot && $0.state == .scheduled })
        w.alarms.setState(n.id, nil)  // lost by AlarmKit, never alerts
        await w.settle()
        await w.advance(by: 45_000)
        let rings = w.alarms.transitionList.filter { $0.tripId == "t1" }
        #expect(rings.count == 1, "exactly one ring: \(rings.map(\.kind))")
        #expect(rings.first?.kind == .guardSlot)
        if let r = rings.first { #expect(r.wall <= decidedWall + 30_000, "guard rang \(r.wall - decidedWall) ms after the decision") }
        #expect(w.alarms.doubleRings == 0)
        #expect(w.seen.entries.last?.view.alarmRinging == true)
    }

    @Test("StopIntent whose ring event could not be written (disk error): the running trip still ends, nothing rings again")
    func stopIntentWithoutRingEventOnDisk() async {
        let w = World()
        let slot = await U.diedAndStopped(w)
        let now0 = U.nowAlarms(w).count
        let starts0 = w.location.startCount
        await w.advance(by: 40)
        // D12 step (1) failed (try? in RuntimeHost.appendRingEventSync); the intent still hands the record over in memory.
        let rec = RingEventRec(tripId: "t1", alarmId: slot.alarmId, kind: slot.kind, action: .dismiss, atWallMs: w.time.wallMs())
        await w.runtime.onStopIntent(rec)
        await w.settle()
        await w.advance(by: 30 * 60_000)
        #expect(U.nowAlarms(w).count == now0, "no now alarm after Stop")
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1, "no second ring after Stop")
        #expect(w.location.startCount == starts0)
        let ended = w.store.finished["t1"] != nil
        let mode = await w.runtime.mode()
        // Bug #2 of docs/test-reports/T17.md (fixed, coder round 4): the record handed over in memory is used.
        #expect(ended, "§5.6.5: StopIntent of the running trip → UserAction(DISMISS) → TripEnded")
        #expect(mode == .idle)
    }

    @Test("A slot kept as `stale` (list unreadable while re-scheduling) is not orphaned by the next re-schedule")
    func staleSlotNotOrphaned() async {
        let w = World()
        #expect(await U.started(w) == .started)
        let a = w.store.currentLedger.current!
        let alarms = w.alarms
        alarms.onSchedule = { _ in alarms.listUnreadable = true }
        await w.runtime.onClockChanged()  // re-schedules A as B; the list read before cancelling A fails → A kept as stale
        alarms.onSchedule = nil
        alarms.listUnreadable = false
        await w.settle()
        #expect(w.store.currentLedger.stale?.alarmId == a.alarmId)
        await w.runtime.onClockChanged()  // re-schedules B as C
        await w.settle()
        let l = w.store.currentLedger
        let slots = Self.tripAlarms(w).filter { $0.kind != .now && $0.state == .scheduled }
        let known = Set([l.current?.alarmId, l.stale?.alarmId].compactMap { $0 })
        let orphans = slots.filter { !known.contains($0.id) }.count
        // Consequence: the forgotten slot A must not ring at its old time.
        await w.advance(to: a.targetAtWallMs - w.startWall + 1_000)
        let forgottenRang = w.alarms.transitionList.contains { $0.id == a.alarmId }
        #expect(w.alarms.doubleRings == 0, "two slot alarms of the trip alerting at once")
        // Bug #1 of docs/test-reports/T17.md (fixed, coder round 4): scheduleSlot also retires the previous stale slot.
        #expect(orphans == 0, "slot alarms unknown to the ledger: \(orphans)")
        #expect(slots.count == 1, "one fallback slot expected, found \(slots.count)")
        #expect(!forgottenRang, "forgotten slot rang")
    }

    @Test("Clock change with a dead current slot and a live stale slot: the live slot is moved, not left at the old wall time")
    func clockChangeMovesLiveStale() async {
        let w = World()
        #expect(await U.started(w) == .started)
        let a = w.store.currentLedger.current!
        let alarms = w.alarms
        alarms.onSchedule = { _ in alarms.listUnreadable = true }
        await w.runtime.onClockChanged()
        alarms.onSchedule = nil
        alarms.listUnreadable = false
        await w.settle()
        let b = w.store.currentLedger.current!
        #expect(w.store.currentLedger.stale?.alarmId == a.alarmId)
        alarms.setState(b.alarmId, nil)  // B lost by the system before its time
        await w.settle()
        w.time.shiftWall(600_000)  // the user moves the clock forward 10 min
        await w.runtime.onClockChanged()
        await w.settle()
        let atOldWall = Self.tripAlarms(w).filter { $0.state == .scheduled && $0.fireAtWallMs == a.targetAtWallMs }
        let slotCount = Self.tripAlarms(w).filter { $0.kind != .now && $0.state == .scheduled }.count
        #expect(Self.tripAlarms(w).contains { $0.state == .scheduled && $0.fireAtWallMs == a.targetAtWallMs + 600_000 },
                "the live slot is re-scheduled on the new wall clock")
        // Bug #1 (variant, fixed, coder round 4): the live stale slot is moved and the dead current one retired.
        #expect(atOldWall.isEmpty, "a slot still fires at the pre-change wall time (\(atOldWall.count))")
        #expect(slotCount == 1)
    }

    @Test("Reboot mid-trip (new boot id, wall moved on), user opens the app: alarms intact → PENDING, tracking again, no ring")
    func rebootThenOpen() async {
        let w = World()
        w.time.setBoot("boot-A")
        #expect(await U.started(w) == .started)
        await U.drive(w, km: 30, max: 6) { false }
        let slot = w.store.currentLedger.current!
        w.kill()
        await w.advance(by: 120_000)
        w.time.reboot("boot-B")
        w.relaunch(.active)
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(w.journal.all.contains { $0.ev == "restore" && $0.fields["status"] == "PENDING" })
        #expect(w.journal.all.contains { $0.ev == "proc_start" && $0.fields["bootChanged"] == "true" })
        #expect(await w.runtime.mode() == .tracking)
        #expect(U.nowAlarms(w).isEmpty)
        #expect(Self.tripAlarms(w).contains { $0.id == slot.alarmId && $0.state == .scheduled }
                || w.store.currentLedger.current != nil)
        #expect(w.alarms.transitionList.isEmpty)
    }
}
