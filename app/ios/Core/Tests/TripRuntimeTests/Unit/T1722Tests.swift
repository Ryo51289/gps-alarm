import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T17.2.2 (docs/specs/T17.2.md §5.3): the iOS runtime side of rule P1 (T10.8). AU15: a ring swallowed by `ring_live` is
/// rung when the live ring stops unanswered. AU14: the trailing alarm for a dead app (AM05 branch "AlarmKit stops after D").
@Suite("T1722")
struct T1722Tests {
    typealias U = RuntimeUnitTests

    static func overshootAlarms(_ w: World) -> [SystemAlarmRequest] {
        w.alarms.scheduledRequests().filter { $0.kind == .now && $0.secondary == .routeBack }
    }

    static func overshootEvents(_ w: World) -> Int {
        w.seen.events.filter { if case let .alarm(a) = $0 { return a.reason == .overshoot && a.ringNow }; return false }.count
    }

    // MARK: - AU15 swallowed ring

    /// The first ring rings out (AlarmSilenced: engine ALARMING, ringing = false) while the system still shows a live "now"
    /// alarm of the trip (`N2`, e.g. a "now" confirmed but not reported yet). The trip then overshoots: the engine rings
    /// OVERSHOOT (#18) and the planner swallows it (`ring_live`, one ring per trip). Returns N2's id.
    static func swallowedOvershoot(_ w: World) async throws -> String {
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        let first = try #require(U.nowAlarms(w).first)
        w.alarms.setState(first.id, nil)  // rang out without a StopIntent
        await w.settle()
        await w.advance(by: 3_500)  // goneCheck → AlarmSilenced
        #expect(w.seen.entries.last?.view.alarmRinging == false)
        try await w.alarms.schedule(SystemAlarmRequest(id: "N2", tripId: "t1", kind: .now, generation: 99,
                                                       fireAtWallMs: w.time.wallMs(), title: "x", channel: .alarmKit))
        w.alarms.setState("N2", .alerting)
        await w.settle()
        var km = 0.5
        for _ in 0..<120 where overshootEvents(w) == 0 {
            km -= 0.075
            await w.advance(by: 5_000)
            await w.emit(TestData.fix(kmSouth: km, wall: w.time.wallMs()))
        }
        #expect(overshootEvents(w) == 1)
        #expect(w.journal.all.contains { $0.ev == "ring_live" })
        return "N2"
    }

