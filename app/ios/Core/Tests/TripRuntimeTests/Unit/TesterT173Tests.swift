import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Tester T17.3 (docs/test-reports/T17.3.md): edge cases of the notification channel outside NU01–NU10. Virtual time and
/// fakes only (deterministic, no network).
@Suite("TesterT173")
struct TesterT173Tests {
    static let akAndNotif = ChannelAccess(alarmKit: .authorized, notifications: true)
    static let notifOnly = T173Tests.notificationsOnly

    /// `n` pending requests of the app that are not alarm requests (unparsable ids), far in the future.
    static func fillForeign(_ center: FakeNotificationCenter, _ n: Int) async throws {
        for i in 0..<n {
            try await center.add(NotificationRequestPlan(id: "foreign.\(i)", rep: 0, title: "", soundFile: nil,
                                                         delayS: 1_000_000, userInfo: [:]))
        }
    }

    static func fbFired(_ w: World) -> Int { w.journal.all.filter { $0.ev == "fb_fired" }.count }

    /// The notification slot rings while the app is frozen; the app wakes 1 s after F.
    static func ringSlotFrozen(_ w: World, _ slot: AlarmSlotRec) async {
        w.suspended = true
        await w.advance(to: slot.targetAtWallMs - w.startWall + 1_000)
        w.suspended = false
        await w.advance(by: 0)
    }

    // MARK: - Channel switch mid-trip

