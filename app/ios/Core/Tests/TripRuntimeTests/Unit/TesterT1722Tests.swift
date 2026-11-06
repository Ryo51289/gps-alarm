import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Tester T17.2.2 (docs/test-reports/T17.2.2.md): the swallowed ring (§5.3 3b) and the trailing alarm outside AU12/14/15.
/// Virtual time and fakes only.
@Suite("TesterT1722")
struct TesterT1722Tests {
    typealias U = RuntimeUnitTests
    typealias A = T1722Tests

    // MARK: - Ledger

    @Test("Ledger: swallowedRing survives encode/decode; an old ledger without the key decodes as nil; nil is not written")
    func ledgerCodec() throws {
        var l = AlarmLedger.empty
        l.activeTripId = "t1"
        l.swallowedRing = "OVERSHOOT"
        let data = try JSONEncoder().encode(l)
        #expect(String(decoding: data, as: UTF8.self).contains("\"swallowedRing\":\"OVERSHOOT\""))
        let back = try JSONDecoder().decode(AlarmLedger.self, from: data)
        #expect(back == l && back.swallowedRing == "OVERSHOOT")
        l.swallowedRing = nil
        let plain = try JSONEncoder().encode(l)
        #expect(!String(decoding: plain, as: UTF8.self).contains("swallowedRing"))
        #expect(try JSONDecoder().decode(AlarmLedger.self, from: plain).swallowedRing == nil)
    }

    // MARK: - Where the swallowed ring is rung or dropped

