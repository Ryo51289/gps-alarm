import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Spec "Sửa spec sau review vòng 1": R1 (IU47), R2 (IU29 table), review #2 (AlarmRefRegistry).
@Suite("RuntimeRound2Pure")
struct R2PureTests {
    static func slot(_ id: String, _ at: Int64, kind: SystemAlarmKind = .guardSlot) -> AlarmSlotRec {
        AlarmSlotRec(alarmId: id, kind: kind, generation: 1, targetAtMs: at, targetAtWallMs: at, setAtWallMs: 0, channel: .alarmKit)
    }

    static func info(_ id: String, _ s: SystemAlarmState, kind: SystemAlarmKind = .guardSlot, at: Int64 = 0) -> SystemAlarmInfo {
        SystemAlarmInfo(id: id, tripId: "t1", kind: kind, generation: 1, state: s, fireAtWallMs: at, channel: .alarmKit)
    }

    @Test("IU47 liveSlot + guard condition: (a) live in window → no guard; (b) after window, (c) past/dead, (d) list nil → guard; (e) dead current, live stale in window → no guard")
    func iu47() {
        let now: Int64 = 1_000_000, guardAt = now + 30_000
        func needs(_ l: AlarmLedger, _ list: [SystemAlarmInfo]?) -> Bool {
            EffectPlanner.needsGuard(live: EffectPlanner.liveSlot(l, list: list), nowWallMs: now, guardAtWallMs: guardAt)
        }
        var a = AlarmLedger.empty
        a.current = Self.slot("A", now + 20_000)
        #expect(!needs(a, [Self.info("A", .scheduled)]))
        var b = AlarmLedger.empty
        b.current = Self.slot("B", now + 3_600_000)
        #expect(needs(b, [Self.info("B", .scheduled)]))
        var c = AlarmLedger.empty
        c.current = Self.slot("C", now - 5_000)
        #expect(needs(c, []))
        #expect(EffectPlanner.liveSlot(c, list: []) == nil)
        #expect(needs(a, nil))
        var e = AlarmLedger.empty
        e.current = Self.slot("D", now - 1)
        e.stale = Self.slot("S", now + 10_000)
        #expect(!needs(e, [Self.info("S", .scheduled), Self.info("D", .alerting)]))
        #expect(EffectPlanner.liveSlot(e, list: [Self.info("S", .scheduled)])?.alarmId == "S")
    }

    @Test("IU29 RestoreRingPolicy.decide table (i)–(viii)")
    func iu29() {
        let now: Int64 = 10_000_000, lag: Int64 = 30_000, grace: Int64 = 20_000
        func d(_ l: AlarmLedger, _ list: [SystemAlarmInfo]?, info: RestoreInfo = RestoreInfo(status: .pending),
               alarmWall: Int64) -> RestoreRingDecision {
            RestoreRingPolicy.decide(info: info, ledger: l, list: list, nowWallMs: now, lagMs: lag, graceMs: grace,
                                     alarmWallMs: alarmWall)
        }
        func nowRec(_ fire: Int64, confirmed: Bool) -> NowRingRec {
            NowRingRec(alarmId: "N", generation: 2, fireAtWallMs: fire, reason: "DISTANCE", confirmed: confirmed, seenAlerting: false,
                       channel: .alarmKit)
        }
        // (i) RANG
        #expect(d(.empty, [], info: RestoreInfo(status: .rang, firedAtMs: 1), alarmWall: now) == .silenced(atWallMs: now))
        // (ii) now confirmed, still scheduled
        var l2 = AlarmLedger.empty
        l2.now = nowRec(now + 3_000, confirmed: true)
        #expect(d(l2, [Self.info("N", .scheduled, kind: .now)], alarmWall: now + 3_000) == .none)
        // (iii) now confirmed, past fireAt + grace, not listed
        var l3 = AlarmLedger.empty
        l3.now = nowRec(now - 60_000, confirmed: true)
        #expect(d(l3, [], alarmWall: now - 60_000) == .silenced(atWallMs: now - 60_000))
        // (iv) now unconfirmed + guard still scheduled
        var l4 = AlarmLedger.empty
        l4.now = nowRec(now - 5_000, confirmed: false)
        l4.current = Self.slot("G", now + 20_000)
        #expect(d(l4, [Self.info("G", .scheduled)], alarmWall: now - 5_000) == .none)
        // (v) now unconfirmed + guard past its time, not listed
        var l5 = AlarmLedger.empty
        l5.now = nowRec(now - 100_000, confirmed: false)
        l5.current = Self.slot("G", now - 70_000)
        #expect(d(l5, [], alarmWall: now - 100_000) == .silenced(atWallMs: now - 70_000))
        // (vi) now unconfirmed + guard lost before its time
        var l6 = AlarmLedger.empty
        l6.now = nowRec(now - 5_000, confirmed: false)
        l6.current = Self.slot("G", now + 20_000)
        #expect(d(l6, [], alarmWall: now - 5_000) == .ring)
        // (vii) no now, no near slot (far fallback only)
        var l7 = AlarmLedger.empty
        l7.current = Self.slot("F", now + 3_600_000, kind: .fallback)
        #expect(d(l7, [Self.info("F", .scheduled, kind: .fallback)], alarmWall: now) == .ring)
        // (viii) list nil, now confirmed, not yet due
        var l8 = AlarmLedger.empty
        l8.now = nowRec(now + 3_000, confirmed: true)
        #expect(d(l8, nil, info: RestoreInfo(status: .unknown), alarmWall: now + 3_000) == .none)
    }