    @Test("AU15 ring_live swallows OVERSHOOT; the live ring stops unanswered → exactly one ring(OVERSHOOT), no AlarmSilenced")
    func au15() async throws {
        let w = World()
        let live = try await Self.swallowedOvershoot(w)
        #expect(Self.overshootAlarms(w).isEmpty, "swallowed while N2 rings")
        #expect(w.store.currentLedger.swallowedRing == "OVERSHOOT", "kept in the ledger too")
        let ringsBefore = w.alarms.scheduledRequests().count
        w.alarms.setState(live, nil)  // AlarmKit stops it; no StopIntent
        await w.settle()
        await w.advance(by: w.constants.stopIntentGraceMs + 500)
        let over = Self.overshootAlarms(w)
        #expect(over.count == 1)
        #expect(over.first?.title == NativeCopy.alarmTitle(.overshoot, destinationName: "Ga Đông Hà", locale: "vi"))
        #expect(w.store.currentLedger.swallowedRing == nil)
        #expect(Self.overshootEvents(w) == 1, "the engine decided it once; the runtime rang it")
        #expect(w.seen.entries.last?.view.alarmRinging == true, "AlarmSilenced not fed")
        // With its ring guard (R1), as every ring.
        let added = w.alarms.scheduledRequests().dropFirst(ringsBefore)
        #expect(added.contains { $0.kind == .guardSlot && $0.secondary == .routeBack })
        await w.advance(by: 6_000)
        #expect(w.alarms.all.contains { $0.id == over.first?.id && $0.state == .alerting })
        await w.advance(by: 120_000)
        #expect(Self.overshootAlarms(w).count == 1, "never twice")
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("AU15b StopIntent on the live ring instead → no OVERSHOOT ring, trip DISMISSED; Flutter dismiss the same")
    func au15b() async throws {
        let w = World()
        let live = try await Self.swallowedOvershoot(w)
        await T172Tests.intent(w, RingEventRec(tripId: "t1", alarmId: live, kind: .now, action: .dismiss,
                                               atWallMs: w.time.wallMs()))
        await w.advance(by: 60_000)
        #expect(Self.overshootAlarms(w).isEmpty)
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        #expect(w.store.currentLedger.swallowedRing == nil)

        let w2 = World()
        let live2 = try await Self.swallowedOvershoot(w2)
        await w2.runtime.userAction(tripId: "t1", .dismiss)
        await w2.settle()
        w2.alarms.setState(live2, nil)
        await w2.settle()
        await w2.advance(by: 60_000)
        #expect(Self.overshootAlarms(w2).isEmpty)
        #expect(w2.store.finished["t1"]?.endReason == "DISMISSED")
    }

    @Test("AU15c swallowed ring survives the process: restore with the live ring gone rings it instead of AlarmSilenced")
    func au15c() async throws {
        let w = World()
        let live = try await Self.swallowedOvershoot(w)
        w.kill()
        w.alarms.setState(live, nil)  // stops while no process runs
        await w.advance(by: 10_000)
        w.relaunch(.active)
        await w.listen()
        await w.settle()
        #expect(Self.overshootAlarms(w).count == 1)
        #expect(w.store.currentLedger.swallowedRing == nil)
        #expect(w.seen.entries.last?.view.alarmRinging == true)
    }

    // MARK: - AU14 trailing alarm (AM05 branch "AlarmKit stops after D s")

    static let selfStopMs: Int64 = 600_000

    /// TR44 with `akSelfStopMs = D` = the fake's self-stop (osRingMaxS). Stops right after the Overshoot Step.
    static func tr44(_ constants: RuntimeConstants) async throws -> (World, TraceCase, TraceRun) {
        let trace = try RuntimeFixtures.read("coach_gb_phuly_overshoot")
        let c = try #require(trace.cases.first { $0.id == "distance_1000_overshoot_ringing" })
        let w = World(startWall: trace.startMs, constants: constants)
        w.alarms.silenceAfterMs = Int64(try #require(c.osRingMaxS)) * 1000
        await w.listen()
        #expect(await w.runtime.start(meta: RuntimeFixtures.meta(trace, c), destLat: trace.destLat, destLng: trace.destLng)
            == .started)
        await w.settle()
        let run = TraceRun(world: w, trace: trace)
        let seen = w.seen
        await run.run(endT: trace.durationS) { seen.events.contains { $0.fixtureName == "overshoot" } }
        return (w, trace, run)
    }

    static func trailing(_ w: World) -> [SystemAlarmRequest] {
        w.alarms.scheduledRequests().filter { $0.kind == .guardSlot && $0.secondary == .routeBack && $0.title == overshootTitle }
    }

    /// RuntimeFixtures.meta names every fixture destination "Đích thử".
    static let overshootTitle = NativeCopy.alarmTitle(.overshoot, destinationName: "Đích thử", locale: "vi")

    /// Alarms of the trip that started alerting at or after `wall`.
    static func ringsSince(_ w: World, _ wall: Int64) -> Int {
        w.alarms.transitionList.filter { !$0.tripId.isEmpty && $0.wall >= wall }.count
    }

    @Test("AU14 overshoot while ringing → trailing alarm at ring start + D + lead; app alive: one ring after the stop")
    func au14Alive() async throws {
        var k = RuntimeConstants.default
        k.akSelfStopMs = Self.selfStopMs
        let (w, trace, run) = try await Self.tr44(k)
        let firstNow = try #require(U.nowAlarms(w).first)
        let tr = Self.trailing(w)
        #expect(tr.count == 1)
        #expect(tr.first?.fireAtWallMs == firstNow.fireAtWallMs + Self.selfStopMs + k.akNowLeadMs)
        #expect(Self.overshootAlarms(w).isEmpty, "the engine rings only on AlarmSilenced")
        let overWall = w.time.wallMs()
        await run.run(endT: trace.durationS)
        // The first ring stops by itself (D), AlarmSilenced → Alarm(OVERSHOOT) → "now"; the trailing alarm alerts first
        // (D + 5 s < D + 3 s grace + 5 s lead) and cancels that "now" (obligation 4): one ring, OVERSHOOT title + route back.
        #expect(Self.overshootEvents(w) == 1)
        #expect(Self.ringsSince(w, overWall) == 1)
        #expect(w.alarms.doubleRings == 0)
        #expect(Self.trailing(w).count == 1, "scheduled once")
    }

    @Test("AU14b app dead when the first ring stops: the trailing alarm rings, one ring after the overshoot before the app opens")
    func au14Dead() async throws {
        var k = RuntimeConstants.default
        k.akSelfStopMs = Self.selfStopMs
        let (w, _, _) = try await Self.tr44(k)
        let tr = try #require(Self.trailing(w).first)
        let overWall = w.time.wallMs()
        w.kill()
        await w.advance(to: tr.fireAtWallMs - w.startWall + 60_000)
        #expect(Self.ringsSince(w, overWall) == 1)
        #expect(w.alarms.transitionList.last?.id == tr.id)
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("AU14c akSelfStopMs = nil (default until AM05): no trailing alarm")
    func au14Off() async throws {
        let (w, _, _) = try await Self.tr44(.default)
        #expect(Self.trailing(w).isEmpty)
        #expect(!w.journal.all.contains { $0.ev == "trailing" })
    }
}
