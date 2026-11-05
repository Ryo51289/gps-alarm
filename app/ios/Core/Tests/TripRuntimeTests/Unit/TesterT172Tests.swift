import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Tester T17.2 (docs/test-reports/T17.2.md): edges outside the AU table. Mostly a process that dies while a secondary
/// button intent runs (D4: write → stop → hand over), plus launch-action TTL edges.
@Suite("TesterT172")
struct TesterT172Tests {
    typealias U = RuntimeUnitTests
    typealias A = T172Tests

    static func snoozed(_ w: World) -> [TripEvent.Snoozed] { A.snoozedEvents(w) }

    static func alarms(_ w: World, _ reason: AlarmReason) -> [TripEvent.Alarm] {
        w.seen.events.compactMap { if case let .alarm(a) = $0, a.reason == reason { return a }; return nil }
    }

    static func attach(_ w: World) async {
        _ = await w.runtime.addListenerWithoutRestoreWait { _, view, choice, events in
            w.seen.add(.init(view: view, choice: choice, events: events))
        }
    }

    // MARK: - Launch action TTL edges (pure)

    @Test("LaunchActionSlot edges: age exactly TTL is valid, TTL + 1 is not; negative age is not; same boot uses elapsed")
    func ttlEdges() {
        let ttl: Int64 = 600_000
        let r = LaunchActionRec(tripId: "t1", pastM: 250, atWallMs: 1_000_000, atElapsedMs: 50_000, bootSessionId: "B")
        func v(wall: Int64, elapsed: Int64, boot: String?) -> LaunchActionRec? {
            LaunchActionSlot.valid(r, nowWallMs: wall, nowElapsedMs: elapsed, bootSessionId: boot, ttlMs: ttl)
        }
        #expect(v(wall: 1_000_000 + ttl, elapsed: 50_000 + ttl, boot: "B") != nil)
        #expect(v(wall: 1_000_000 + ttl + 1, elapsed: 50_000 + ttl + 1, boot: "B") == nil)
        // Same boot: elapsed decides even when the wall clock jumped (user changed the time).
        #expect(v(wall: 1_000_000 + 10 * ttl, elapsed: 50_000 + 1_000, boot: "B") != nil)
        #expect(v(wall: 1_000_000, elapsed: 50_000 + ttl + 1, boot: "B") == nil)
        // Elapsed went back within the same boot id (impossible clock) → not valid.
        #expect(v(wall: 1_000_000, elapsed: 49_999, boot: "B") == nil)
        // Another boot: wall decides; a wall clock moved back → negative age → not valid.
        #expect(v(wall: 1_000_000 + ttl, elapsed: 1, boot: "C") != nil)
        #expect(v(wall: 999_999, elapsed: 1, boot: "C") == nil)
        // Unknown boot id on either side → wall.
        #expect(v(wall: 1_000_000 + 5_000, elapsed: 0, boot: nil) != nil)
        let noBoot = LaunchActionRec(tripId: "t1", pastM: nil, atWallMs: 1_000_000, atElapsedMs: 50_000, bootSessionId: nil)
        #expect(LaunchActionSlot.valid(noBoot, nowWallMs: 1_000_000 + ttl + 1, nowElapsedMs: 50_001, bootSessionId: nil,
                                       ttlMs: ttl) == nil)
        // pastM edges.
        for (p, out) in [(0, 0), (1_000_000, 1_000_000)] as [(Int, Int?)] {
            let x = LaunchActionRec(tripId: "t1", pastM: p, atWallMs: 1_000_000, atElapsedMs: 50_000, bootSessionId: "B")
            #expect(LaunchActionSlot.valid(x, nowWallMs: 1_000_000, nowElapsedMs: 50_000, bootSessionId: "B", ttlMs: ttl)?.pastM == out)
        }
        // Trip id length edge (64 ok, 65 not).
        #expect(LaunchActionSlot.validTripId(String(repeating: "a", count: 64)))
        #expect(!LaunchActionSlot.validTripId(String(repeating: "a", count: 65)))
    }

    // MARK: - Process death inside an intent

    /// ALARMING with the "now" alarm ringing; returns its request.
    static func ringingNow(_ w: World) async -> SystemAlarmRequest? {
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        return U.nowAlarms(w).first
    }

    @Test("Snooze intent killed after write + stop, before the hand-over; the user opens the app 5 min later: snoozed once, SNOOZE_END rings within a minute, once")
    func snoozeDiedBeforeHandOverThenOpen() async {
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let nows0 = U.nowAlarms(w).count
        w.kill()
        try? w.store.appendRingEvent(RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze,
                                                  atWallMs: w.time.wallMs()))  // (1)
        w.alarms.setState(now.id, nil)  // (2) stop; (3) never ran
        await w.advance(by: 300_000)
        #expect(!w.alarms.transitionList.contains { $0.wall > now.fireAtWallMs }, "nothing of the trip rings while no process")
        w.relaunch(.active)
        await Self.attach(w)
        await w.runtime.ensureLoaded()
        await w.settle()
        let opened = w.time.wallMs()
        #expect(Self.snoozed(w).count == 1)
        #expect(U.nowAlarms(w).count == nows0, "no ring at once on opening")
        await w.advance(by: 70_000)
        let rings = U.nowAlarms(w).dropFirst(nows0)
        #expect(rings.count == 1, "one SNOOZE_END ring, got \(rings.count)")
        if let r = rings.first { #expect(r.fireAtWallMs - opened <= 65_000 + w.constants.akNowLeadMs) }
        #expect(Self.alarms(w, .snoozeEnd).count == 1)
        #expect(w.store.readRingEvents().isEmpty)
    }

    @Test("Snooze intent killed after its write, before stop (alarm still ringing); the user then taps Stop: DISMISSED, nothing rings again")
    func snoozeDiedBeforeStopThenStop() async {
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let nows0 = U.nowAlarms(w).count
        w.kill()
        try? w.store.appendRingEvent(RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze,
                                                  atWallMs: w.time.wallMs()))
        await w.advance(by: 10_000)  // still alerting in the system
        // The user taps Stop on the same alarm: iOS launches a process for the StopIntent.
        w.alarms.setState(now.id, nil)
        w.relaunch(.background)
        await Self.attach(w)
        await w.runtime.ensureLoaded()
        await w.advance(by: 40)
        await A.intent(w, RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .dismiss, atWallMs: w.time.wallMs()))
        await w.advance(by: 10 * 60_000)
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        #expect(U.nowAlarms(w).count == nows0)
        #expect(Self.snoozed(w).isEmpty, "the later Stop wins over the snooze of the same alarm")
        #expect(!w.alarms.all.contains { $0.tripId == "t1" })
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1)
    }

    @Test("Route-back intent killed after writing the launch action, before DISMISS: the restore keeps that launch action (pastM)")
    func routeBackDiedAfterLaunchAction() async {
        let w = World()
        let over = await A.overshootRinging(w)
        guard let over else { Issue.record("no overshoot alarm"); return }
        let tap = w.time.wallMs()
        w.kill()
        try? w.store.appendRingEvent(RingEventRec(tripId: "t1", alarmId: over.id, kind: .now, action: .routeBack, atWallMs: tap))
        w.alarms.setState(over.id, nil)
        // The runtime had written the launch action with the live pastM (a value the snapshot does not hold).
        try? w.store.writeLaunchAction(LaunchActionRec(tripId: "t1", pastM: 4_321, atWallMs: tap,
                                                       atElapsedMs: w.time.elapsedMs(), bootSessionId: w.time.bootSessionId()))
        await w.advance(by: 500)
        w.relaunch(.background)
        await w.runtime.ensureLoaded()
        await w.advance(by: 2_100)
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        let a = await w.runtime.consumeLaunchAction()
        #expect(a?.tripId == "t1" && a?.pastM == 4_321, "not overwritten by the restore")
    }

    @Test("Route-back intent killed before the launch action was written: TTL counts from the tap, also through a later restore")
    func routeBackRestoreTtlFromTap() async {
        for (reopenAfterMs, valid) in [(9 * 60_000, true), (11 * 60_000, false)] as [(Int64, Bool)] {
            let w = World()
            let over = await A.overshootRinging(w)
            guard let over else { Issue.record("no overshoot alarm"); return }
            w.kill()
            try? w.store.appendRingEvent(RingEventRec(tripId: "t1", alarmId: over.id, kind: .now, action: .routeBack,
                                                      atWallMs: w.time.wallMs()))
            w.alarms.setState(over.id, nil)
            await w.advance(by: reopenAfterMs)
            w.relaunch(.active)  // the user opens the app
            await w.runtime.ensureLoaded()
            await w.settle()
            #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
            let a = await w.runtime.consumeLaunchAction()
            #expect((a != nil) == valid, "reopened after \(reopenAfterMs / 60_000) min")
        }
    }

    @Test("Held ring: the StopIntent record reaches the disk before the hold ends, its hand-over after: no \"now\" alarm at all")
    func heldRingStopIntentRace() async {
        let w = World()
        guard let (slot, lo, hi) = await A.heldRing(w) else { return }
        await w.advance(to: lo + 2_500)
        let rec = RingEventRec(tripId: "t1", alarmId: slot.alarmId, kind: slot.kind, action: .dismiss, atWallMs: w.time.wallMs())
        try? w.store.appendRingEvent(rec)  // StopIntentFlow step (1) done …
        await w.advance(to: hi + w.constants.stopIntentGraceMs + 500)  // … the hold ends before step (3)
        #expect(U.nowAlarms(w).isEmpty, "the hold saw the record on disk and dropped the ring")
        await w.runtime.onStopIntent(rec)
        await w.settle()
        await w.advance(by: 60_000)
        #expect(U.nowAlarms(w).isEmpty)
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1)
    }

    @Test("Snooze intent delivered twice for the same alarm: one Snoozed, the until + 30 s slot stays, no AlarmSilenced")
    func duplicateSnoozeIntent() async {
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let rec = RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze, atWallMs: w.time.wallMs())
        await A.intent(w, rec)
        let until = w.seen.entries.last?.view.snoozeUntilMs
        await w.advance(by: 200)
        await A.intent(w, rec)
        #expect(Self.snoozed(w).count == 1)
        #expect(w.seen.entries.last?.view.phase == .snoozed)
        if let u = until {
            #expect(w.alarms.all.contains { $0.kind == .fallback && $0.fireAtWallMs == u + 30_000 && $0.state == .scheduled })
        }
        #expect(!w.journal.all.contains { $0.ev == "snooze_intent" && $0.fields["refused"] == "true" })
    }
}