    final class Clock: @unchecked Sendable {
        var t: Int64 = 1_000_000
    }

    @Test("review #2: AlarmRefRegistry.retain never drops a pending or fresh ref, drops old missing ones, persists")
    func registry() throws {
        let clock = Clock()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("napstop-refs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = AlarmRefRegistry(url: url, now: { clock.t }, graceMs: 120_000)
        let ref = AlarmRefRegistry.Ref(tripId: "t1", kind: .now, generation: 3, fireAtWallMs: 5)
        r.beginSchedule("N", ref)
        r.retain([])  // an alarmUpdates snapshot taken before N was added, handled after put
        #expect(r.get("N")?.tripId == "t1")
        clock.t += 500_000
        r.retain([])  // still pending (schedule has not returned): kept
        #expect(r.get("N") != nil)
        r.endSchedule("N", ok: true)
        r.retain([])  // fresh after endSchedule: kept
        #expect(r.get("N") != nil)
        clock.t += 121_000
        r.retain(["N"])  // listed: kept
        #expect(r.get("N") != nil)
        r.beginSchedule("X", ref)
        r.endSchedule("X", ok: false)
        #expect(r.get("X") == nil)
        let reopened = AlarmRefRegistry(url: url, now: { clock.t })
        #expect(reopened.get("N")?.generation == 3)
        reopened.retain([])  // old and missing: dropped
        #expect(reopened.get("N") == nil)
    }
}

@Suite("RuntimeRound3Pure")
struct R3PureTests {
    @Test("IU49 (V2-1) no guard while an alarm of the trip already rings; a guard when nothing rings")
    func iu49() {
        let alarm = PureUnitTests.alarmEv
        func plan(_ facts: RingFacts) -> [Effect] {
            EffectPlanner.plan(PureUnitTests.planInput(PureUnitTests.step(events: [alarm]), current: nil, facts: facts))
        }
        let isGuard: (Effect) -> Bool = { if case .armRingGuard = $0 { return true }; return false }
        let isRing: (Effect) -> Bool = { if case .ringNow = $0 { return true }; return false }
        let liveNow = RingFacts(ringingNow: true, ringingKind: .now, ringStartedAtWallMs: 995_000, ringingAlarmId: "N")
        #expect(!plan(liveNow).contains(where: isGuard) && !plan(liveNow).contains(where: isRing))
        let fallback = RingFacts(ringingNow: true, ringingKind: .fallback, ringStartedAtWallMs: 995_000, ringingAlarmId: "F")
        #expect(!plan(fallback).contains(where: isGuard))
        let nothing = plan(.none)
        let g = nothing.firstIndex(where: isGuard), r = nothing.firstIndex(where: isRing)
        #expect(g != nil && r != nil && g! < r!)
    }
}

@Suite("RuntimeRound4")
struct R4Tests {
    @Test("StopIntentFlow: write → stop → hand over, in that order; a failed write still hands the record over")
    func stopIntentOrder() async {
        let rec = RingEventRec(tripId: "t1", alarmId: "A", kind: .fallback, action: .dismiss, atWallMs: 1)
        let log = OpLog()
        let ok = await StopIntentFlow.perform(rec, write: { _ in log.add("write") }, stopSystemAlarm: { log.add("stop") },
                                              handOver: { _ in log.add("handOver") })
        #expect(ok)
        #expect(log.ops == ["write", "stop", "handOver"])
        log.clear()
        let failed = await StopIntentFlow.perform(rec, write: { _ in log.add("write"); throw ScheduleFailure() },
                                                  stopSystemAlarm: { log.add("stop") }, handOver: { _ in log.add("handOver") })
        #expect(!failed)
        #expect(log.ops == ["write", "stop", "handOver"])
    }

    @Test("StopIntentFlow through the runtime: the ring event is on disk before the runtime handles it")
    func stopIntentDiskBeforeRuntime() async {
        let w = World()
        let slot = await RuntimeUnitTests.diedAndStopped(w)
        await w.advance(by: 40)
        let rec = RingEventRec(tripId: "t1", alarmId: slot.alarmId, kind: slot.kind, action: .dismiss, atWallMs: w.time.wallMs())
        let onDiskAtHandOver = Counter()
        let store = w.store, rt = w.runtime!
        await StopIntentFlow.perform(rec, write: { try store.appendRingEvent($0) }, stopSystemAlarm: {}, handOver: { r in
            if store.readRingEvents().contains(r) { onDiskAtHandOver.inc() }
            await rt.onStopIntent(r)
        })
        await w.settle()
        #expect(onDiskAtHandOver.value == 1)
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
    }
}