    @Test("AlarmKit granted mid-trip: the next slot is on AlarmKit, the 3 old requests are removed, one ring, no notification delivered")
    func grantAlarmKitMidTrip() async throws {
        let w = T173Tests.notifWorld()
        let old = await T173Tests.farTrip(w)
        #expect(w.alarms.center.pendingCount == 3)
        w.env.channels = Self.akAndNotif
        await w.runtime.onClockChanged()
        await w.settle()
        let cur = try #require(w.store.currentLedger.current)
        #expect(cur.alarmId != old.alarmId && cur.channel == .alarmKit)
        #expect(w.alarms.center.snapshot().pending.isEmpty, "old notification slot removed (A/B, D8)")
        #expect(w.store.currentLedger.stale == nil)
        #expect(w.alarms.all.map(\.id) == [cur.alarmId])
        await Self.ringSlotFrozen(w, cur)
        #expect(w.store.currentLedger.lastFired?.alarmId == cur.alarmId)
        #expect(Self.fbFired(w) == 1)
        await w.advance(by: 120_000)
        #expect(w.alarms.center.snapshot().delivered.isEmpty, "the cancelled notification slot never rang")
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.map(\.id) == [cur.alarmId])
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("AlarmKit revoked mid-trip: the next slot is on the notification channel, the AlarmKit slot is cancelled, the slot rings once")
    func revokeAlarmKitMidTrip() async throws {
        let w = World()
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.drive(w, km: 30, max: 6) { false }
        let old = try #require(w.store.currentLedger.current)
        #expect(old.channel == .alarmKit)
        w.env.channels = Self.notifOnly
        await w.runtime.onClockChanged()
        await w.settle()
        let cur = try #require(w.store.currentLedger.current)
        #expect(cur.channel == .notification && cur.alarmId != old.alarmId)
        #expect(w.alarms.cancels.contains(old.alarmId))
        #expect(w.alarms.alarmKitAll.isEmpty)
        #expect(w.alarms.center.pendingCount == 3)
        await Self.ringSlotFrozen(w, cur)
        #expect(w.store.currentLedger.lastFired?.alarmId == cur.alarmId)
        #expect(Self.fbFired(w) == 1)
        await w.advance(by: 120_000)
        #expect(Self.fbFired(w) == 1)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.map(\.id) == [cur.alarmId])
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("AlarmKit granted while the notification slot rings: the clock change does not cancel it, nothing else rings")
    func grantAlarmKitWhileNotificationRings() async throws {
        let w = T173Tests.notifWorld()
        let slot = await T173Tests.farTrip(w)
        await Self.ringSlotFrozen(w, slot)
        #expect(w.store.currentLedger.lastFired?.alarmId == slot.alarmId)
        w.env.channels = Self.akAndNotif
        await w.runtime.onClockChanged()
        await w.settle()
        await w.advance(by: 1)
        #expect(w.alarms.all.first { $0.id == slot.alarmId }?.state == .alerting, "K4 #4: a ringing slot is never cancelled")
        #expect(!w.alarms.all.contains { $0.channel == .alarmKit && $0.state == .alerting })
        await w.advance(by: 120_000)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.map(\.id) == [slot.alarmId], "one ring")
        #expect(Self.fbFired(w) == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    // MARK: - Budget (D7) at the boundary, through the runtime

    @Test("Budget boundary at start: 17 other pending + 3 = 20 → the fallback slot is set; 18 + 3 = 21 → FAILED and the UI is told")
    func budgetBoundaryAtStart() async throws {
        let ok = T173Tests.notifWorld()
        try await Self.fillForeign(ok.alarms.center, 17)
        #expect(await RuntimeUnitTests.started(ok) == .started)
        #expect(ok.store.currentLedger.current?.channel == .notification)
        #expect(ok.seen.entries.last?.view.fallbackStatus != .failed)
        #expect(ok.alarms.center.maxPending == 20)
        #expect(ok.alarms.budgetRejections == 0)

        let over = T173Tests.notifWorld()
        try await Self.fillForeign(over.alarms.center, 18)
        #expect(await RuntimeUnitTests.started(over) == .started)
        #expect(over.store.currentLedger.current == nil)
        #expect(over.seen.entries.last?.view.fallbackStatus == .failed)
        #expect(over.notifier.shownNow.contains(.fallbackFailed))
        #expect(over.alarms.budgetRejections >= 1)
        #expect(over.alarms.center.maxPending == 18, "never above the budget")
    }

    /// After a failed ring the user is near the destination; fixes every 5 s for `seconds`.
    static func keepDriving(_ w: World, seconds: Int) async {
        for _ in 0..<(seconds / 5) {
            await w.advance(by: 5_000)
            await w.emit(TestData.fix(kmSouth: 0.5, wall: w.time.wallMs()))
        }
    }

    /// Guard slots scheduled (ok) after `wall`.
    static func guardsAfter(_ w: World, _ wall: Int64) -> Int {
        w.alarms.scheduleLog.filter { $0.kind == .guardSlot && $0.wall > wall }.count
    }

    @Test("Budget refuses the now alarm and its guard: G2 (ringFailed, AlarmSilenced), budget never passed")
    func budgetRefusesNowAndGuard() async throws {
        let w = T173Tests.notifWorld()
        try await Self.fillForeign(w.alarms.center, 15)
        #expect(await RuntimeUnitTests.started(w) == .started)
        #expect(w.alarms.center.pendingCount == 18)
        await RuntimeUnitTests.ringing(w)
        #expect(w.alarms.budgetRejections == 2, "guard and now refused")
        #expect(w.notifier.shownNow.contains(.ringFailed))
        #expect(w.seen.entries.last?.view.phase == .alarming && w.seen.entries.last?.view.alarmRinging == false)
        #expect(w.alarms.center.maxPending <= 20)
        #expect(!w.alarms.all.contains { $0.kind == .now })
    }

    /// BUG #1 (docs/test-reports/T17.3.md): when the guard slot cannot be set either, `ringRetryIfDue` sees the old fallback
    /// slot (hours away, the engine already dropped it) still `scheduled` and never retries (T17 §5.6.3 step 3). Same on
    /// AlarmKit. Fixed in T17.3 round 2 (no longer a known issue).
    @Test("G2 retry when the guard slot also failed: once scheduling works again a new guard is set within RING_RETRY_MS + one tick", arguments: ["notification", "alarmKit", "budget"])
    func g2RetryAfterGuardFailed(_ mode: String) async throws {
        let w = mode == "alarmKit" ? World() : T173Tests.notifWorld()
        if mode == "budget" {
            try await Self.fillForeign(w.alarms.center, 15)
        } else {
            w.alarms.fail = { $0.kind == .now || $0.kind == .guardSlot }
        }
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        #expect(w.notifier.shownNow.contains(.ringFailed), "\(mode)")
        let fb = try #require(w.store.currentLedger.current)
        #expect(fb.kind == .fallback && fb.targetAtWallMs > w.time.wallMs() + 3_600_000, "\(mode): the old fallback slot, > 1 h away")
        // Scheduling works again (transient error over / room in the budget).
        let healed = w.time.wallMs()
        if mode == "budget" {
            await w.alarms.center.removePending((0..<15).map { "foreign.\($0)" })
        } else {
            w.alarms.fail = nil
        }
        await Self.keepDriving(w, seconds: 90)
        #expect(Self.guardsAfter(w, healed) >= 1, "\(mode): a new guard slot after RING_RETRY_MS")
        #expect(w.alarms.transitionList.contains { $0.tripId == "t1" }, "\(mode): something of the trip rang")
        #expect(w.alarms.doubleRings == 0)
    }

    // MARK: - Restore

    @Test("Process killed while the notification now rings, relaunched inside the window: no second now, the reps go on")
    func killWhileNowRings() async throws {
        let w = T173Tests.notifWorld()
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        let n = try #require(RuntimeUnitTests.nowAlarms(w).first)
        await w.advance(to: n.fireAtWallMs + 2_000 - w.startWall)
        #expect(w.store.currentLedger.now?.seenAlerting == true)
        w.kill()
        await w.advance(to: n.fireAtWallMs + 40_000 - w.startWall)
        w.relaunch(.active)
        await w.listen()
        await w.settle()
        await w.advance(by: 1_000)
        #expect(RuntimeUnitTests.nowAlarms(w).count == 1, "no second now alarm")
        #expect(w.alarms.all.first { $0.id == n.id }?.state == .alerting)
        #expect(w.alarms.center.pendingDeliveries["\(n.id)#2"] == n.fireAtWallMs + 60_000, "#2 still comes")
        await w.advance(by: 120_000)
        #expect(RuntimeUnitTests.nowAlarms(w).count == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    // MARK: - D6 with an AlarmKit slot

    @Test("D6: AlarmKit list throws while the trip has an AlarmKit slot → same as an unreadable list (replaced slot kept as stale, not cancelled)")
    func akUnreadableWithAlarmKitSlot() async throws {
        for mode in ["listUnreadable", "alarmKitUnreadable"] {
            let w = World()
            #expect(await RuntimeUnitTests.started(w) == .started)
            let old = try #require(w.store.currentLedger.current)
            #expect(old.channel == .alarmKit)
            if mode == "listUnreadable" { w.alarms.listUnreadable = true } else { w.alarms.alarmKitUnreadable = true }
            // The engine moves the fallback slot as the ETA becomes known (fixes 30 km out).
            await RuntimeUnitTests.drive(w, km: 30, max: 12) { w.store.currentLedger.current?.alarmId != old.alarmId }
            let l = w.store.currentLedger
            #expect(l.current != nil && l.current?.alarmId != old.alarmId, "\(mode): slot re-planned")
            #expect(l.stale?.alarmId == old.alarmId, "\(mode): the replaced slot may be ringing; kept to retire later (#10)")
            #expect(!w.alarms.cancels.contains(old.alarmId), "\(mode)")
            w.alarms.listUnreadable = false
            w.alarms.alarmKitUnreadable = false
        }
    }

    /// Ring with the guard slot on the notification channel and the now alarm on AlarmKit (AlarmKit granted between the
    /// two schedule calls of one ring; `earlyPoll`: a notification poll runs before the now alarm alerts).
    static func mixedRing(earlyPoll: Bool) async throws -> (World, SystemAlarmRequest, SystemAlarmRequest) {
        let w = World()
        w.env.channels = Self.notifOnly
        let env = w.env
        w.alarms.onSchedule = { r in if r.kind == .guardSlot { env.channels = Self.akAndNotif } }
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        w.alarms.onSchedule = nil
        let now = try #require(RuntimeUnitTests.nowAlarms(w).first)
        let guardReq = try #require(w.alarms.scheduledRequests().last { $0.kind == .guardSlot })
        #expect(now.channel == .alarmKit && guardReq.channel == .notification)
        if earlyPoll, let d = w.timer.due {
            w.timer.consume()
            await w.runtime.onTimer(generation: d.gen)
            await w.settle()
        }
        await w.advance(by: 6_000)
        #expect(w.alarms.alarmKitAll.first { $0.id == now.id }?.state == .alerting)
        return (w, now, guardReq)
    }

    @Test("D6: AlarmKit list throws while the AlarmKit now rings and a notification poll runs → the ring is not taken as gone (no false AlarmSilenced)")
    func akUnreadableDuringPollKeepsAlarmKitRing() async throws {
        let (w, now, guardReq) = try await Self.mixedRing(earlyPoll: true)
        #expect(!w.alarms.all.contains { $0.id == guardReq.id }, "K4 #3: the guard slot is cancelled when the now alarm alerts")
        #expect(w.seen.entries.last?.view.alarmRinging == true)
        w.alarms.alarmKitUnreadable = true
        await w.advance(to: guardReq.fireAtWallMs + NotificationAlarmPlan.alertWindowMs + 5_000 - w.startWall)
        #expect(w.alarms.alarmKitAll.first { $0.id == now.id }?.state == .alerting, "AlarmKit still rings")
        #expect(w.seen.entries.last?.view.alarmRinging == true, "an unreadable AlarmKit list is not 'gone'")
        #expect(w.alarms.doubleRings == 0)
        w.alarms.alarmKitUnreadable = false
    }

    /// BUG #2 (docs/test-reports/T17.3.md): the AlarmKit update that shows the now alarm alerting only cancels notification
    /// alarms the runtime has already read; a notification guard scheduled since the last poll is not cancelled (K4 #3),
    /// rings 30 s later on top of the AlarmKit now, and when its window ends the runtime reports AlarmSilenced although
    /// AlarmKit still rings. Narrow: needs the guard and the now alarm of one ring on different channels. Remove
    /// Fixed in T17.3 round 2 (no longer a known issue).
    @Test("Mixed channels in one ring without an early poll: the notification guard is still cancelled, one ring only")
    func mixedRingGuardCancelled() async throws {
        let (w, now, guardReq) = try await Self.mixedRing(earlyPoll: false)
        await w.advance(to: guardReq.fireAtWallMs + NotificationAlarmPlan.alertWindowMs + 5_000 - w.startWall)
        #expect(w.alarms.alarmKitAll.first { $0.id == now.id }?.state == .alerting)
        #expect(!w.alarms.transitionList.contains { $0.id == guardReq.id }, "the guard slot never rings")
        #expect(w.alarms.doubleRings == 0)
        #expect(w.seen.entries.last?.view.alarmRinging == true, "no false AlarmSilenced while AlarmKit rings")
    }

    // MARK: - Round 2

    @Test("Round 2: a slot whose first channel fails goes to the second one (fallback at start, guard at ring), not FAILED")
    func slotFallsBackToSecondChannel() async throws {
        let w = World()
        w.alarms.fail = { $0.channel == .alarmKit && $0.kind != .now }
        #expect(await RuntimeUnitTests.started(w) == .started)
        let fb = try #require(w.store.currentLedger.current)
        #expect(fb.kind == .fallback && fb.channel == .notification)
        #expect(w.seen.entries.last?.view.fallbackStatus != .failed)
        #expect(!w.notifier.shownNow.contains(.fallbackFailed))
        #expect(w.alarms.center.pendingCount == 3)
        #expect(w.journal.all.contains { $0.ev == "ak" && $0.fields["ok"] == "false" && $0.fields["ch"] == "alarmKit" })
        await RuntimeUnitTests.ringing(w)
        let g = try #require(w.store.currentLedger.current)
        #expect(g.kind == .guardSlot && g.channel == .notification, "the guard slot of the ring on the second channel")
        #expect(RuntimeUnitTests.nowAlarms(w).map(\.channel) == [.alarmKit])
        await w.advance(by: 120_000)
        #expect(w.alarms.doubleRings == 0)
    }

    /// Review round 2 nit #1 without goneCheck/notifPoll to mask it: the live guard slot inside the window at the retry
    /// check is dropped by AlarmKit (never alerts, never goes), fixes keep pushing the engine timer back. Only the
    /// `.ringRetry` re-armed in that branch runs the next check.
    @Test("Round 2 nit #1: the live guard slot at the retry check never rings (dropped by AlarmKit) → a new guard follows")
    func liveGuardDroppedThenRetry() async throws {
        var c = RuntimeConstants.default
        c.ringRetryMs = 10_000  // the first check runs while the guard slot (ring + 30 s) is still ahead
        let w = World(constants: c)
        w.alarms.fail = { $0.kind == .now }
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        #expect(RuntimeUnitTests.nowAlarms(w).isEmpty && w.notifier.shownNow.contains(.ringFailed))
        let first = try #require(w.alarms.scheduledRequests().last { $0.kind == .guardSlot })
        w.alarms.neverAlert = { $0.id == first.id }
        await RuntimeUnitTests.drive(w, km: 0.5, max: 30) { false }
        let guards = w.alarms.scheduledRequests().filter { $0.kind == .guardSlot }
        #expect(guards.count >= 2, "a new guard after the dropped one")
        #expect(w.alarms.transitionList.contains { $0.tripId == "t1" && $0.kind == .guardSlot && $0.id != first.id },
                "the new guard rings")
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("Window boundary through the channel: alerting at fire + 89 999 ms, other at fire + 90 000 ms")
    func windowBoundaryThroughChannel() async throws {
        let time = VirtualTime(wallBase: 1_000_000)
        let center = FakeNotificationCenter(time: time)
        let ch = NotificationAlarmChannel(center: center, now: { time.wallMs() })
        let fire: Int64 = 1_600_000
        try await ch.schedule(T173Tests.request(fire: fire))
        func state() async -> SystemAlarmState? { await ch.list()?.items.first?.state }
        time.v = fire - 1 - 1_000_000
        #expect(await state() == .scheduled)
        time.v = fire - 1_000_000
        #expect(await state() == .alerting, "#0 delivered at F")
        time.v = fire + 89_999 - 1_000_000
        #expect(await state() == .alerting)
        time.v = fire + 90_000 - 1_000_000
        #expect(await state() == .other)
        await ch.stop(id: "X", channel: .notification)
        #expect(await ch.list()?.items.isEmpty == true)
    }
}