    @Test("Refused lock-screen snooze (T17.2 record, no rescue) on the live ring while OVERSHOOT is swallowed → OVERSHOOT rings, not AlarmSilenced")
    func refusedSnoozeRingsSwallowed() async throws {
        let w = World()
        let live = try await A.swallowedOvershoot(w)
        #expect(A.overshootAlarms(w).isEmpty)
        await T172Tests.intent(w, RingEventRec(tripId: "t1", alarmId: live, kind: .now, action: .snooze,
                                               atWallMs: w.time.wallMs()))
        await w.advance(by: 1_000)
        #expect(w.journal.all.contains { $0.ev == "snooze_intent" && $0.fields["refused"] == "true" })
        // Without it: AlarmSilenced with lastReason == OVERSHOOT → T10.8 does not ring → nothing rings any more.
        #expect(A.overshootAlarms(w).count == 1, "the swallowed OVERSHOOT is rung")
        #expect(w.store.currentLedger.swallowedRing == nil)
        await w.advance(by: 120_000)
        #expect(A.overshootAlarms(w).count == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("Flutter dismiss on the live ring clears the swallowed ring; nothing rings when the live ring then goes")
    func flutterDismissClears() async throws {
        let w = World()
        let live = try await A.swallowedOvershoot(w)
        await w.runtime.userAction(tripId: "t1", .dismiss)
        await w.settle()
        #expect(w.store.currentLedger.swallowedRing == nil)
        w.alarms.setState(live, nil)
        await w.settle()
        await w.advance(by: 10_000)
        #expect(A.overshootAlarms(w).isEmpty, "no OVERSHOOT ring after the answer")
    }

    @Test("Swallowed SNOOZE_END in ALARMING (an old now still rings), then an accepted snooze: the swallowed ring is dropped at once")
    func acceptedSnoozeClears() async throws {
        let w = World()
        #expect(await U.started(w, meta: TestData.meta(params: "{\"maxSnoozes\":2}")) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        let until = try #require(w.seen.entries.last?.view.snoozeUntilMs)
        // An earlier "now" still rings in the system (as AU15's N2) when the snooze ends: SNOOZE_END is swallowed.
        try await w.alarms.schedule(SystemAlarmRequest(id: "N2", tripId: "t1", kind: .now, generation: 99,
                                                       fireAtWallMs: w.time.wallMs(), title: "x", channel: .alarmKit))
        w.alarms.setState("N2", .alerting)
        await w.settle()
        await w.advance(to: until - w.startWall + 1_000)
        try #require(w.store.currentLedger.swallowedRing == "SNOOZE_END", "precondition: SNOOZE_END swallowed")
        #expect(w.seen.entries.last?.view.phase == .alarming)
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        #expect(w.seen.entries.last?.view.phase == .snoozed, "second snooze accepted")
        #expect(w.store.currentLedger.swallowedRing == nil, "answered: the swallowed ring is dropped (stopRinging)")
    }

    @Test("Flutter snooze while OVERSHOT (engine refuses): the swallowed ring stays and rings when the live ring goes unanswered")
    func flutterSnoozeRefusedKeeps() async throws {
        let w = World()
        let live = try await A.swallowedOvershoot(w)
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        #expect(w.seen.entries.last?.view.phase == .overshot, "no snooze from OVERSHOT")
        #expect(w.store.currentLedger.swallowedRing == "OVERSHOOT")
        w.alarms.setState(live, nil)
        await w.settle()
        await w.advance(by: w.constants.stopIntentGraceMs + 500)
        #expect(A.overshootAlarms(w).count == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("A stale swallowedRing in the ledger at start (crash) is dropped: the new trip's fallback slot rings unanswered → AlarmSilenced, no OVERSHOOT ring")
    func staleLedgerAtStart() async throws {
        let w = World()
        var l = AlarmLedger.empty
        l.swallowedRing = "OVERSHOOT"
        try w.store.writeLedger(l)
        #expect(await U.started(w) == .started)
        #expect(w.store.currentLedger.swallowedRing == nil)
        await U.drive(w, km: 30, max: 6) { false }
        let slot = try #require(w.store.currentLedger.current)
        w.alarms.silenceAfterMs = 10_000
        w.suspended = true
        await w.advance(to: slot.targetAtWallMs - w.startWall + 1_000)
        w.suspended = false
        await w.advance(by: 30_000)
        #expect(A.overshootAlarms(w).isEmpty, "no OVERSHOOT ring from a stale ledger")
        #expect(w.seen.entries.last?.view.alarmRinging == false, "the slot went unanswered: AlarmSilenced")
    }

    // MARK: - ring_live through a trace (review nit 1–1)

    /// TR44 (`distance_1000_overshoot_ringing`, the fake stops a ring after osRingMaxS). An AlarmKit glitch: one update
    /// without the ringing first "now" (it keeps ringing) → goneCheck → AlarmSilenced while it rings. `recover`: the next
    /// update lists it again. The trip then overshoots: Alarm(OVERSHOOT) is swallowed (ring_live).
    static func ringLiveRun(recover: Bool) async throws -> (World, SystemAlarmRequest, Int64) {
        let trace = try RuntimeFixtures.read("coach_gb_phuly_overshoot")
        let c = try #require(trace.cases.first { $0.id == "distance_1000_overshoot_ringing" })
        let w = World(startWall: trace.startMs)
        let osRingMs = Int64(try #require(c.osRingMaxS)) * 1000
        w.alarms.silenceAfterMs = osRingMs
        await w.listen()
        #expect(await w.runtime.start(meta: RuntimeFixtures.meta(trace, c), destLat: trace.destLat, destLng: trace.destLng)
            == .started)
        await w.settle()
        let run = TraceRun(world: w, trace: trace)
        await run.run(endT: trace.durationS, stopAtFirstAlarm: true)
        await w.advance(by: 6_000)
        let first = try #require(U.nowAlarms(w).first)
        #expect(w.alarms.alarmKitAll.first { $0.id == first.id }?.state == .alerting)
        await w.runtime.onSystemAlarms(w.alarms.alarmKitAll.filter { $0.id != first.id }, channel: .alarmKit)
        await w.runtime.drain()
        await w.advance(by: w.constants.stopIntentGraceMs + 500)
        #expect(w.seen.entries.last?.view.alarmRinging == false, "the engine believes the ring stopped")
        #expect(w.alarms.alarmKitAll.first { $0.id == first.id }?.state == .alerting, "it still rings")
        if recover {
            await w.runtime.onSystemAlarms(w.alarms.alarmKitAll, channel: .alarmKit)
            await w.runtime.drain()
        }
        await run.run(endT: trace.durationS)
        await w.advance(to: first.fireAtWallMs + osRingMs + 60_000 - w.startWall)
        #expect(w.journal.all.contains { $0.ev == "ring_live" }, "ring_live reached")
        #expect(w.journal.all.contains { $0.ev == "ring_swallowed" && $0.fields["op"] == "set" && $0.fields["reason"] == "OVERSHOOT" })
        return (w, first, osRingMs)
    }

    @Test("Trace TR44 + AlarmKit glitch that recovers: the swallowed OVERSHOOT rings once when the first ring stops by itself; 1–1 holds with ring_swallowed{op:ring} (review nit)")
    func ringLiveThroughTrace() async throws {
        let (w, first, osRingMs) = try await Self.ringLiveRun(recover: true)
        let lines = w.journal.all
        let live = lines.filter { $0.ev == "ring_live" }.count
        let swallowedRung = lines.filter { $0.ev == "ring_swallowed" && $0.fields["op"] == "ring" }.count
        #expect(swallowedRung == 1)
        let over = A.overshootAlarms(w)
        #expect(over.count == 1)
        if let o = over.first {
            let stopAt = first.fireAtWallMs + osRingMs
            #expect(o.fireAtWallMs >= stopAt && o.fireAtWallMs <= stopAt + w.constants.stopIntentGraceMs + 2 * w.constants.akNowLeadMs + 1_000,
                    "OVERSHOOT ring \(o.fireAtWallMs - stopAt) ms after the first ring stopped")
        }
        #expect(w.alarms.doubleRings == 0)
        // 1–1 with the review nit: a swallowed ring rung later is one schedule(.now) more than its Alarm(ringNow) event.
        let ringNowEvents = w.seen.events.filter { if case let .alarm(a) = $0 { return a.ringNow }; return false }.count
        let nowSchedules = U.nowAlarms(w).count
        let fed = lines.filter { $0.ev == "fb_fired" && $0.fields["src"] == "planner" }.count
        #expect(ringNowEvents == nowSchedules - swallowedRung + fed + live,
                "ringNow \(ringNowEvents) vs now \(nowSchedules) − swallowed \(swallowedRung) + fed \(fed) + live \(live)")
        #expect(ringNowEvents != nowSchedules + fed + live, "the unadjusted count is off by the swallowed ring (the nit)")
    }

    /// FINDING #1 (docs/test-reports/T17.2.2.md): when the glitch does not recover, the interpreter's previous list never
    /// shows the live ring again, so its real stop is not seen (no checkGone) and the swallowed OVERSHOOT never rings.
    /// Fixed in T17.2.2 round 2: the swallow poll (`RuntimeConstants.swallowPollMs`) reads `list()` itself.
    @Test("Trace TR44 + AlarmKit glitch that does not recover: the swallowed OVERSHOOT still rings when the first ring stops")
    func ringLiveGlitchNoRecover() async throws {
        let (w, _, _) = try await Self.ringLiveRun(recover: false)
        #expect(A.overshootAlarms(w).count == 1, "the overshoot rings")
        #expect(w.alarms.doubleRings == 0)
    }
}
