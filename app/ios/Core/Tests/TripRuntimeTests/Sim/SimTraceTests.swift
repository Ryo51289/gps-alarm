import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T18.1 trace tests (docs/specs/T18.1.md): SIU10 (the engine sequence of a simulated trip does not depend on the speed or
/// on a late timer: the T18.2 bug cannot happen on iOS), SIU14 (= SM15), SIU17 (= SM20), SIU18 (= SM22).
@Suite("SimTrace")
struct SimTraceTests {
    static let speeds: [Double] = [1, 10, 60, 600, 6_000]
    static let seeds: [UInt64] = [11, 22, 33]
    static let maxJitterMs: Int64 = 2_000

    struct Outcome {
        let lines: [String]
        let firstAlarm: TripEvent.Alarm?
        let world: World
    }

    /// ITR30 run (real trip on the fakes, TraceRun) of one case: its transcript up to the end of the trace.
    static func realRun(_ trace: TraceCase, _ c: ExpectCase) async -> Outcome {
        let world = World(startWall: trace.startMs)
        if let s = c.osRingMaxS { world.alarms.silenceAfterMs = Int64(s) * 1000 }
        await world.listen()
        _ = await world.runtime.start(meta: RuntimeFixtures.meta(trace, c), destLat: trace.destLat, destLng: trace.destLng)
        await world.settle()
        await TraceRun(world: world, trace: trace).run(endT: trace.durationS)
        let end = trace.startMs + Int64(trace.durationS) * 1000
        return Outcome(lines: SimFixtures.transcript(world.seen.entries, startMs: trace.startMs, untilMs: end),
                       firstAlarm: world.seen.firstAlarm(), world: world)
    }

    /// The same case as a simulated trip at `speed`, the in-process timer late by up to `maxJitterMs` (seeded).
    static func simRun(_ trace: TraceCase, _ c: ExpectCase, speed: Double, seed: UInt64?, jitterMs: Int64) async -> Outcome {
        let world = World(startWall: trace.startMs, traces: FixtureTraceStore())
        if let s = c.osRingMaxS { world.alarms.silenceAfterMs = Int64(s) * 1000 }
        await world.listen()
        let r = await world.runtime.start(meta: SimFixtures.simMeta(trace, c, speed: speed), destLat: trace.destLat,
                                          destLng: trace.destLng)
        #expect(r == .started)
        await world.settle()
        let end = trace.startMs + Int64(trace.durationS) * 1000
        let seen = world.seen
        await SimRun(world: world, seed: seed, maxJitterMs: jitterMs).run(maxV: Int64(trace.durationS) * 1000 + 7_200_000) {
            seen.entries.contains { $0.view.atMs > end || $0.view.phase == .ended }
        }
        return Outcome(lines: SimFixtures.transcript(world.seen.entries, startMs: trace.startMs, untilMs: end),
                       firstAlarm: world.seen.firstAlarm(), world: world)
    }

    static func firstDifference(_ a: [String], _ b: [String]) -> (index: Int, text: String)? {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : "<none>", y = i < b.count ? b[i] : "<none>"
            if x != y {
                let lo = max(0, i - 3)
                let ctxA = a[lo..<min(a.count, i + 3)].joined(separator: " / ")
                let ctxB = b[lo..<min(b.count, i + 3)].joined(separator: " / ")
                return (i, "step #\(i): expected \(x) | got \(y)\n  ITR30: \(ctxA)\n  sim:   \(ctxB)")
            }
        }
        return nil
    }

    /// Index of the first ITR30 Step made by an input of real-time origin: the OS alarm stopping by itself after
    /// `osRingMaxS` real seconds (checkGone → AlarmSilenced, T17 obligation 6). nil = none in this run.
    static func osSilenceStep(_ entries: [Seen.Entry]) -> Int? {
        guard entries.count > 1 else { return nil }
        for i in 1..<entries.count where entries[i - 1].view.alarmRinging && !entries[i].view.alarmRinging
            && entries[i].events.isEmpty {
            return i
        }
        return nil
    }

    /// Q3 = A (designer 06/11): from the first input of real-time origin on, the engine events of the simulated trip are
    /// compared by kind (alarm reason, gpsLost cause, tripEnded outcome/endReason) and time within `tol`. `alarmSilenced`
    /// stands for the Step where the ring stops with no engine event.
    struct Token: Equatable, CustomStringConvertible {
        let name: String
        let atMs: Int64
        var description: String { "\(name)@\(atMs)" }
    }

    static func tokens(_ entries: [Seen.Entry], from: Int, startMs: Int64) -> [Token] {
        var out: [Token] = []
        for i in from..<entries.count {
            let e = entries[i]
            if i > 0, entries[i - 1].view.alarmRinging, !e.view.alarmRinging, e.events.isEmpty {
                out.append(Token(name: "alarmSilenced", atMs: e.view.atMs - startMs))
            }
            for x in e.events {
                var n = x.fixtureName
                switch x {
                case let .alarm(a): n += "[\(a.reason.jsonName),\(a.ringNow)]"
                case let .gpsLost(g): n += "[\(g.cause.jsonName)]"
                case let .tripEnded(t): n += "[\(t.outcome.jsonName),\(t.endReason.jsonName)]"
                default: break
                }
                out.append(Token(name: n, atMs: x.atMs - startMs))
            }
        }
        return out
    }

    /// tol = maxTimerJitterMs + samplingDenseIntervalS·1000 + STOP_INTENT_GRACE_MS + 1 000 (designer Q3).
    static let tolMs: Int64 = maxJitterMs + 5_000 + RuntimeConstants.default.stopIntentGraceMs + 1_000

    /// nil = criteria 2 (a), (b) hold; else the first violation.
    static func compareAfter(_ ref: [Token], _ sim: [Token], endMs: Int64) -> String? {
        let r = ref.filter { $0.atMs <= endMs }
        var s = sim.filter { $0.atMs <= endMs + tolMs }
        while s.count > r.count, let last = s.last, last.atMs > endMs { s.removeLast() }
        if r.map(\.name) != s.map(\.name) { return "(a) kinds differ: ITR30 \(r) | sim \(s)" }
        for (a, b) in zip(r, s) where abs(a.atMs - b.atMs) > tolMs {
            return "(b) \(a.name) at \(b.atMs) vs ITR30 \(a.atMs): |Δ| > \(tolMs) ms"
        }
        return nil
    }

    /// (c) invariants of a simulated run: never two alarms of the trip alerting at once; every Alarm(ringNow) is one
    /// schedule(.now) of a Step, one planner FallbackFired, or the live "now" (as ITR30); after an OS self-silence while the
    /// trip overshoots, exactly one Alarm(OVERSHOOT, ringNow).
    static func invariants(_ w: World, key: String, endMs: Int64, startMs: Int64, osSilence: Bool) {
        #expect(w.alarms.doubleRings == 0, "\(key): two alarms alerting")
        let events = w.seen.entries.filter { $0.view.atMs - startMs <= endMs }.flatMap(\.events)
        let ringNow = events.filter { if case let .alarm(a) = $0 { return a.ringNow }; return false }.count
        let lines = w.journal.all
        let nowSchedules = lines.filter { $0.ev == "ak" && $0.fields["kind"] == "now" && $0.fields["ok"] == "true" }.count
        let guardRings = lines.filter { $0.ev == "sim_guard" }.count
        let fed = lines.filter { $0.ev == "fb_fired" && $0.fields["src"] == "planner" }.count
        let live = lines.filter { $0.ev == "ring_live" }.count
        #expect(ringNow == nowSchedules - guardRings + fed + live,
                "\(key): ringNow \(ringNow) vs now \(nowSchedules) − guard \(guardRings) + fed \(fed) + live \(live)")
        if osSilence, events.contains(where: { $0.fixtureName == "overshoot" }) {
            let over = events.filter { if case let .alarm(a) = $0 { return a.reason == .overshoot && a.ringNow }; return false }
            #expect(over.count == 1, "\(key): Alarm(OVERSHOOT, ringNow) after the OS silence")
        }
    }

    @Test("SIU10 same engine sequence at 1/10/60/600/6000× with a 0–2 s late timer, = ITR30 (anti T18.2)", .tags(.slow),
          arguments: RuntimeTraceTests.caseIds)
    func siu10(_ key: String) async throws {
        let parts = key.split(separator: "/").map(String.init)
        let trace = try RuntimeFixtures.read(parts[0])
        let c = try #require(trace.cases.first { $0.id == parts[1] })
        let ref = await Self.realRun(trace, c)
        #expect(!ref.lines.isEmpty)
        let osSilence = c.osRingMaxS == nil ? nil : Self.osSilenceStep(ref.world.seen.entries)
        if c.osRingMaxS != nil { #expect(osSilence != nil, "\(key): ITR30 has the OS silence Step") }
        let endMs = Int64(trace.durationS) * 1000
        let table = try FirstAlarmTable.load()
        let row = try #require(table.first { $0.trace == parts[0] && $0.caseId == parts[1] })
        for speed in Self.speeds {
            for seed in Self.seeds {
                let sim = await Self.simRun(trace, c, speed: speed, seed: seed, jitterMs: Self.maxJitterMs)
                let label = "\(key) speed \(speed) seed \(seed)"
                if let s = osSilence {
                    // 1. Identical before the first input of real-time origin; 2. kinds + tolerance from there (Q3 = A).
                    if let d = Self.firstDifference(Array(ref.lines.prefix(s)), Array(sim.lines.prefix(s))) {
                        Issue.record(Comment(rawValue: "\(label): before the OS silence, first difference at \(d.text)"))
                    }
                    let a = Self.tokens(ref.world.seen.entries, from: s, startMs: trace.startMs)
                    let b = Self.tokens(sim.world.seen.entries, from: min(s, sim.world.seen.entries.count), startMs: trace.startMs)
                    if let v = Self.compareAfter(a, b, endMs: endMs) { Issue.record(Comment(rawValue: "\(label): \(v)")) }
                } else if let d = Self.firstDifference(ref.lines, sim.lines) {
                    Issue.record(Comment(rawValue: "\(label): first difference vs ITR30 at \(d.text)"))
                }
                Self.invariants(sim.world, key: label, endMs: endMs, startMs: trace.startMs, osSilence: osSilence != nil)
                #expect(sim.firstAlarm?.reason.jsonName == row.reason, "\(label): first alarm reason")
                #expect(sim.world.alarms.scheduledRequests().allSatisfy { $0.kind != .guardSlot }, "\(label): no guard alarm")
                #expect(sim.world.warns.isEmpty, "\(label): warnings \(sim.world.warns)")
                sim.world.sleeper.releaseAll()
            }
        }
        // The invariants hold for the real trip too (sanity of the checks).
        Self.invariants(ref.world, key: "\(key) ITR30", endMs: endMs, startMs: trace.startMs, osSilence: osSilence != nil)
        ref.world.sleeper.releaseAll()
    }

    /// (virtual real ms, Step) of every Publish.
    final class TimedSteps: Locked, @unchecked Sendable {
        private var items: [(v: Int64, view: TripView, events: [TripEvent])] = []
        func add(_ v: Int64, _ view: TripView, _ events: [TripEvent]) { locked { items.append((v, view, events)) } }
        var all: [(v: Int64, view: TripView, events: [TripEvent])] { locked { items } }
    }

    @Test("SIU21 6000×, the command with the alarm Step 2 s late: nothing past T_alarm in it, clock back at T_alarm, silence before overshoot")
    func siu21() async throws {
        let trace = try RuntimeFixtures.read("coach_gb_phuly_overshoot")
        let c = try #require(trace.cases.first { $0.id == "distance_1000_overshoot_silenced" })
        let world = World(startWall: trace.startMs, traces: FixtureTraceStore())
        world.alarms.silenceAfterMs = Int64(try #require(c.osRingMaxS)) * 1000
        await world.listen()
        let steps = TimedSteps()
        let time = world.time
        _ = await world.runtime.addListener { _, view, _, events in steps.add(time.v, view, events) }
        #expect(await world.runtime.start(meta: SimFixtures.simMeta(trace, c, speed: 6_000), destLat: trace.destLat,
                                          destLng: trace.destLng) == .started)
        await world.settle()
        // On time until 40 trip s before the alarm (ITR30: 2 341.289 s).
        let seen = world.seen
        await SimRun(world: world).run(maxV: 60_000) { (seen.entries.last?.view.atMs ?? 0) - trace.startMs >= 2_300_000 }
        #expect(seen.firstAlarm() == nil)
        // The next timer is delivered 2 s late (= 12 000 trip s at 6000×): one command catches up past the alarm.
        let due = try #require(world.timer.due)
        world.timer.consume()
        world.time.v = due.v + 2_000
        let lateV = world.time.v
        await world.runtime.onTimer(generation: due.gen)
        await world.settle()
        let alarm = try #require(seen.firstAlarm())
        let tAlarm = alarm.atMs
        let inCommand = steps.all.filter { $0.v == lateV }
        #expect(inCommand.contains { $0.events.contains { $0.fixtureName == "alarm" } })
        #expect(inCommand.allSatisfy { $0.view.atMs <= tAlarm }, "a virtual event past T_alarm in the late command")
        // Clock back at T_alarm, 1×: an external input now (D5) runs at T_alarm exactly.
        _ = await world.runtime.addListener { _, _, _, _ in }
        await world.settle()
        #expect(steps.all.last?.view.atMs == tAlarm)
        // Then on time at 1×: every engine input at or after T_alarm, and the OS silence before the overshoot (as ITR30).
        await SimRun(world: world).run(maxV: lateV + 400_000) { seen.events.contains { $0.fixtureName == "overshoot" } }
        let all = steps.all
        let iAlarm = try #require(all.firstIndex { $0.events.contains { $0.fixtureName == "alarm" } })
        #expect(all[iAlarm...].allSatisfy { $0.view.atMs >= tAlarm }, "no engine input before T_alarm after the alarm")
        let silence = all.indices.first { i in i > 0 && all[i - 1].view.alarmRinging && !all[i].view.alarmRinging && all[i].events.isEmpty }
        let overshoot = all.firstIndex { $0.events.contains { $0.fixtureName == "overshoot" } }
        let s = try #require(silence, "no AlarmSilenced")
        let o = try #require(overshoot, "no overshoot")
        #expect(s < o, "AlarmSilenced before Overshoot")
        #expect(abs((all[s].view.atMs - tAlarm) - (2_409_289 - 2_341_289)) <= Self.tolMs, "silence ≈ 68 s after the alarm")
        world.sleeper.releaseAll()
    }

    /// v (virtual real ms) at which the first Step matching `pred` was published.
    final class StepClock: Locked, @unchecked Sendable {
        private var at: [String: Int64] = [:]
        func mark(_ k: String, _ v: Int64) { locked { if at[k] == nil { at[k] = v } } }
        func get(_ k: String) -> Int64? { locked { at[k] } }
    }

    @Test("SIU17 train_hn_dh distance_1000 at 60×: PreAlert, Alarm(DISTANCE) windows, ≈ 561.7 s real (= SM20)", .tags(.slow))
    func siu17() async throws {
        let trace = try RuntimeFixtures.read("train_hn_dh")
        let c = try #require(trace.cases.first { $0.id == "distance_1000" })
        let world = World(startWall: trace.startMs, traces: FixtureTraceStore())
        await world.listen()
        let marks = StepClock()
        let time = world.time
        _ = await world.runtime.addListener { _, _, _, events in
            for case let .alarm(a) in events where a.ringNow { marks.mark("alarm", time.v) }
        }
        #expect(await world.runtime.start(meta: SimFixtures.simMeta(trace, c, speed: 60), destLat: trace.destLat,
                                          destLng: trace.destLng) == .started)
        await world.settle()
        await SimRun(world: world).run(maxV: Int64(trace.durationS) * 1000 / 60 + 600_000) { marks.get("alarm") != nil }
        func t(_ ms: Int64) -> Int64 { (ms - trace.startMs) / 1000 }
        let pre = try #require(world.seen.events.first { $0.fixtureName == "preAlert" })
        #expect((33_435...33_470).contains(t(pre.atMs)), "preAlert at \(t(pre.atMs))")
        let alarm = try #require(world.seen.firstAlarm())
        #expect(alarm.reason == .distance && alarm.ringNow)
        #expect((33_680...33_715).contains(t(alarm.atMs)), "alarm at \(t(alarm.atMs))")
        let real = try #require(marks.get("alarm"))
        #expect(abs(real - (alarm.atMs - trace.startMs) / 60) <= 2_000, "rang after \(real) ms real")
        #expect(world.alarms.scheduledRequests().map(\.kind) == [.now], "only the ring is a system alarm")
        world.sleeper.releaseAll()
    }

    @Test("SIU18 coach_dn_langco_tunnel distance_1000_gps_lost at 60×: Alarm(GPS_LOST) in [1175, 1265] (= SM22)")
    func siu18() async throws {
        let trace = try RuntimeFixtures.read("coach_dn_langco_tunnel")
        let c = try #require(trace.cases.first { $0.id == "distance_1000_gps_lost" })
        let world = World(startWall: trace.startMs, traces: FixtureTraceStore())
        await world.listen()
        #expect(await world.runtime.start(meta: SimFixtures.simMeta(trace, c, speed: 60), destLat: trace.destLat,
                                          destLng: trace.destLng) == .started)
        await world.settle()
        let seen = world.seen
        await SimRun(world: world).run(maxV: 1_400_000 / 60 + 120_000) { seen.firstAlarm() != nil }
        let alarm = try #require(world.seen.firstAlarm())
        #expect(alarm.reason == .gpsLost)
        let at = (alarm.atMs - trace.startMs) / 1000
        #expect((1_175...1_265).contains(at), "GPS_LOST alarm at \(at)")
        // Inside the gap (no sample) the Steps came from engine wakes of the virtual queue.
        let inGap = world.seen.entries.filter { (1_175_000...1_265_000).contains($0.view.atMs - trace.startMs) }
        #expect(!inGap.isEmpty)
        #expect(world.alarms.scheduledRequests().allSatisfy { $0.kind == .now })
        world.sleeper.releaseAll()
    }

    @Test("SIU14 coach_gb_phuly_overshoot at 60×: 1× before the Alarm Step is planned; snooze = 60 s real (= SM15)")
    func siu14() async throws {
        let trace = try RuntimeFixtures.read("coach_gb_phuly_overshoot")
        let c = try #require(trace.cases.first { $0.id == "distance_1000_overshoot" })
        let world = World(startWall: trace.startMs, traces: FixtureTraceStore())
        await world.listen()
        let meta = SimFixtures.simMeta(trace, c, speed: 60)
        #expect(await world.runtime.start(meta: meta, destLat: trace.destLat, destLng: trace.destLng) == .started)
        await world.settle()
        let seen = world.seen
        await SimRun(world: world).run(maxV: Int64(trace.durationS) * 1000 / 60 + 60_000) { seen.firstAlarm() != nil }
        let lines = world.journal.all
        let iSpeed = try #require(lines.firstIndex { $0.ev == "sim_speed" })
        let iStep = try #require(lines.firstIndex { $0.ev == "step" && $0.fields["events"]?.contains("alarm") == true })
        let iRing = try #require(lines.firstIndex { $0.ev == "ak" && $0.fields["kind"] == "now" })
        #expect(iSpeed < iStep && iStep < iRing, "sim_speed \(iSpeed), alarm step \(iStep), ring \(iRing)")
        #expect(lines[iSpeed].fields["to"] == "1.0")
        // Snooze right away.
        let snoozeV = world.time.v
        await world.runtime.userAction(tripId: meta.tripId, .snooze)
        await world.settle()
        #expect(world.seen.entries.last?.view.phase == .snoozed)
        await SimRun(world: world).run(maxV: snoozeV + 600_000) {
            seen.events.contains { if case let .alarm(a) = $0 { return a.reason == .snoozeEnd }; return false }
        }
        let snoozeEnd = try #require(world.seen.events.first { if case let .alarm(a) = $0 { return a.reason == .snoozeEnd }; return false })
        let real = world.time.v - snoozeV
        #expect((59_000...61_000).contains(real), "SNOOZE_END after \(real) ms real")
        _ = snoozeEnd
        world.sleeper.releaseAll()
    }
}
