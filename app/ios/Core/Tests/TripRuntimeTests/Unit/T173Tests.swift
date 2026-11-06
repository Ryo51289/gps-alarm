import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T17.3 (docs/specs/T17.3.md): the notification channel. NU01–NU10, plus the request plan, the list mapping, the budget
/// and the router (NC02 checks the UNNotificationRequest built from the plan on the Simulator).
@Suite("T173")
struct T173Tests {
    static let notificationsOnly = ChannelAccess(alarmKit: .unavailable, notifications: true)

    /// A world whose only channel is the notification channel (iOS 16–25, or AlarmKit denied).
    static func notifWorld(constants: RuntimeConstants = .default) -> World {
        let w = World(constants: constants)
        w.env.channels = notificationsOnly
        return w
    }

    static func request(_ id: String = "X", kind: SystemAlarmKind = .fallback, fire: Int64, trip: String = "t1",
                        sound: String? = "alarm_horn.wav") -> SystemAlarmRequest {
        SystemAlarmRequest(id: id, tripId: trip, kind: kind, generation: 7, fireAtWallMs: fire, title: "Sắp tới Ga Đông Hà",
                           channel: .notification, soundFile: sound)
    }

    static func rec(_ id: String, fire: Int64, kind: SystemAlarmKind = .fallback, trip: String = "t1") -> NotificationRecord {
        NotificationRecord(id: id, userInfo: ["tripId": trip, "kind": kind.rawValue, "generation": "3",
                                              "fireAtWallMs": String(fire), "rep": String(NotificationAlarmPlan.parse(id)?.rep ?? 0)])
    }

    // MARK: - Pure

    @Test("NU01 fireTimes, requestId/parse")
    func nu01() {
        #expect(NotificationAlarmPlan.fireTimes(1_000_000) == [1_000_000, 1_030_000, 1_060_000])
        #expect(NotificationAlarmPlan.requestId("X", rep: 2) == "X#2")
        let p = NotificationAlarmPlan.parse("X#2")
        #expect(p?.logicalId == "X" && p?.rep == 2)
        let uuid = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        let q = NotificationAlarmPlan.parse(NotificationAlarmPlan.requestId(uuid, rep: 0))
        #expect(q?.logicalId == uuid && q?.rep == 0)
        #expect(NotificationAlarmPlan.parse("X") == nil, "no #")
        #expect(NotificationAlarmPlan.parse("napstop.t1.preAlert") == nil, "a trip notice")
        #expect(NotificationAlarmPlan.parse("X#3") == nil && NotificationAlarmPlan.parse("X#") == nil)
        #expect(NotificationAlarmPlan.parse("#1") == nil && NotificationAlarmPlan.parse("X#+1") == nil)
        #expect(NotificationAlarmPlan.requestIds("X") == ["X#0", "X#1", "X#2"])
        #expect(NotificationAlarmPlan.pollTimes(1_000_000) == [1_001_000, 1_031_000, 1_061_000, 1_091_000])
    }

