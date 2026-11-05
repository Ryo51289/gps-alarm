import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

extension Tag {
    /// ≥ 2 s (T01.1 rule): process-death sweep, suspension grid.
    @Tag static var slow: Self
}

/// ITR31 (process death) and ITR32 (app suspended) per docs/specs/T17.md "Sửa spec sau review vòng 1" R4.
@Suite("RuntimeKillSuspend")
struct KillSuspendTraceTests {
    struct Base: Sendable {
        let tbMs: Int64      // first Alarm of the no-death run, ms from the GPX start
        let reason: String
        let tolMs: Int64
    }

    static func base(_ trace: TraceCase, _ c: ExpectCase) async -> Base? {
        let w = World(startWall: trace.startMs)
        if let s = c.osRingMaxS { w.alarms.silenceAfterMs = Int64(s) * 1000 }
        await w.listen()
        _ = await w.runtime.start(meta: RuntimeFixtures.meta(trace, c), destLat: trace.destLat, destLng: trace.destLng)
        await w.settle()
        await TraceRun(world: w, trace: trace).run(endT: trace.durationS, stopAtFirstAlarm: true)
        w.sleeper.releaseAll()
        guard let a = w.seen.firstAlarm() else { return nil }
        let p = EngineParams.defaults
        return Base(tbMs: a.atMs - trace.startMs, reason: a.reason.jsonName,
                    tolMs: Int64(p.fallbackLagS) * 1000 + Int64(p.samplingDenseIntervalS) * 1000 + 1000)
    }

    /// A world that ran the case until trace second `untilS`.
    static func prefix(_ trace: TraceCase, _ c: ExpectCase, untilS: Int) async -> (World, TripMeta) {
        let w = World(startWall: trace.startMs)
        if let s = c.osRingMaxS { w.alarms.silenceAfterMs = Int64(s) * 1000 }
        await w.listen()
        let meta = RuntimeFixtures.meta(trace, c)
        _ = await w.runtime.start(meta: meta, destLat: trace.destLat, destLng: trace.destLng)
        await w.settle()
        await TraceRun(world: w, trace: trace).run(endT: untilS)
        return (w, meta)
    }

    static func tripTransitions(_ w: World, _ tripId: String) -> [(id: String, tripId: String, kind: SystemAlarmKind, wall: Int64)] {
        w.alarms.transitionList.filter { $0.tripId == tripId }
    }

    /// Advances (no process or suspended) until the first `alerting` of the trip after index `from`, or `limitV`.
    static func untilRing(_ w: World, _ tripId: String, from: Int, limitV: Int64) async -> (id: String, kind: SystemAlarmKind, wall: Int64)? {
        while w.time.v < limitV {
            let off = w.time.wallMs() - w.time.v
            let next = min(w.alarms.nextTransitionV(wallBaseOffset: off) ?? limitV, limitV)
            await w.advance(to: max(next, w.time.v))
            let t = tripTransitions(w, tripId)
            if t.count > from { return (t[from].id, t[from].kind, t[from].wall) }
            if next >= limitV { break }
        }
        return nil
    }

    static func order(_ w: World, _ a: String, _ b: String) -> Bool {
        let evs = w.journal.all.map(\.ev)
        guard let i = evs.lastIndex(of: a), let j = evs.lastIndex(of: b) else { return false }
        return i < j
    }

    static func stopIntent(_ w: World, tripId: String, alarmId: String, kind: SystemAlarmKind) async {
        let rec = RingEventRec(tripId: tripId, alarmId: alarmId, kind: kind, action: .dismiss, atWallMs: w.time.wallMs())
        try? w.store.appendRingEvent(rec)
        await w.runtime.onStopIntent(rec)
        await w.settle()
    }

    final class Stats: @unchecked Sendable {
        let lock = NSLock()
        var lines: [String] = []
        func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    }

    // MARK: ITR31

