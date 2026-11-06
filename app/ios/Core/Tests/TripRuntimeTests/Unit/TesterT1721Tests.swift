import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Tester T17.2.1 (docs/test-reports/T17.2.1.md): process deaths between the steps of the snooze intent and inside the
/// runtime hand-over, plus a repeated intent. Every case: the trip keeps an alarm, and rings once for one snooze.
@Suite("TesterT1721")
struct TesterT1721Tests {
    typealias U = RuntimeUnitTests
    typealias A = T172Tests
    typealias S = T1721Tests

    static func ringsAfter(_ w: World, _ tapWall: Int64) -> [(id: String, tripId: String, kind: SystemAlarmKind, wall: Int64)] {
        w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > tapWall }
    }

    @Test("Snooze fully handled but its ring event could not be removed, then the process dies: the restore does not snooze again, one ring ≤ 90 s after the tap")
    func removeFailedThenDied() async {
        let w = World()
        guard let now = await S.ringingNow(w) else { Issue.record("no now"); return }
        w.store.failRemoveRingEvents = true
        let tap = await S.snoozeIntent(w, alarmId: now.id)
        #expect(tap.result.outcome == .snoozed && tap.result.stopped)
        #expect(w.store.currentLedger.current?.alarmId == tap.rescue.id)
        let n0 = U.nowAlarms(w).count
        await w.advance(by: 10_000)
        w.kill()
        await w.advance(by: 5_000)
        w.relaunch(.background)
        await S.attach(w)
        await w.runtime.ensureLoaded()
        await w.advance(by: 2_100)  // D13 settle: the stale snooze event is read again
        #expect(U.nowAlarms(w).count == n0, "no ring at restore")
        #expect(w.alarms.all.contains { $0.id == tap.rescue.id && $0.state == .scheduled }, "the rescue slot is still there")
        await w.advance(by: 150_000)
        let rings = Self.ringsAfter(w, tap.rec.atWallMs)
        #expect(rings.count == 1, "one ring for one snooze, got \(rings.count)")
        if let r = rings.first {
            #expect(r.wall - tap.rec.atWallMs >= 55_000, "not earlier than the snooze (\(r.wall - tap.rec.atWallMs) ms)")
            #expect(r.wall - tap.rec.atWallMs <= 90_000 + w.constants.akNowLeadMs)
        }
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("Died after (1) only, the system had stopped the ring at the tap (RK-T1721-1): nothing rings while no process; on opening, the snooze is applied once and rings once")
    func diedAfterWriteRingAutoStopped() async {
        let w = World()
        guard let now = await S.ringingNow(w) else { Issue.record("no now"); return }
        w.kill()
        let (rec, _) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: now.id, kind: .now, tapWallMs: w.time.wallMs(),
                                                rescueId: UUID().uuidString, params: .defaults, locale: "vi")
        try? w.store.appendRingEvent(rec)  // (1); died before (2)
        w.alarms.setState(now.id, nil)  // the system stopped the ring itself at the tap
        await w.advance(by: 180_000)
        #expect(Self.ringsAfter(w, rec.atWallMs).isEmpty, "the remaining window: no alarm without a process")
        w.relaunch(.active)  // the user opens the app
        await S.attach(w)
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(A.snoozedEvents(w).count == 1)
        let opened = w.time.wallMs()
        await w.advance(by: 150_000)
        let rings = Self.ringsAfter(w, rec.atWallMs)
        #expect(rings.count == 1, "one ring after opening, got \(rings.count)")
        if let r = rings.first { #expect(r.wall - opened <= 90_000 + w.constants.akNowLeadMs) }
    }

    @Test("Snooze intent delivered twice (two rescues): one snooze, the second rescue is cancelled, one ring after the tap")
    func repeatedIntent() async {
        let w = World()
        guard let now = await S.ringingNow(w) else { Issue.record("no now"); return }
        let t1 = await S.snoozeIntent(w, alarmId: now.id)
        #expect(t1.result.outcome == .snoozed)
        await w.advance(by: 300)
        let t2 = await S.snoozeIntent(w, alarmId: now.id)
        #expect(A.snoozedEvents(w).count == 1)
        let gen0 = w.alarms.all.filter { $0.generation == RuntimeConstants.rescueGeneration && $0.state == .scheduled }
        #expect(gen0.count == 1, "one rescue left (the slot), got \(gen0.count)")
        #expect(!w.alarms.all.contains { $0.id == t2.rescue.id && $0.id != w.store.currentLedger.current?.alarmId },
                "the second rescue is not left behind")
        await w.advance(by: 150_000)
        #expect(Self.ringsAfter(w, t1.rec.atWallMs).count == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("Died after (2); the rescue is past due but still `scheduled` (AlarmKit dropped or late) when the app opens: it is not taken, a new slot rings")
    func overdueRescueNotTaken() async {
        let w = World()
        guard let now = await S.ringingNow(w) else { Issue.record("no now"); return }
        let (rec, rescue) = await S.diedAfterRescue(w, now: now)
        let rescueId = rescue.id
        w.alarms.neverAlert = { $0.id == rescueId }  // AlarmKit never rings it
        await w.advance(by: 100_000)  // past tap + 90 s
        #expect(w.alarms.all.first { $0.id == rescueId }?.state == .scheduled, "overdue, still listed as scheduled")
        w.relaunch(.active)
        await S.attach(w)
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(A.snoozedEvents(w).count == 1)
        #expect(w.store.currentLedger.current?.alarmId != rescueId, "an overdue rescue is not the slot")
        await w.advance(by: 150_000)
        let rings = Self.ringsAfter(w, rec.atWallMs)
        #expect(rings.count == 1, "the snooze still wakes the user, got \(rings.count) rings")
        #expect(!rings.contains { $0.id == rescueId })
    }

    @Test("Hand-over times out (3 s) and the process dies before the runtime handles it: the rescue alone wakes the user ≤ 90 s after the tap, once")
    func timeoutThenDied() async {
        let w = World()
        guard let now = await S.ringingNow(w) else { Issue.record("no now"); return }
        let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: now.id, kind: .now, tapWallMs: w.time.wallMs(),
                                                     rescueId: UUID().uuidString, params: .defaults, locale: "vi")
        let gate = S.Gate()
        let r = await SnoozeIntentFlow.perform(
            rec, rescue: rescue, budgetMs: 3_000,
            write: { try w.store.appendRingEvent($0) },
            schedule: { try await w.alarms.schedule($0) },
            handOver: { _ in await gate.wait(); return .snoozed },  // the runtime never answers in time
            stopSystemAlarm: { w.alarms.setState(now.id, nil) },
            journal: w.journal, sleep: { _ in })
        #expect(r.outcome == .timeout && r.stopped, "written + rescue → the ring is stopped on timeout")
        w.kill()  // the process dies before the runtime ran the snooze
        gate.open()
        await w.advance(by: 150_000)
        let rings = Self.ringsAfter(w, rec.atWallMs)
        #expect(rings.count == 1 && rings.first?.id == rescue.id, "the rescue rang alone")
        if let x = rings.first { #expect(x.wall - rec.atWallMs <= 90_000) }
    }
}