    @Test("NU02 state table, every cell, boundary fire + 90 s → other")
    func nu02() {
        let f: Int64 = 1_000_000
        func s(_ p: Set<Int>, _ d: Set<Int>, _ now: Int64) -> SystemAlarmState {
            NotificationAlarmState.state(fireAtWallMs: f, pendingReps: p, deliveredReps: d, nowWallMs: now)
        }
        // ∅ delivered, pending ≠ ∅ → scheduled (before and after the fire time: not delivered yet).
        #expect(s([0, 1, 2], [], f - 10_000) == .scheduled)
        #expect(s([0, 1, 2], [], f + 100_000) == .scheduled)
        #expect(s([0], [], f) == .scheduled)
        // delivered ∋ 0 (or ≠ ∅), any pending, inside the window → alerting.
        #expect(s([1, 2], [0], f) == .alerting)
        #expect(s([2], [0, 1], f + 30_000) == .alerting)
        #expect(s([], [0, 1, 2], f + 89_999) == .alerting)
        #expect(s([], [1], f + 40_000) == .alerting, "delivered ≠ ∅ without #0")
        #expect(s([1, 2], [0], f - 5_000) == .alerting, "a now alarm: #0 delivered at once, before its fire time")
        // delivered ≠ ∅, outside the window → other; boundary.
        #expect(s([], [0, 1, 2], f + 90_000) == .other)
        #expect(s([], [0], f + 200_000) == .other)
        #expect(s([2], [0, 1], f + 90_000) == .other)
        // ∅ ∅ is never listed (state reports other).
        #expect(s([], [], f) == .other)
        // #0 swiped away by the user, #1/#2 still pending: it was delivered → alerting, then other.
        #expect(s([1, 2], [], f + 10_000) == .alerting)
        #expect(s([2], [], f + 95_000) == .other)
    }

    @Test("Plan: 3 requests, delays from now, now #0 at once, userInfo without title or coordinates")
    func plan() {
        let now: Int64 = 1_000_000
        let fb = NotificationAlarmPlan.requests(Self.request(fire: now + 600_000), nowWallMs: now)
        #expect(fb.map(\.id) == ["X#0", "X#1", "X#2"])
        #expect(fb.map(\.rep) == [0, 1, 2])
        #expect(fb.map(\.delayS) == [600, 630, 660])
        #expect(fb.allSatisfy { $0.soundFile == "alarm_horn.wav" && $0.title == "Sắp tới Ga Đông Hà" })
        #expect(fb[2].userInfo == ["tripId": "t1", "kind": "fallback", "generation": "7", "fireAtWallMs": "1600000", "rep": "2"])
        #expect(fb.allSatisfy { !$0.userInfo.values.contains { $0.contains("Đông Hà") } })
        #expect(!"\(fb[0])".contains("Đông Hà"), "description redacts the title")
        let n = NotificationAlarmPlan.requests(Self.request(kind: .now, fire: now + 5_000, sound: nil), nowWallMs: now)
        #expect(n.map(\.delayS) == [nil, 35, 65])
        #expect(n.allSatisfy { $0.soundFile == nil })
        // A past or near fire time: at least 1 s (UNTimeIntervalNotificationTrigger needs > 0).
        let late = NotificationAlarmPlan.requests(Self.request(fire: now - 40_000), nowWallMs: now)
        #expect(late.map(\.delayS) == [1, 1, 20])
    }

    @Test("List mapping: grouped by logical id, trip notices and incomplete records ignored, sorted by fire time")
    func listMapping() {
        let f: Int64 = 2_000_000
        let pending = [Self.rec("B#1", fire: f + 100_000), Self.rec("A#1", fire: f), Self.rec("A#2", fire: f),
                       NotificationRecord(id: "napstop.t1.preAlert", userInfo: ["tripId": "t1"]),
                       NotificationRecord(id: "C#0", userInfo: ["tripId": "t1"]),
                       Self.rec("B#0", fire: f + 100_000), Self.rec("B#2", fire: f + 100_000)]
        let delivered = [Self.rec("A#0", fire: f)]
        let l = NotificationAlarmList.infos(pending: pending, delivered: delivered, nowWallMs: f + 1_000)
        #expect(l.map(\.id) == ["A", "B"])
        #expect(l.map(\.state) == [.alerting, .scheduled])
        #expect(l.allSatisfy { $0.channel == .notification && $0.tripId == "t1" && $0.kind == .fallback && $0.generation == 3 })
        #expect(l.map(\.fireAtWallMs) == [f, f + 100_000])
    }