    /// Branches (a), (c), (c′): death at `tk`, the first slot rings, Stop after 5 s, P2 in the background, StopIntent `d` ms
    /// after ensureLoaded. Returns F − arrival (s) for the statistics.
    static func branchA(_ w: World, _ meta: TripMeta, _ trace: TraceCase, tkS: Int, delayMs: Int64, key: String) async -> Int64? {
        let id = meta.tripId
        let scheduled = w.alarms.all.filter { $0.tripId == id && $0.state == .scheduled }
        #expect(!scheduled.isEmpty, "\(key) A1 at \(tkS)")
        let cur = w.store.currentLedger.current
        let before = tripTransitions(w, id).count
        guard let ring = await untilRing(w, id, from: before, limitV: Int64(trace.durationS + 7200) * 1000) else {
            Issue.record("\(key) A: nothing rang after death at \(tkS)")
            return nil
        }
        #expect(ring.wall == cur?.targetAtWallMs, "\(key) A2 at \(tkS)")
        await w.advance(to: ring.wall - w.startWall + 5_000)
        w.alarms.setState(ring.id, nil)
        let starts0 = w.location.startCount
        let now0 = w.alarms.scheduledRequests().filter { $0.kind == .now }.count
        w.relaunch(.background)
        // V2-3: a listener attached before the restore (test seam, no D13 wait) sees the TripEnded of the restore Step.
        let p2 = Seen()
        _ = await w.runtime.addListenerWithoutRestoreWait { _, view, choice, events in p2.add(.init(view: view, choice: choice, events: events)) }
        await w.runtime.ensureLoaded()
        await w.advance(by: delayMs)
        await stopIntent(w, tripId: id, alarmId: ring.id, kind: ring.kind)
        await w.advance(by: 600_000)
        #expect(w.location.startCount == starts0, "\(key) A3 location at \(tkS)/\(delayMs)")
        #expect(w.alarms.scheduledRequests().filter { $0.kind == .now }.count == now0, "\(key) A3 now at \(tkS)/\(delayMs)")
        #expect(!w.alarms.all.contains { $0.tripId == id }, "\(key) A4 alarms left at \(tkS)/\(delayMs)")
        #expect(tripTransitions(w, id).count == 1, "\(key) A4 rings at \(tkS)/\(delayMs)")
        #expect(w.store.finished[id]?.endReason == "DISMISSED", "\(key) A5 at \(tkS)/\(delayMs)")
        var ended: TripEvent.TripEnded?
        for case let .tripEnded(x) in p2.events { ended = x }
        #expect(ended != nil, "\(key) A5 TripEnded at \(tkS)/\(delayMs)")
        if let e = ended { #expect(w.store.finished[id] == FinishedRecordBuilder.fromEvent(tripId: id, e), "\(key) A5 record") }
        if delayMs < 2_000 {
            #expect(order(w, "stop_intent", "restore"), "\(key) D13 at \(tkS)/\(delayMs)")
        } else {
            #expect(order(w, "restore", "stop_intent"), "\(key) c′ order at \(tkS)")
        }
        w.sleeper.releaseAll()
        return (ring.wall - trace.startMs) / 1000 - Int64(trace.arrivalT)
    }

    /// Branch (b): the user opens the app 120 s after death. nil = skipped (a slot rang in the 120 s).
    /// nil = skipped (a slot rang within 120 s of death); else the reason pair ("" when equal to reason_b).
    static func branchB(_ w: World, _ meta: TripMeta, _ trace: TraceCase, tkS: Int, base: Base, key: String) async -> String? {
        let id = meta.tripId
        let before = tripTransitions(w, id).count
        let r = Int64(tkS) * 1000 + 120_000
        await w.advance(to: r)
        if tripTransitions(w, id).count > before { w.sleeper.releaseAll(); return nil }
        let starts0 = w.location.startCount
        w.relaunch(.active)
        let journalFrom = w.journal.all.count
        await w.listen()
        await w.runtime.ensureLoaded()
        await w.settle()
        let status = w.journal.all.last { $0.ev == "restore" }?.fields["status"]
        #expect(status == "PENDING" || status == "MISSING", "\(key) B1 at \(tkS): \(status ?? "nil")")
        #expect(w.location.startCount == starts0 + 1, "\(key) B2 at \(tkS)")
        let world = w
        await TraceRun(world: w, trace: trace).run(endT: trace.durationS,
                                                   stopWhen: { tripTransitions(world, id).count > before })
        guard let ring = await untilRing(w, id, from: before, limitV: w.time.v + 120_000) else {
            Issue.record("\(key) B: nothing rang after reopening at \(tkS)")
            return nil
        }
        // B3. A reopening after T_b cannot ring before R + AK_NOW_LEAD (the spec bound assumes R ≤ T_b + tol − lead).
        let tk = ring.wall - trace.startMs
        let bound = max(base.tbMs + base.tolMs, r + RuntimeConstants.default.akNowLeadMs + 1_000)
        #expect(tk <= bound, "\(key) B3 at \(tkS): \(tk) > \(bound)")
        // B4: the first Alarm of P2 (the restore Step itself may carry it, so read the journal, not the listener).
        let reason = w.journal.all.dropFirst(journalFrom).first { $0.ev == "step" && !($0.fields["reason"] ?? "").isEmpty }?
            .fields["reason"] ?? "none"
        #expect(reason == base.reason || ["GPS_LOST", "FALLBACK", "FALLBACK_MISSED"].contains(reason), "\(key) B4 at \(tkS): \(reason)")
        await w.advance(by: 5_000)
        #expect(w.alarms.doubleRings == 0, "\(key) B5 double at \(tkS)")
        #expect(tripTransitions(w, id).count == before + 1, "\(key) B5 rings at \(tkS)")
        await w.runtime.userAction(tripId: id, .dismiss)
        await w.settle()
        #expect(w.store.finished[id] != nil, "\(key) B6 at \(tkS)")
        w.sleeper.releaseAll()
        return reason == base.reason ? "" : "\(base.reason)->\(reason)"
    }

    /// Branch (d): death while the "now" alarm waits/rings; Stop at fireAt + 5 s; P2 in the background, StopIntent 40 ms later.
    static func branchD(_ trace: TraceCase, _ c: ExpectCase, base: Base, key: String) async {
        let tRing = Int((base.tbMs + 999) / 1000) + 2
        let (w, meta) = await prefix(trace, c, untilS: tRing)
        let id = meta.tripId
        guard let n = w.store.currentLedger.now, n.confirmed else {
            Issue.record("\(key) D: no confirmed now alarm at T_b + 2 s")
            return
        }
        let before = tripTransitions(w, id).count
        w.kill()
        await w.advance(to: n.fireAtWallMs - w.startWall)
        #expect(tripTransitions(w, id).contains { $0.id == n.alarmId }, "\(key) D1")
        await w.advance(to: n.fireAtWallMs - w.startWall + 5_000)
        w.alarms.setState(n.alarmId, nil)
        let slotAtStop = w.alarms.all.filter { $0.tripId == id && $0.kind != .now && $0.state == .scheduled }
        #expect(!slotAtStop.isEmpty, "\(key) D2 a slot still scheduled at Stop")
        let now0 = w.alarms.scheduledRequests().filter { $0.kind == .now }.count
        w.relaunch(.background)
        let world = w
        Task { await world.listen() }
        await w.runtime.ensureLoaded()
        await w.advance(by: 40)
        await stopIntent(w, tripId: id, alarmId: n.alarmId, kind: .now)
        await w.advance(by: 600_000)
        #expect(!w.alarms.all.contains { $0.tripId == id }, "\(key) D2 slot cancelled")
        #expect(tripTransitions(w, id).count == before + 1, "\(key) D2 one ring")
        #expect(w.alarms.scheduledRequests().filter { $0.kind == .now }.count == now0, "\(key) D3 no now in P2")
        #expect(w.store.finished[id]?.endReason == "DISMISSED", "\(key) D3")
        w.sleeper.releaseAll()
    }

    @Test("ITR31 process-death sweep every 300 s: branches a, b, c, c′, d", .tags(.slow), arguments: RuntimeTraceTests.caseIds)
    func itr31(_ key: String) async throws {
        let parts = key.split(separator: "/").map(String.init)
        let trace = try RuntimeFixtures.read(parts[0])
        let c = try #require(trace.cases.first { $0.id == parts[1] })
        let base = try #require(await Self.base(trace, c), "\(key): no first alarm")
        var lateness: [Int64] = []
        var skippedB = 0, points = 0
        var reasonPairs: [String: Int] = [:]
        // One prefix run; at each death point t_k the surviving state is forked for every branch.
        let (w, meta) = await Self.prefix(trace, c, untilS: 0)
        let run = TraceRun(world: w, trace: trace)
        var k = 1
        while Int64(300 * k) * 1000 < base.tbMs {
            let tk = 300 * k
            await run.run(endT: tk)
            points += 1
            for d: Int64 in [40, 1_900, 2_100] {
                if let late = await Self.branchA(w.forkKilled(), meta, trace, tkS: tk, delayMs: d, key: key), d == 40 {
                    lateness.append(late)
                }
            }
            if let pair = await Self.branchB(w.forkKilled(), meta, trace, tkS: tk, base: base, key: key) {
                if !pair.isEmpty { reasonPairs[pair, default: 0] += 1 }
            } else {
                skippedB += 1
            }
            k += 1
        }
        w.sleeper.releaseAll()
        await Self.branchD(trace, c, base: base, key: key)
        let sorted = lateness.sorted()
        let line = "\(key)\tpoints=\(points)\tbSkipped=\(skippedB)\tF-arrival(s) min=\(sorted.first ?? 0) median=\(sorted.isEmpty ? 0 : sorted[sorted.count / 2]) max=\(sorted.last ?? 0)\treasonPairs=\(reasonPairs)\n"
        RTPaths.write("\(RTPaths.reportDir)/ios-killsweep/\(key.replacingOccurrences(of: "/", with: "__")).txt", line)
    }

    // MARK: ITR32

    static let suspendCases: [String] = {
        var out: [String] = []
        for id in ["coach_dn_langco_neardest", "coach_dn_langco_tunnel"] {
            guard let t = try? RuntimeFixtures.read(id) else { continue }
            for c in RuntimeFixtures.l30Cases(t) { out.append("\(id)/\(c.id)") }
        }
        return out
    }()

    /// `intentFirst`: when a slot rang in the window and the user tapped Stop, the StopIntent runs before the queued
    /// deliveries (one possible iOS order); false = the spec R4 order (queued fixes, alarmUpdates, timer, then StopIntent).
    static func suspendRun(_ trace: TraceCase, _ c: ExpectCase, base: Base, sOffS: Int, dS: Int, key: String,
                           intentFirst: Bool = true) async -> String {
        let sS = Int(base.tbMs / 1000) - sOffS
        let (w, meta) = await prefix(trace, c, untilS: sS)
        let id = meta.tripId
        let tag = "\(key) S=Tb-\(sOffS) D=\(dS)" + (intentFirst ? "" : " fixes-first")
        let fS = EffectPlanner.liveSlot(w.store.currentLedger, list: w.alarms.all)?.targetAtWallMs
        let before = tripTransitions(w, id).count
        let eV = Int64(sS + dS) * 1000
        w.suspended = true
        let ringInWindow = await untilRing(w, id, from: before, limitV: eV)
        let endV = ringInWindow.map { min(eV, $0.wall - w.startWall + 5_000) } ?? eV
        await w.advance(to: endV)
        w.suspended = false
        var stopped = false
        var firstRing = ringInWindow
        if let r = ringInWindow {
            // The user taps Stop (iOS removes the alarm); the intent then wakes the app.
            w.alarms.setState(r.id, nil)
            if intentFirst {
                await stopIntent(w, tripId: id, alarmId: r.id, kind: r.kind)
            }
            stopped = true
        }
        // Queued Core Location deliveries [I3], then alarmUpdates (settle), then the due timer once (advance).
        var queued = 0
        for x in trace.samples where x.t >= sS && Int64(x.t) * 1000 < endV {
            w.location.sink?.locationSession(didReceive: RawFix(
                lat: x.lat, lng: x.lng, horizontalAccuracyM: x.accuracyM, speedMps: x.speedMps ?? -1,
                timestampWallMs: trace.startMs + Int64(x.t) * 1000))
            queued += 1
        }
        await w.settle()
        await w.advance(to: w.time.v)
        if stopped && !intentFirst, let r = ringInWindow {
            await stopIntent(w, tripId: id, alarmId: r.id, kind: r.kind)
            await w.advance(by: 600_000)
        }
        if !stopped {
            await TraceRun(world: w, trace: trace).run(endT: trace.durationS, stopAtFirstAlarm: true)
            firstRing = await untilRing(w, id, from: before, limitV: w.time.v + 120_000)
            if let r = firstRing {
                await w.advance(to: max(w.time.v, r.wall - w.startWall + 5_000))
                // S3: no now alarm scheduled while a fallback/guard slot is alerting.
                if r.kind != .now {
                    #expect(!w.alarms.schedules.contains { $0.kind == .now && $0.wall >= r.wall && $0.wall <= w.time.wallMs() }, "\(tag) S3 now")
                }
                #expect(tripTransitions(w, id).count == before + 1 && w.alarms.doubleRings == 0, "\(tag) S1")
                w.alarms.setState(r.id, nil)
                await stopIntent(w, tripId: id, alarmId: r.id, kind: r.kind)
            }
        } else {
            #expect(tripTransitions(w, id).count == before + 1 && w.alarms.doubleRings == 0, "\(tag) S1")
        }
        guard let ring = firstRing else {
            Issue.record("\(tag): nothing rang")
            return "\(tag)\tnone\n"
        }
        let tbIn = base.tbMs >= Int64(sS) * 1000 && base.tbMs < eV
        let bound = (tbIn ? (fS.map { $0 - trace.startMs } ?? base.tbMs + base.tolMs) : base.tbMs + base.tolMs) + 1_000
        #expect(ring.wall - trace.startMs <= bound, "\(tag) S2: \(ring.wall - trace.startMs) > \(bound)")
        if ring.kind != .now {
            let fed = w.journal.all.filter { $0.ev == "fb_fired" }.count
            #expect(fed == 1, "\(tag) S3 FallbackFired x\(fed)")
        }
        let fixAts = w.journal.all.filter { $0.ev == "fix" }.compactMap { $0.fields["fixAt"].flatMap { Int64($0) } }
        #expect(zip(fixAts, fixAts.dropFirst()).allSatisfy { $0 <= $1 }, "\(tag) S4")
        #expect(w.store.finished[id] != nil, "\(tag) S5")
        w.sleeper.releaseAll()
        return "\(tag)\tring=\(ring.wall - trace.startMs - base.tbMs)ms vs Tb\tsource=\(ring.kind.rawValue)\tqueued=\(queued)\tdropped=\(w.seen.entries.last?.view.droppedFixes ?? 0)\n"
    }

    @Test("ITR32 app suspended 10/30 min in the final phases", .tags(.slow), arguments: suspendCases)
    func itr32(_ key: String) async throws {
        let parts = key.split(separator: "/").map(String.init)
        let trace = try RuntimeFixtures.read(parts[0])
        let c = try #require(trace.cases.first { $0.id == parts[1] })
        let base = try #require(await Self.base(trace, c), "\(key): no first alarm")
        var out = ""
        for s in [1_200, 600, 120] {
            for d in [600, 1_800] { out += await Self.suspendRun(trace, c, base: base, sOffS: s, dS: d, key: key) }
            // V2-4: the spec R4 order (queued fixes before the StopIntent) where a slot rings during the window.
            out += await Self.suspendRun(trace, c, base: base, sOffS: s, dS: 1_800, key: key, intentFirst: false)
        }
        RTPaths.write("\(RTPaths.reportDir)/ios-suspend/\(key.replacingOccurrences(of: "/", with: "__")).txt", out)
    }
}
