import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T17.2.1 (docs/specs/T17.2.1.md): the snooze intent schedules a rescue alarm before the ring is stopped; the runtime takes
/// it as the snooze slot; `stopRinging(.snoozed)` runs after the slot exists; restore and reconcile rules (SU01–SU09).
@Suite("T1721")
struct T1721Tests {
    typealias U = RuntimeUnitTests
    typealias A = T172Tests

    // MARK: - Helpers

    /// A hand-over that waits until `open()` (SU01 "treo").
    final class Gate: Locked, @unchecked Sendable {
        private var waiter: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let now: Bool = locked {
                    if opened { return true }
                    waiter = c
                    return false
                }
                if now { c.resume() }
            }
        }
        func open() {
            let c: CheckedContinuation<Void, Never>? = locked { opened = true; let w = waiter; waiter = nil; return w }
            c?.resume()
        }
    }

    final class Slept: Locked, @unchecked Sendable {
        private var ms: [Int64] = []
        func add(_ v: Int64) { locked { ms.append(v) } }
        var all: [Int64] { locked { ms } }
    }

    struct WriteFailure: Error {}

    /// A budget timer that never fires before the hand-over in runtime tests (cancelled when the hand-over answers).
    static let longSleep: @Sendable (Int64) async -> Void = { _ in try? await Task.sleep(nanoseconds: 60_000_000_000) }

    struct Tap {
        let result: SnoozeIntentFlow.Result
        let rec: RingEventRec
        let rescue: SystemAlarmRequest
    }

    /// The snooze intent of T17.2.1 §2 with the world's fakes. `params` nil = what the (current) process knows (§2.1).
    static func snoozeIntent(_ w: World, alarmId: String, kind: SystemAlarmKind = .now, params: SnoozeRescueParams? = nil,
                             scheduleFails: Bool = false, order: OpLog? = nil) async -> Tap {
        let p = params ?? w.runtime.snoozeRescueParams(tripId: "t1")
        let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: alarmId, kind: kind, tapWallMs: w.time.wallMs(),
                                                     rescueId: UUID().uuidString, params: p, locale: "vi")
        let result = await SnoozeIntentFlow.perform(
            rec, rescue: rescue, budgetMs: w.constants.snoozeHandoverBudgetMs,
            write: { r in order?.add("write"); try w.store.appendRingEvent(r) },
            schedule: { r in
                order?.add("schedule")
                if scheduleFails { throw ScheduleFailure() }
                try await w.alarms.schedule(r)
            },
            handOver: { r in
                order?.add("handOver")
                return await w.runtime.onSnoozeIntent(r)
            },
            stopSystemAlarm: { order?.add("stop"); w.alarms.setState(alarmId, nil) },
            journal: w.journal, sleep: longSleep)
        await w.settle()
        return Tap(result: result, rec: rec, rescue: rescue)
    }

    /// ALARMING with the "now" alarm alerting; returns its request.
    static func ringingNow(_ w: World, meta: TripMeta = TestData.meta()) async -> SystemAlarmRequest? {
        #expect(await U.started(w, meta: meta) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        let now = U.nowAlarms(w).first
        if let now { #expect(w.alarms.all.first { $0.id == now.id }?.state == .alerting) }
        return now
    }

    static func attach(_ w: World) async {
        _ = await w.runtime.addListenerWithoutRestoreWait { _, view, choice, events in
            w.seen.add(.init(view: view, choice: choice, events: events))
        }
    }

    static func alarmEvents(_ w: World, _ reason: AlarmReason) -> [TripEvent.Alarm] {
        w.seen.events.compactMap { if case let .alarm(a) = $0, a.reason == reason { return a }; return nil }
    }

    final class Flags: Locked, @unchecked Sendable {
        private var v: [Bool] = []
        func add(_ b: Bool) { locked { v.append(b) } }
        var values: [Bool] { locked { v } }
    }

    /// For every runtime slot (generation ≥ 1) scheduled from now on: was a rescue alarm (generation 0) in the system then?
    static func rescueProbe(_ w: World) -> Flags {
        let f = Flags()
        let alarms = w.alarms
        alarms.locked { alarms.onSchedule = { r in
            if r.kind != .now && r.generation >= 1 { f.add(alarms.all.contains { $0.generation == 0 && $0.state == .scheduled }) }
        } }
        return f
    }

    /// Fallback/guard slots scheduled after the request index `from`.
    static func slotSchedules(_ w: World, from: Int) -> [SystemAlarmRequest] {
        Array(w.alarms.scheduledRequests().dropFirst(from)).filter { $0.kind != .now }
    }

    // MARK: - SU01 pure flow

    @Test("SU01 SnoozeIntentFlow: write → schedule → handOver → stop; stop rule for schedule failure, refused, timeout")
    func su01() async throws {
        let params = SnoozeRescueParams(snoozeS: 60, fallbackLagS: 30, soundFile: "alarm_bell.wav", destinationName: "Ga X")
        let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: "A", kind: .now, tapWallMs: 1_000_000,
                                                     rescueId: "R", params: params, locale: "vi")
        #expect(rec.action == .snooze && rec.rescueAlarmId == "R" && rec.rescueAtWallMs == 1_090_000 && rec.atWallMs == 1_000_000)
        #expect(rescue.id == "R" && rescue.kind == .fallback && rescue.generation == RuntimeConstants.rescueGeneration)
        #expect(rescue.generation == 0 && rescue.fireAtWallMs == 1_090_000 && rescue.secondary == nil)
        #expect(rescue.soundFile == "alarm_bell.wav" && rescue.channel == .alarmKit)
        #expect(rescue.title == NativeCopy.alarmTitle(.snoozeEnd, destinationName: "Ga X", locale: "vi"))
        #expect(SnoozeRescueParams.defaults.snoozeS == 60 && SnoozeRescueParams.defaults.fallbackLagS == 30)
        #expect(SnoozeRescueParams.defaults.soundFile == nil)
        #expect(RuntimeConstants.default.snoozeHandoverBudgetMs == 3_000 && RuntimeConstants.default.rescueMatchMs == 2_000)

        func run(writeFails: Bool = false, scheduleFails: Bool = false, outcome: SnoozeHandOverOutcome? = .snoozed)
            async -> (SnoozeIntentFlow.Result, [String], [Int64]) {
            let order = OpLog()
            let gate = Gate()
            let started = Gate()
            let slept = Slept()
            let r = await SnoozeIntentFlow.perform(
                rec, rescue: rescue, budgetMs: 3_000,
                write: { _ in order.add("write"); if writeFails { throw WriteFailure() } },
                schedule: { _ in order.add("schedule"); if scheduleFails { throw ScheduleFailure() } },
                handOver: { _ in
                    order.add("handOver")
                    guard let outcome else {
                        started.open()
                        await gate.wait()  // hangs ("treo") until the test ends
                        return .snoozed
                    }
                    return outcome
                },
                stopSystemAlarm: { order.add("stop") },
                sleep: { ms in
                    slept.add(ms)
                    // The timer: at once when the hand-over hangs, never otherwise.
                    if outcome != nil { try? await Task.sleep(nanoseconds: 60_000_000_000) } else { await started.wait() }
                })
            gate.open()
            return (r, order.ops, slept.all)
        }
        // All fine.
        let (ok, okOps, _) = await run()
        #expect(okOps == ["write", "schedule", "handOver", "stop"])
        #expect(ok == SnoozeIntentFlow.Result(written: true, rescueScheduled: true, outcome: .snoozed, stopped: true))
        // Rescue failed, runtime snoozed → stop.
        let (b, bOps, _) = await run(scheduleFails: true)
        #expect(bOps == ["write", "schedule", "handOver", "stop"] && b.stopped && !b.rescueScheduled)
        // Rescue failed, runtime silent → no stop.
        let (c, cOps, cSlept) = await run(scheduleFails: true, outcome: nil)
        #expect(c.outcome == .timeout && !c.stopped && !cOps.contains("stop"))
        #expect(cSlept == [3_000])
        // Refused → no stop; the flow never cancels the rescue itself (the runtime cancels or keeps it, review #1).
        let (d, dOps, _) = await run(outcome: .refused)
        #expect(!d.stopped && dOps == ["write", "schedule", "handOver"], "the runtime owns the rescue (review #1)")
        // Hangs → answer after the 3 s budget; stop only with the rescue set.
        let (e, eOps, eSlept) = await run(outcome: nil)
        #expect(e.outcome == .timeout && e.stopped && eOps == ["write", "schedule", "handOver", "stop"])
        #expect(eSlept == [3_000])
        // Unknown trip → stop (the runtime cancelled that alarm).
        let (f, _, _) = await run(scheduleFails: true, outcome: .unknownTrip)
        #expect(f.stopped)
        // Ring event not on disk + timeout: a new process could not tie the rescue to this snooze → keep ringing.
        let (g, _, _) = await run(writeFails: true, outcome: nil)
        #expect(!g.written && g.outcome == .timeout && !g.stopped)
        let (h, _, _) = await run(writeFails: true)
        #expect(!h.written && h.stopped, "the runtime got the record in memory and snoozed")
        // The table of §2 step 4.
        for w in [true, false] {
            for s in [true, false] {
                #expect(SnoozeIntentFlow.shouldStop(written: w, rescueScheduled: s, outcome: .snoozed))
                #expect(SnoozeIntentFlow.shouldStop(written: w, rescueScheduled: s, outcome: .unknownTrip))
                #expect(!SnoozeIntentFlow.shouldStop(written: w, rescueScheduled: s, outcome: .refused))
                #expect(SnoozeIntentFlow.shouldStop(written: w, rescueScheduled: s, outcome: .timeout) == (w && s))
            }
        }
        // Journal: rescue schedule before stop, no ids.
        let j = RecordingJournal()
        _ = await SnoozeIntentFlow.perform(rec, rescue: rescue, budgetMs: 3_000, write: { _ in }, schedule: { _ in },
                                           handOver: { _ in .snoozed }, stopSystemAlarm: {},
                                           journal: j, sleep: Self.longSleep)
        let ak = j.all.filter { $0.ev == "ak" }
        #expect(ak.map { $0.fields["op"] } == ["schedule", "stop"])
        #expect(ak.first?.fields["gen"] == "0" && ak.first?.fields["kind"] == "fallback" && ak.first?.fields["ok"] == "true")
        #expect(!j.all.contains { $0.fields.values.contains("R") || $0.fields.values.contains("A") }, "no ids")
    }

    // MARK: - SU02 planner order

    @Test("SU02 EffectPlanner: Step with Snoozed + FallbackAlarmChanged → scheduleFallback before stopRinging(.snoozed)")
    func su02() throws {
        let meta = TestData.meta()
        var s = try TripEngine.start(config: meta.config(destLat: TestData.destLat, destLng: TestData.destLng),
                                     params: .defaults, nowMs: 1_000).state
        var t: Int64 = 1_000
        var phase: TripPhase = .acquiring
        for _ in 0..<60 where phase != .alarming {
            t += 5_000
            let st = TripEngine.reduce(s, .locationFix(LocationFix(atMs: t, fixAtMs: t, lat: TestData.destLat - 0.5 / 111.2,
                                                                   lng: TestData.destLng, accuracyM: 8, speedMps: 15)))
            s = st.state
            phase = st.view.phase
        }
        #expect(phase == .alarming)
        let step = TripEngine.reduce(s, .userAction(atMs: t + 6_000, action: .snooze))
        #expect(step.events.contains { if case .snoozed = $0 { return true }; return false })
        let fx = EffectPlanner.plan(PlanInput(prevView: nil, step: step, meta: meta, mode: .tracking, facts: .none,
                                              ledger: .empty, timerDueTripMs: nil, params: .defaults, nowWallMs: t + 6_000,
                                              nowTripMs: t + 6_000))
        let sched = fx.firstIndex { if case .scheduleFallback = $0 { return true }; return false }
        let stops = fx.indices.filter { fx[$0] == .stopRinging(.snoozed) }
        #expect(sched != nil && stops.count == 1)
        if let a = sched, let b = stops.first { #expect(a < b) }
        if case let .scheduleFallback(at)? = sched.map({ fx[$0] }) { #expect(at == t + 6_000 + 90_000) }
        // A Step without Snoozed: no stopRinging(.snoozed).
        let plain = EffectPlanner.plan(PlanInput(prevView: nil, step: TripEngine.reduce(s, .tick(atMs: t + 1)), meta: meta,
                                                 mode: .tracking, facts: .none, ledger: .empty, timerDueTripMs: nil,
                                                 params: .defaults, nowWallMs: t + 1, nowTripMs: t + 1))
        #expect(!plain.contains(.stopRinging(.snoozed)))
    }

    // MARK: - Runtime (fakes)

    @Test("SU03 app alive: one schedule (the rescue, gen 0), taken as the slot; SNOOZE_END at until cancels it; one ring after the tap")
    func su03() async {
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let tapWall = w.time.wallMs()
        let n0 = w.alarms.scheduledRequests().count
        let log0 = w.log.ops.count
        let order = OpLog()
        let tap = await Self.snoozeIntent(w, alarmId: now.id, order: order)
        #expect(order.ops == ["write", "schedule", "handOver", "stop"])
        #expect(tap.result == SnoozeIntentFlow.Result(written: true, rescueScheduled: true, outcome: .snoozed, stopped: true))
        let after = Array(w.alarms.scheduledRequests().dropFirst(n0))
        #expect(after.count == 1 && after.first?.id == tap.rescue.id && after.first?.generation == 0)
        #expect(w.store.currentLedger.current?.alarmId == tap.rescue.id)
        #expect(w.journal.all.contains { $0.ev == "rescue" && $0.fields["op"] == "adopt" })
        // The rescue is in place before anything stops the ring (runtime stopRinging or the intent).
        let ops = Array(w.log.ops.dropFirst(log0))
        let sched = ops.firstIndex(of: "schedule.fallback.alarmKit")
        let stop = ops.firstIndex(of: "stop")
        #expect(sched != nil && stop != nil && sched! < stop!)
        let v = w.seen.entries.last!.view
        #expect(v.phase == .snoozed && v.fallbackStatus == .confirmed)
        let until = v.snoozeUntilMs!
        #expect(until + 30_000 == tap.rescue.fireAtWallMs, "same clock in the fakes: exact match")
        #expect(w.store.readRingEvents().isEmpty)
        // Tick at until → SNOOZE_END "now" ring; when it alerts the interpreter cancels the rescue (K4 #3).
        await w.advance(to: until - w.startWall + 7_000)
        #expect(Self.alarmEvents(w, .snoozeEnd).count == 1)
        #expect(w.alarms.cancels.contains(tap.rescue.id))
        #expect(!w.alarms.all.contains { $0.id == tap.rescue.id })
        #expect(Self.slotSchedules(w, from: n0).count == 1, "the runtime never set a slot of its own")
        await w.advance(by: 120_000)
        let rings = w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > tapWall }
        #expect(rings.count == 1, "one ring after the tap, got \(rings.count)")
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("SU04 trip snoozeS = 120, fresh process (intent uses 60): new slot at until + 30 s first, then the rescue is cancelled")
    func su04() async {
        let w = World()
        let meta = TestData.meta(params: "{\"snoozeS\":120}")
        guard let now = await Self.ringingNow(w, meta: meta) else { Issue.record("no now"); return }
        // §2.1: the loaded process knows the trip's values; another trip / a fresh process gets the defaults.
        #expect(w.runtime.snoozeRescueParams(tripId: "t1").snoozeS == 120)
        #expect(w.runtime.snoozeRescueParams(tripId: "t1").soundFile == "alarm_horn.wav")
        #expect(w.runtime.snoozeRescueParams(tripId: "other") == .defaults)
        w.kill()
        await w.advance(by: 20_000)
        w.relaunch(.background)  // the system launches a process for the intent
        await Self.attach(w)
        #expect(w.runtime.snoozeRescueParams(tripId: "t1") == .defaults)
        let n0 = w.alarms.scheduledRequests().count
        let probe = Self.rescueProbe(w)
        let tap = await Self.snoozeIntent(w, alarmId: now.id)
        #expect(tap.rescue.fireAtWallMs == tap.rec.atWallMs + 90_000)
        #expect(tap.result.outcome == .snoozed && tap.result.stopped)
        let v = w.seen.entries.last!.view
        #expect(v.phase == .snoozed)
        let until = v.snoozeUntilMs!
        #expect(until == tap.rec.atWallMs + 120_000)
        let slots = Self.slotSchedules(w, from: n0)
        #expect(slots.count == 2 && slots.first?.id == tap.rescue.id)
        let slot = slots.last!
        #expect(slot.fireAtWallMs == until + 30_000 && slot.generation >= 1)
        #expect(w.store.currentLedger.current?.alarmId == slot.id)
        // Never without an alarm: the rescue was still there when the new slot was scheduled, and is cancelled after.
        #expect(probe.values == [true], "rescue present at the new slot's schedule")
        #expect(w.alarms.cancels.contains(tap.rescue.id))
        #expect(!w.alarms.all.contains { $0.id == tap.rescue.id })
        #expect(w.journal.all.contains { $0.ev == "rescue" && $0.fields["op"] == "replace" })
        await w.advance(to: until - w.startWall + 60_000)
        #expect(Self.alarmEvents(w, .snoozeEnd).count == 1)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > tap.rec.atWallMs }.count == 1)
    }

    /// The intent died after step (2): ring event + rescue alarm, the ring stopped by the system (the O1 case); no process.
    static func diedAfterRescue(_ w: World, now: SystemAlarmRequest) async -> (RingEventRec, SystemAlarmRequest) {
        w.kill()
        let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: now.id, kind: .now, tapWallMs: w.time.wallMs(),
                                                     rescueId: UUID().uuidString, params: .defaults, locale: "vi")
        try? w.store.appendRingEvent(rec)
        try? await w.alarms.schedule(rescue)
        w.alarms.setState(now.id, nil)
        return (rec, rescue)
    }

    @Test("SU05a died after (2), opened in the background 5 min later: the rescue rang → RANG as the snooze end, no ring again")
    func su05a() async {
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let nows0 = U.nowAlarms(w).count
        let (rec, rescue) = await Self.diedAfterRescue(w, now: now)
        let n0 = w.alarms.scheduledRequests().count
        await w.advance(by: 300_000)
        #expect(w.alarms.all.first { $0.id == rescue.id }?.state == .alerting, "the rescue rang without a process")
        w.relaunch(.background)
        await Self.attach(w)
        await w.runtime.ensureLoaded()
        await w.advance(by: 2_100)  // D13 settle
        #expect(A.snoozedEvents(w).count == 1)
        let v = w.seen.entries.last!.view
        #expect(v.phase == .alarming && v.alarmRinging && v.snoozeCount == 1)
        let end = Self.alarmEvents(w, .snoozeEnd)
        #expect(end.count == 1 && end.first?.ringNow == false, "the rescue is the SNOOZE_END ring")
        #expect(U.nowAlarms(w).count == nows0, "no new ring")
        #expect(w.alarms.scheduledRequests().count == n0, "no new alarm at all")
        #expect(w.alarms.all.first { $0.id == rescue.id }?.state == .alerting, "the rescue keeps ringing")
        #expect(w.store.currentLedger.lastFired?.alarmId == rescue.id)
        #expect(w.store.readRingEvents().isEmpty)
        await w.advance(by: 120_000)
        #expect(U.nowAlarms(w).count == nows0)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > rec.atWallMs }.count == 1)
        // The user taps Stop on the rescue: DISMISSED.
        await A.intent(w, RingEventRec(tripId: "t1", alarmId: rescue.id, kind: .fallback, action: .dismiss,
                                       atWallMs: w.time.wallMs()))
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
    }

    @Test("SU05b died after (2), process back while the rescue is scheduled: taken as the slot (restore delay tolerated), rings ≤ 90 s after the tap, once")
    func su05b() async {
        // Opened (foreground) 500 ms after the tap: the engine snoozes from the restore time, 500 ms off → taken.
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let (rec, rescue) = await Self.diedAfterRescue(w, now: now)
        let n0 = w.alarms.scheduledRequests().count
        await w.advance(by: 500)
        w.relaunch(.active)
        await Self.attach(w)
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(A.snoozedEvents(w).count == 1)
        #expect(w.seen.entries.last?.view.phase == .snoozed)
        #expect(w.store.currentLedger.current?.alarmId == rescue.id)
        #expect(w.alarms.scheduledRequests().count == n0, "no new slot")
        #expect(w.alarms.all.first { $0.id == rescue.id }?.state == .scheduled)
        await w.advance(by: 120_000)
        #expect(Self.alarmEvents(w, .snoozeEnd).count == 1)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > rec.atWallMs }.count == 1)
        // Opened in the background 1 s / 40 s after the tap: the restore runs after the D13 settle, so the engine's slot is
        // later than the rescue by the restore delay (review suggestion): the rescue is kept, nothing new is scheduled, and
        // the trip rings once, at the latest 90 s after the tap.
        for openAfterMs in [1_000, 40_000] as [Int64] {
            let w2 = World()
            guard let now2 = await Self.ringingNow(w2) else { Issue.record("no now"); return }
            let (rec2, rescue2) = await Self.diedAfterRescue(w2, now: now2)
            let m0 = w2.alarms.scheduledRequests().count
            await w2.advance(by: openAfterMs)
            w2.relaunch(.background)
            await Self.attach(w2)
            await w2.runtime.ensureLoaded()
            #expect(w2.alarms.all.contains { $0.id == rescue2.id }, "kept by the reconcile (pending snooze event)")
            await w2.advance(by: 2_100)
            #expect(A.snoozedEvents(w2).count == 1, "open after \(openAfterMs)")
            #expect(w2.store.currentLedger.current?.alarmId == rescue2.id, "open after \(openAfterMs)")
            #expect(w2.alarms.scheduledRequests().count == m0, "no new slot, open after \(openAfterMs)")
            await w2.advance(by: 150_000)
            let rings = w2.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > rec2.atWallMs }
            #expect(rings.count == 1, "open after \(openAfterMs): \(rings.count) rings")
            if let first = rings.first { #expect(first.wall - rec2.atWallMs <= 90_000 + w2.constants.akNowLeadMs) }
            #expect(Self.alarmEvents(w2, .snoozeEnd).count == 1)
        }
    }

    @Test("SU06 died after (1) or (2), ring still on, the user taps Stop: DISMISSED wins, rescue cancelled, nothing rings again")
    func su06() async {
        for withRescue in [false, true] {
            let w = World()
            guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
            w.kill()
            let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: now.id, kind: .now, tapWallMs: w.time.wallMs(),
                                                         rescueId: UUID().uuidString, params: .defaults, locale: "vi")
            try? w.store.appendRingEvent(rec)  // (1)
            if withRescue { try? await w.alarms.schedule(rescue) }  // (2)
            await w.advance(by: 10_000)  // still alerting
            #expect(w.alarms.all.first { $0.id == now.id }?.state == .alerting)
            w.alarms.setState(now.id, nil)  // Stop on the lock screen; iOS launches a process for the StopIntent
            w.relaunch(.background)
            await Self.attach(w)
            await w.runtime.ensureLoaded()
            await w.advance(by: 40)
            if withRescue { #expect(w.alarms.all.contains { $0.id == rescue.id }, "kept for the snooze handling") }
            await A.intent(w, RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .dismiss,
                                           atWallMs: w.time.wallMs()))
            #expect(w.store.finished["t1"]?.endReason == "DISMISSED", "rescue \(withRescue)")
            #expect(A.snoozedEvents(w).isEmpty)
            #expect(!w.alarms.all.contains { $0.tripId == "t1" })
            if withRescue { #expect(w.alarms.cancels.contains(rescue.id)) }
            await w.advance(by: 10 * 60_000)
            #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1, "rescue \(withRescue)")
        }
    }

    @Test("SU07 the engine refuses (no snooze left): .refused, rescue cancelled, ring not stopped by the intent, no AlarmSilenced")
    func su07() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        let until = w.seen.entries.last!.view.snoozeUntilMs!
        await w.advance(to: until - w.startWall + 7_000)  // SNOOZE_END "now" alarm alerting
        let end = U.nowAlarms(w).last!
        #expect(w.alarms.all.first { $0.id == end.id }?.state == .alerting)
        let snoozes0 = A.snoozedEvents(w).count
        let order = OpLog()
        let tap = await Self.snoozeIntent(w, alarmId: end.id, order: order)
        #expect(tap.result.outcome == .refused && !tap.result.stopped)
        #expect(!order.ops.contains("stop"))
        #expect(w.alarms.cancels.contains(tap.rescue.id) && !w.alarms.all.contains { $0.id == tap.rescue.id })
        #expect(w.alarms.all.first { $0.id == end.id }?.state == .alerting, "the ring goes on")
        #expect(A.snoozedEvents(w).count == snoozes0)
        let v = w.seen.entries.last!.view
        #expect(v.phase == .alarming && v.alarmRinging, "no AlarmSilenced from the intent")
        #expect(w.journal.all.contains { $0.ev == "snooze_intent" && $0.fields["refused"] == "true" && $0.fields["silenced"] == "false" })
        #expect(w.store.readRingEvents().isEmpty)
        // The user then taps Stop: DISMISSED, nothing else rings.
        await A.intent(w, RingEventRec(tripId: "t1", alarmId: end.id, kind: .now, action: .dismiss, atWallMs: w.time.wallMs()))
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        let rings = w.alarms.transitionList.filter { $0.tripId == "t1" }.count
        await w.advance(by: 5 * 60_000)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == rings)
    }

    @Test("SU07b snooze intent of an unknown trip: .unknownTrip, its alarm and its rescue cancelled, the active trip untouched")
    func su07b() async {
        let w = World()
        #expect(await U.started(w) == .started)
        let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "ghost", alarmId: "G", kind: .now, tapWallMs: w.time.wallMs(),
                                                     rescueId: UUID().uuidString, params: .defaults, locale: "vi")
        try? await w.alarms.schedule(rescue)
        let out = await w.runtime.onSnoozeIntent(rec)
        #expect(out == .unknownTrip)
        #expect(w.alarms.cancels.contains("G") && w.alarms.cancels.contains(rescue.id))
        #expect(await w.runtime.current()?.meta.tripId == "t1")
    }

    /// ALARMING with the SNOOZE_END "now" alarm alerting and no snooze left (SU07 setup); returns that alarm.
    static func refusedSetup(_ w: World) async -> SystemAlarmRequest? {
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        guard let until = w.seen.entries.last?.view.snoozeUntilMs else { return nil }
        await w.advance(to: until - w.startWall + 7_000)
        let end = U.nowAlarms(w).last
        if let end { #expect(w.alarms.all.first { $0.id == end.id }?.state == .alerting) }
        return end
    }

    @Test("SU10 (review #1) refusal after the 3 s budget: the intent stopped the ring, the rescue stays as the slot, rings once")
    func su10() async {
        let w = World()
        guard let end = await Self.refusedSetup(w) else { Issue.record("no SNOOZE_END ring"); return }
        let (rec, rescue) = SnoozeIntentFlow.prepare(tripId: "t1", alarmId: end.id, kind: .now, tapWallMs: w.time.wallMs(),
                                                     rescueId: UUID().uuidString,
                                                     params: w.runtime.snoozeRescueParams(tripId: "t1"), locale: "vi")
        let gate = Gate()
        let done = Gate()
        let box = Slept()  // reused as a box for the late outcome (0 = refused)
        let result = await SnoozeIntentFlow.perform(
            rec, rescue: rescue, budgetMs: 3_000,
            write: { r in try w.store.appendRingEvent(r) },
            schedule: { r in try await w.alarms.schedule(r) },
            handOver: { r in
                await gate.wait()  // the runtime answers after the budget
                let out = await w.runtime.onSnoozeIntent(r)
                box.add(out == .refused ? 0 : 1)
                done.open()
                return out
            },
            stopSystemAlarm: { w.alarms.setState(end.id, nil) },
            sleep: { _ in })
        #expect(result.outcome == .timeout && result.stopped, "budget over, rescue set and written → ring stopped")
        #expect(!w.alarms.all.contains { $0.id == end.id })
        gate.open()
        await done.wait()
        await w.settle()
        #expect(box.all == [0], "the runtime refused")
        #expect(w.alarms.all.first { $0.id == rescue.id }?.state == .scheduled, "the rescue is kept")
        #expect(w.store.currentLedger.current?.alarmId == rescue.id)
        #expect(w.journal.all.contains { $0.ev == "rescue" && $0.fields["op"] == "keep" && $0.fields["cause"] == "refused" })
        #expect(w.alarms.all.filter { $0.tripId == "t1" }.count == 1, "exactly one alarm of the trip")
        let v = w.seen.entries.last!.view
        #expect(v.phase == .alarming && !v.alarmRinging, "the stopped ring is reported silenced")
        #expect(w.store.readRingEvents().isEmpty)
        // The rescue rings ≈ 90 s after the tap, once; nothing else.
        await w.advance(to: rescue.fireAtWallMs - w.startWall + 2_000)
        let rings = w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > rec.atWallMs }
        #expect(rings.count == 1 && rings.first?.id == rescue.id)
        #expect(w.seen.entries.last?.view.alarmRinging == true, "FallbackFired")
        await w.advance(by: 120_000)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > rec.atWallMs }.count == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    @Test("SU11 (review #2) ring events cannot be removed: the rescue taken as the slot is still cancelled by SNOOZE_END, one ring")
    func su11() async {
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        w.store.failRemoveRingEvents = true
        let tap = await Self.snoozeIntent(w, alarmId: now.id)
        #expect(tap.result.outcome == .snoozed)
        #expect(w.store.currentLedger.current?.alarmId == tap.rescue.id)
        #expect(w.store.readRingEvents().contains { $0.rescueAlarmId == tap.rescue.id }, "the event stayed on disk")
        let until = w.seen.entries.last!.view.snoozeUntilMs!
        await w.advance(to: until - w.startWall + 7_000)
        #expect(Self.alarmEvents(w, .snoozeEnd).count == 1)
        #expect(w.alarms.cancels.contains(tap.rescue.id), "K4 #3 cancels the rescue slot")
        await w.advance(by: 120_000)
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" && $0.wall > tap.rec.atWallMs }.count == 1)
        #expect(w.alarms.doubleRings == 0)
    }

    // MARK: - SU08 reconcile / interpreter (pure)

    @Test("SU08 LedgerReconciler: a gen-0 alarm is never adopted; cancelled unless a pending snooze event names it; ended trip → cancelled")
    func su08() {
        func info(_ id: String, gen: Int64, trip: String = "t1", state: SystemAlarmState = .scheduled,
                  kind: SystemAlarmKind = .fallback) -> SystemAlarmInfo {
            SystemAlarmInfo(id: id, tripId: trip, kind: kind, generation: gen, state: state, fireAtWallMs: 5_000, channel: .alarmKit)
        }
        var l = AlarmLedger.empty
        l.activeTripId = "t1"
        // Only the rescue: not adopted, cancelled (no snooze event).
        let r1 = LedgerReconciler.reconcile(l, list: [info("R", gen: 0)], activeTripId: "t1", nowWallMs: 1_000, toTrip: { $0 })
        #expect(r1.ledger.current == nil)
        #expect(r1.actions == [.cancel(id: "R", channel: .alarmKit)])
        // Named by a pending snooze event: kept, still not adopted.
        let r2 = LedgerReconciler.reconcile(l, list: [info("R", gen: 0)], activeTripId: "t1", nowWallMs: 1_000,
                                            protectedIds: ["R"], toTrip: { $0 })
        #expect(r2.ledger.current == nil && r2.actions.isEmpty)
        // With a runtime slot: that one is adopted (R1 of T17), the rescue cancelled.
        let r3 = LedgerReconciler.reconcile(l, list: [info("R", gen: 0), info("S", gen: 2)], activeTripId: "t1",
                                            nowWallMs: 1_000, toTrip: { $0 })
        #expect(r3.ledger.current?.alarmId == "S" && r3.ledger.nextGeneration == 3)
        #expect(r3.actions == [.cancel(id: "R", channel: .alarmKit)])
        // Taken earlier as the slot (ledger.current): kept.
        var l4 = l
        l4.current = AlarmSlotRec(alarmId: "R", kind: .fallback, generation: 7, targetAtMs: 5_000, targetAtWallMs: 5_000,
                                  setAtWallMs: 1, channel: .alarmKit)
        let r4 = LedgerReconciler.reconcile(l4, list: [info("R", gen: 0)], activeTripId: "t1", nowWallMs: 1_000, toTrip: { $0 })
        #expect(r4.ledger.current?.alarmId == "R" && r4.actions.isEmpty)
        // Trip ended: cancelled even when named.
        var l5 = AlarmLedger.empty
        l5.markEnded("t1", max: 8)
        let r5 = LedgerReconciler.reconcile(l5, list: [info("R", gen: 0)], activeTripId: nil, nowWallMs: 1_000,
                                            protectedIds: ["R"], toTrip: { $0 })
        #expect(r5.actions == [.cancel(id: "R", channel: .alarmKit)])
        // Interpreter K4 #3: the "now" alarm starts alerting → scheduled slots cancelled, a pending rescue left alone.
        let nowS = info("N", gen: 3, state: .scheduled, kind: .now)
        let nowA = info("N", gen: 3, state: .alerting, kind: .now)
        let a1 = AlarmUpdateInterpreter.interpret(tripId: "t1", prev: [nowS, info("R", gen: 0)], cur: [nowA, info("R", gen: 0)],
                                                  ledger: l, expectedStops: [], nowWallMs: 5_000, protectedIds: ["R"])
        #expect(a1 == [.nowSeenAlerting(id: "N")])
        let a2 = AlarmUpdateInterpreter.interpret(tripId: "t1", prev: [nowS, info("R", gen: 0)], cur: [nowA, info("R", gen: 0)],
                                                  ledger: l, expectedStops: [], nowWallMs: 5_000)
        #expect(a2 == [.nowSeenAlerting(id: "N"), .cancel(id: "R", channel: .alarmKit)])
    }

    @Test("SU08b runtime: a stray gen-0 alarm at restore without a snooze event is cancelled, never taken as the slot")
    func su08b() async throws {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.drive(w, km: 30, max: 3) { false }
        let slot = w.store.currentLedger.current!
        try await w.alarms.schedule(SystemAlarmRequest(id: "STRAY", tripId: "t1", kind: .fallback, generation: 0,
                                                       fireAtWallMs: w.time.wallMs() + 60_000, title: "x", channel: .alarmKit))
        w.newProcess()
        w.app.state = .active
        await w.runtime.ensureLoaded()
        await w.settle()
        #expect(w.alarms.cancels.contains("STRAY"))
        #expect(w.store.currentLedger.current?.alarmId == slot.alarmId)
    }

    // MARK: - SU09 record format

    @Test("SU09 RingEventRec: a T17.2 record decodes with no rescue; rescue keys written only when set; old flow unchanged")
    func su09() async throws {
        let old = #"{"action":"snooze","alarmId":"A","atWallMs":5,"kind":"now","tripId":"t1"}"#
        let r = try LedgerCodec.decode(RingEventRec.self, Data(old.utf8))
        #expect(r.rescueAlarmId == nil && r.rescueAtWallMs == nil && r.rescue == nil && r.action == .snooze)
        #expect(String(decoding: try LedgerCodec.encode(r), as: UTF8.self) == old)
        let list = #"[{"action":"dismiss","alarmId":"B","atWallMs":7,"kind":"fallback","tripId":"t1"}]"#
        #expect(try LedgerCodec.decode([RingEventRec].self, Data(list.utf8)).first?.rescue == nil)
        let n = RingEventRec(tripId: "t1", alarmId: "A", kind: .now, action: .snooze, atWallMs: 5, rescueAlarmId: "R",
                             rescueAtWallMs: 90_005)
        let s = String(decoding: try LedgerCodec.encode(n), as: UTF8.self)
        #expect(s.contains(#""rescueAlarmId":"R""#) && s.contains(#""rescueAtWallMs":90005"#))
        #expect(try LedgerCodec.decode(RingEventRec.self, Data(s.utf8)) == n)
        #expect(n.rescue?.id == "R" && n.rescue?.atWallMs == 90_005)
        // A dismiss never carries a rescue.
        let d = RingEventRec(tripId: "t1", alarmId: "A", kind: .now, action: .dismiss, atWallMs: 5, rescueAlarmId: "R",
                             rescueAtWallMs: 1)
        #expect(d.rescue == nil)
        // T17.2 record handed over (no rescue): snoozed, the runtime sets its own slot at until + 30 s.
        let w = World()
        guard let now = await Self.ringingNow(w) else { Issue.record("no now"); return }
        let n0 = w.alarms.scheduledRequests().count
        let out = await w.runtime.onSnoozeIntent(RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze,
                                                              atWallMs: w.time.wallMs()))
        await w.settle()
        #expect(out == .snoozed)
        let until = w.seen.entries.last!.view.snoozeUntilMs!
        let slots = Self.slotSchedules(w, from: n0)
        #expect(slots.count == 1 && slots.first?.fireAtWallMs == until + 30_000 && slots.first?.generation ?? 0 >= 1)
        #expect(!w.journal.all.contains { $0.ev == "rescue" })
    }
}