    @Test("Budget: 6 logical alarms (18 requests) fit NOTIF_PENDING_BUDGET, the 7th is refused, re-scheduling an id does not count twice")
    func budget() async throws {
        #expect(NotificationBudget.fits(pendingCount: 17, adding: 3, budget: 20))
        #expect(!NotificationBudget.fits(pendingCount: 18, adding: 3, budget: 20))
        let time = VirtualTime(wallBase: 1_000_000)
        let center = FakeNotificationCenter(time: time)
        let ch = NotificationAlarmChannel(center: center, now: { time.wallMs() }, budget: 20)
        for i in 0..<6 { try await ch.schedule(Self.request("L\(i)", fire: 2_000_000 + Int64(i) * 1_000)) }
        #expect(center.pendingCount == 18)
        try await ch.schedule(Self.request("L0", fire: 2_500_000))  // replaces its own 3
        #expect(center.pendingCount == 18)
        await #expect(throws: AlarmChannelError.budgetExceeded) { try await ch.schedule(Self.request("L6", fire: 3_000_000)) }
        #expect(center.pendingCount == 18 && !center.plans.contains { $0.id.hasPrefix("L6") })
        #expect(center.maxPending <= 20)
    }

    @Test("NU08 schedule fails at #1: #0 removed, error thrown; through the runtime → FallbackScheduled(ok=false)")
    func nu08() async {
        let time = VirtualTime(wallBase: 1_000_000)
        let center = FakeNotificationCenter(time: time)
        center.failAdd = { $0.rep == 1 }
        let ch = NotificationAlarmChannel(center: center, now: { time.wallMs() })
        await #expect(throws: ScheduleFailure.self) { try await ch.schedule(Self.request(fire: 1_600_000)) }
        #expect(center.plans.map(\.id) == ["X#0"])
        #expect(center.snapshot().pending.isEmpty && center.snapshot().delivered.isEmpty)
        #expect(center.opLog.contains("removePending X#0,X#1,X#2") && center.opLog.contains("removeDelivered X#0,X#1,X#2"))
        // Runtime: the first fallback slot cannot be set.
        let w = Self.notifWorld()
        w.alarms.center.failAdd = { $0.rep == 1 }
        #expect(await RuntimeUnitTests.started(w) == .started)
        #expect(w.seen.entries.last?.view.fallbackStatus == .failed)
        #expect(w.notifier.shownNow.contains(.fallbackFailed))
        #expect(w.alarms.center.snapshot().pending.isEmpty)
        #expect(w.store.currentLedger.current == nil)
    }

    // MARK: - Router (D6)

    /// An AlarmKit channel whose list throws (nil) or returns `items`.
    final class FakeAK: Locked, SystemAlarms, @unchecked Sendable {
        let items: [SystemAlarmInfo]?
        init(_ items: [SystemAlarmInfo]?) { self.items = items }
        func schedule(_ r: SystemAlarmRequest) async throws {}
        func cancel(id: String, channel: AlarmChannelKind) async {}
        func stop(id: String, channel: AlarmChannelKind) async {}
        func list() async -> SystemAlarmList? { items.map { SystemAlarmList(items: $0) } }
    }

    @Test("NU09 router: AlarmKit list throws → the notification slot is listed with alarmKitUnreadable (not nil, O8)")
    func nu09() async throws {
        let time = VirtualTime(wallBase: 1_000_000)
        let center = FakeNotificationCenter(time: time)
        let notif = NotificationAlarmChannel(center: center, now: { time.wallMs() })
        try await notif.schedule(Self.request("N", fire: 1_600_000))
        let broken = SystemAlarmsRouter(alarmKit: FakeAK(nil), notifications: notif)
        let l = try #require(await broken.list())
        #expect(l.alarmKitUnreadable)
        #expect(l.items.map(\.id) == ["N"] && l.items.first?.state == .scheduled && l.items.first?.channel == .notification)
        let ak = SystemAlarmInfo(id: "A", tripId: "t1", kind: .fallback, generation: 1, state: .scheduled, fireAtWallMs: 5,
                                 channel: .alarmKit)
        let ok = try #require(await SystemAlarmsRouter(alarmKit: FakeAK([ak]), notifications: notif).list())
        #expect(!ok.alarmKitUnreadable && ok.items.map(\.id) == ["A", "N"])
        let old = try #require(await SystemAlarmsRouter(alarmKit: nil, notifications: notif).list())
        #expect(!old.alarmKitUnreadable && old.items.map(\.id) == ["N"], "iOS < 26: no AlarmKit channel, nothing unreadable")
        // Routing by channel.
        await broken.cancel(id: "N", channel: .notification)
        #expect(center.snapshot().pending.isEmpty)
        await #expect(throws: AlarmChannelError.unavailable) {
            try await SystemAlarmsRouter(alarmKit: nil, notifications: notif).schedule(
                SystemAlarmRequest(id: "Z", tripId: "t1", kind: .fallback, generation: 1, fireAtWallMs: 2_000_000, title: "",
                                   channel: .alarmKit))
        }
    }

    // MARK: - Runtime

    /// A far trip on the notification channel: the engine's fallback slot is set (3 pending requests).
    static func farTrip(_ w: World) async -> AlarmSlotRec {
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.drive(w, km: 30, max: 6) { false }
        let slot = w.store.currentLedger.current!
        #expect(slot.channel == .notification && slot.kind == .fallback)
        return slot
    }

    @Test("NU03 fallback slot on the notification channel: the poll at F + 1 s → FallbackFired(F) once, other trip alarm cancelled")
    func nu03() async throws {
        for akUnreadable in [false, true] {
            let w = Self.notifWorld()
            w.alarms.alarmKitUnreadable = akUnreadable  // D6: an AlarmKit read error does not hide the notification channel
            let slot = await Self.farTrip(w)
            #expect(w.alarms.center.pendingCount == 3)
            // Another scheduled alarm of the trip (as a guard slot would be).
            try await w.alarms.schedule(Self.request("EXTRA", kind: .guardSlot, fire: slot.targetAtWallMs + 600_000))
            // The app is frozen until the slot rings (no fixes, no engine ticks), then the timer runs.
            w.suspended = true
            await w.advance(to: slot.targetAtWallMs - w.startWall + 1_000)
            w.suspended = false
            await w.advance(by: 0)
            let fired = w.journal.all.filter { $0.ev == "fb_fired" && $0.fields["src"] == "interpreter" }
            #expect(fired.count == 1, "akUnreadable=\(akUnreadable)")
            #expect(w.store.currentLedger.lastFired?.alarmId == slot.alarmId)
            #expect(w.store.currentLedger.lastFired?.firedAtWallMs == slot.targetAtWallMs, "firedAt = F")
            #expect(w.seen.entries.last?.view.phase == .alarming && w.seen.entries.last?.view.alarmRinging == true)
            #expect(!w.alarms.all.contains { $0.id == "EXTRA" }, "K4 #3 / obligation 4: the other alarm is cancelled")
            #expect(w.alarms.cancels.contains("EXTRA"))
            #expect(w.alarms.all.first { $0.id == slot.alarmId }?.state == .alerting)
            #expect(RuntimeUnitTests.nowAlarms(w).isEmpty, "the slot rings; no now alarm")
            // The later polls do not feed it again.
            await w.advance(by: 70_000)
            #expect(w.journal.all.filter { $0.ev == "fb_fired" && $0.fields["src"] == "interpreter" }.count == 1)
            #expect(w.alarms.doubleRings == 0)
        }
    }

    @Test("NU04 now on the notification channel: #0 delivered → alerting → guard slot cancelled, seenAlerting")
    func nu04() async {
        let w = Self.notifWorld()
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        let now = RuntimeUnitTests.nowAlarms(w)
        #expect(now.map(\.channel) == [.notification])
        #expect(w.alarms.scheduledRequests().contains { $0.kind == .guardSlot && $0.channel == .notification })
        #expect(w.alarms.all.first { $0.kind == .now }?.state == .alerting, "trigger nil: delivered at once")
        await w.advance(by: 7_000)  // poll at fire + 1 s
        #expect(w.store.currentLedger.now?.seenAlerting == true)
        #expect(!w.alarms.all.contains { $0.kind != .now && $0.state == .scheduled }, "guard and fallback slots cancelled")
        #expect(w.alarms.all.filter { $0.state == .alerting }.map(\.kind) == [.now])
        #expect(w.seen.entries.last?.view.alarmRinging == true)
        // The reps of the now alarm keep coming (#1 at fire + 30 s, #2 at fire + 60 s).
        if let first = now.first {
            let d = w.alarms.center.pendingDeliveries
            #expect(d["\(first.id)#1"] == first.fireAtWallMs + 30_000 && d["\(first.id)#2"] == first.fireAtWallMs + 60_000)
        }
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("NU05 alerting, nobody acts: past fire + 91 s it leaves alerting → AlarmSilenced after STOP_INTENT_GRACE_MS")
    func nu05() async throws {
        let w = Self.notifWorld()
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        let n = try #require(RuntimeUnitTests.nowAlarms(w).first)
        await w.advance(to: n.fireAtWallMs + 85_000 - w.startWall)
        #expect(w.seen.entries.last?.view.alarmRinging == true, "still inside the window")
        await w.advance(to: n.fireAtWallMs + 91_000 + 1_000 - w.startWall)
        #expect(w.alarms.all.first { $0.id == n.id }?.state == .other)
        #expect(w.seen.entries.last?.view.alarmRinging == true, "grace not over")
        await w.advance(to: n.fireAtWallMs + 91_000 + 3_500 - w.startWall)
        #expect(w.seen.entries.last?.view.phase == .alarming && w.seen.entries.last?.view.alarmRinging == false)
        #expect(RuntimeUnitTests.nowAlarms(w).count == 1, "no ring again")
        #expect(!w.alarms.center.snapshot().pending.contains { NotificationAlarmPlan.parse($0.id)?.logicalId == n.id })
    }

    @Test("NU06 the user clears the 3 notifications at fire + 10 s: next poll → gone → AlarmSilenced, nothing rings again")
    func nu06() async throws {
        let w = Self.notifWorld()
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        let n = try #require(RuntimeUnitTests.nowAlarms(w).first)
        await w.advance(to: n.fireAtWallMs + 10_000 - w.startWall)
        w.alarms.userDismissNotifications(n.id)
        await w.advance(to: n.fireAtWallMs + 31_000 + 3_500 - w.startWall)
        #expect(w.seen.entries.last?.view.alarmRinging == false)
        #expect(RuntimeUnitTests.nowAlarms(w).count == 1)
        await w.advance(by: 120_000)
        #expect(RuntimeUnitTests.nowAlarms(w).count == 1, "not rung again")
        #expect(!w.alarms.all.contains { $0.state == .alerting })
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("NU07 A/B on the notification channel: new 3 requests before the old 3 are removed; old one alerting meanwhile → one ring, new slot cancelled")
    func nu07() async throws {
        // (a) The usual replacement (a clock change re-schedules the live slot).
        let a = Self.notifWorld()
        let oldA = await Self.farTrip(a)
        await a.runtime.onClockChanged()
        await a.settle()
        let newA = try #require(a.store.currentLedger.current)
        #expect(newA.alarmId != oldA.alarmId && newA.channel == .notification)
        let ops = a.alarms.center.opLog
        let lastAdd = try #require(ops.lastIndex { $0 == "add \(newA.alarmId)#2" })
        let firstRemove = try #require(ops.firstIndex { $0.hasPrefix("removePending") && $0.contains(oldA.alarmId) })
        #expect(lastAdd < firstRemove, "new requests first")
        #expect(ops.contains { $0.hasPrefix("removeDelivered") && $0.contains(oldA.alarmId) })
        #expect(a.alarms.all.map(\.id) == [newA.alarmId])
        #expect(a.alarms.center.pendingCount == 3)
        // (b) The old slot starts ringing while the new one is being scheduled (T10.5 §8). frozen: the app was frozen until
        // 10 s before the old slot (an overdue timer runs right after); not frozen: nothing else is due, only the poll that
        // `installSlot` asks for right after the command sees it.
        for frozen in [true, false] {
            let w = Self.notifWorld()
            let old = await Self.farTrip(w)
            if frozen {
                w.suspended = true
                await w.advance(to: old.targetAtWallMs - 10_000 - w.startWall)
                w.suspended = false
            }
            let alarms = w.alarms
            alarms.onSchedule = { r in
                if r.kind == .fallback { alarms.center.deliverNow(NotificationAlarmPlan.requestId(old.alarmId, rep: 0)) }
            }
            await w.runtime.onClockChanged()
            alarms.onSchedule = nil
            await w.settle()
            await w.advance(by: 1)  // the poll right after the command
            #expect(w.alarms.all.filter { $0.state == .alerting }.map(\.id) == [old.alarmId], "frozen=\(frozen)")
            #expect(!w.alarms.all.contains { $0.state == .scheduled && $0.kind == .fallback }, "new slot cancelled")
            #expect(w.store.currentLedger.lastFired?.alarmId == old.alarmId)
            if !frozen {
                #expect(w.journal.all.filter { $0.ev == "fb_fired" && $0.fields["src"] == "interpreter" }.count == 1)
            }
            await w.advance(by: 120_000)
            let rings = w.alarms.transitionList.filter { $0.tripId == "t1" }
            #expect(rings.map(\.id) == [old.alarmId], "one ring")
            // FallbackFired once: from the planner when the overdue timer's engine ring (GPS_LOST) sees the slot alerting
            // (obligation 3), else from the interpreter's poll; never both.
            #expect(w.journal.all.filter { $0.ev == "fb_fired" }.count == 1, "frozen=\(frozen)")
            #expect(RuntimeUnitTests.nowAlarms(w).isEmpty)
            #expect(w.alarms.doubleRings == 0)
        }
    }

    @Test("NU10 restore: the notification slot was delivered while no process ran (other) → RANG(fb), no ringNow")
    func nu10() async throws {
        // Pure: RestorePlanner on a stored state.
        let facts = try #require(EngineFacts.read(try TripEngine.start(
            config: TestData.meta().config(destLat: TestData.destLat, destLng: TestData.destLng), params: .defaults,
            nowMs: 1_000).state))
        var l = AlarmLedger.empty
        l.current = AlarmSlotRec(alarmId: "S", kind: .fallback, generation: 1, targetAtMs: 50_000, targetAtWallMs: 50_000,
                                 setAtWallMs: 0, channel: .notification)
        func info(_ s: SystemAlarmState) -> RestoreInfo {
            let x = SystemAlarmInfo(id: "S", tripId: "t1", kind: .fallback, generation: 1, state: s, fireAtWallMs: 50_000,
                                    channel: .notification)
            return RestorePlanner.plan(facts, ledger: l, events: [], list: [x], nowTripMs: 200_000, toTrip: { $0 })
        }
        #expect(info(.other) == RestoreInfo(status: .rang, firedAtMs: 50_000))
        #expect(info(.alerting) == RestoreInfo(status: .rang, firedAtMs: 50_000))
        #expect(RestoreRingPolicy.decide(info: info(.other), ledger: l, list: [], nowWallMs: 200_000, lagMs: 30_000,
                                         graceMs: 20_000, alarmWallMs: 50_000) == .silenced(atWallMs: 200_000))
        // Runtime: the process dies, the slot rings (3 notifications, window over), the user opens the app.
        let w = Self.notifWorld()
        let slot = await Self.farTrip(w)
        w.kill()
        await w.advance(to: slot.targetAtWallMs + 120_000 - w.startWall)
        #expect(w.alarms.all.first { $0.id == slot.alarmId }?.state == .other)
        w.relaunch(.active)
        await w.listen()
        await w.settle()
        #expect(w.journal.all.contains { $0.ev == "restore" && $0.fields["status"] == FallbackRestoreStatus.rang.jsonName })
        #expect(RuntimeUnitTests.nowAlarms(w).isEmpty, "no ringNow")
        let v = try #require(w.seen.entries.last?.view)
        #expect(v.phase == .alarming && !v.alarmRinging, "R2 step 1: rang, silenced")
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("Restore re-creates the polls: a slot set before the process died is seen ringing by the new process")
    func restorePolls() async {
        let w = Self.notifWorld()
        let slot = await Self.farTrip(w)
        w.kill()
        await w.advance(by: 10_000)
        w.relaunch(.active)
        await w.listen()
        await w.settle()
        // No fixes: only the polls (and the engine timer) run.
        w.suspended = true
        await w.advance(to: slot.targetAtWallMs - 1_000 - w.startWall)
        w.suspended = false
        await w.advance(by: 2_500)
        #expect(w.store.currentLedger.lastFired?.alarmId == slot.alarmId)
        #expect(w.journal.all.filter { $0.ev == "fb_fired" && $0.fields["src"] == "interpreter" }.count == 1)
    }

    @Test("IU13b (review round 2 nit #1): a live slot inside the 30 s window at the retry check rings unanswered and goes → the retries go on", arguments: [false, true])
    func iu13LiveSlotThenGone(_ notification: Bool) async {
        var c = RuntimeConstants.default
        c.ringRetryMs = 10_000  // the first check runs while the guard slot (ring + 30 s) is still scheduled
        let w = notification ? Self.notifWorld(constants: c) : World(constants: c)
        w.alarms.fail = { $0.kind == .now }
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        #expect(RuntimeUnitTests.nowAlarms(w).isEmpty && w.notifier.shownNow.contains(.ringFailed))
        let guards0 = w.alarms.scheduledRequests().filter { $0.kind == .guardSlot }.count
        #expect(guards0 == 1)
        w.alarms.silenceAfterMs = 10_000  // AlarmKit: the guard rings and goes; notification: its 90 s window ends
        // Fixes keep coming (they keep pushing the engine timer back): only the .ringRetry entry runs the retry.
        await RuntimeUnitTests.drive(w, km: 0.5, max: 50) { false }
        #expect(w.alarms.scheduledRequests().filter { $0.kind == .guardSlot }.count > guards0,
                "notification=\(notification): a new guard after the first one rang unanswered")
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("D6: an AlarmKit update never makes a notification alarm look gone (no false AlarmSilenced)")
    func akUpdateKeepsNotifications() async {
        let w = World()
        w.alarms.fail = { $0.kind == .now && $0.channel == .alarmKit }  // now on the notification channel, slots on AlarmKit
        #expect(await RuntimeUnitTests.started(w) == .started)
        await RuntimeUnitTests.ringing(w)
        #expect(RuntimeUnitTests.nowAlarms(w).map(\.channel) == [.notification])
        await w.advance(by: 7_000)  // poll: now alerting (guard slot on AlarmKit cancelled → an AlarmKit update)
        #expect(w.store.currentLedger.now?.seenAlerting == true)
        // AlarmKit updates (AlarmKit alarms only) while the notification "now" rings.
        await w.runtime.onSystemAlarms(w.alarms.alarmKitAll, channel: .alarmKit)
        await w.advance(by: 10_000)
        #expect(w.seen.entries.last?.view.alarmRinging == true, "no AlarmSilenced from the AlarmKit-only update")
        #expect(w.alarms.all.first { $0.kind == .now }?.state == .alerting)
    }
}
