import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// ITR30, ITR30p, ITR33 (docs/specs/T17.md "Trace"): the six base traces through TripRuntime with the same expect.json
/// windows as Kotlin L30, and the first alarm of every case against fixtures/runtime/first-alarms.json.
@Suite("RuntimeTrace")
struct RuntimeTraceTests {
    static let caseIds: [String] = {
        var out: [String] = []
        for id in RuntimeFixtures.baseTraces {
            guard let t = try? RuntimeFixtures.read(id) else { continue }
            for c in RuntimeFixtures.l30Cases(t) { out.append("\(id)/\(c.id)") }
        }
        return out
    }()

    static let checked: Set<String> = ["alarm", "preAlert", "overshoot", "gpsLost", "arrived"]

    struct Result {
        let firstAlarm: TripEvent.Alarm?
        let startMs: Int64
        let schedules: Int
        let cancels: Int
        let hours: Double
        /// T17.3 NTR30: the world after the run (notification center, double rings).
        let world: World
    }

    /// Runs one case; `#expect`s the ITR30 windows and invariants.
    /// `configure` (T17.3 NTR30): changes the world before the trip starts (e.g. the notification channel only).
    static func runCase(_ key: String, configure: ((World) -> Void)? = nil) async throws -> Result {
        let parts = key.split(separator: "/").map(String.init)
        let trace = try RuntimeFixtures.read(parts[0])
        let c = try #require(trace.cases.first { $0.id == parts[1] })
        let world = World(startWall: trace.startMs)
        if let s = c.osRingMaxS { world.alarms.silenceAfterMs = Int64(s) * 1000 }
        configure?(world)
        await world.listen()
        let meta = RuntimeFixtures.meta(trace, c)
        let slotViolations = Counter()
        let alarms = world.alarms
        _ = await world.runtime.addListener { tripId, view, _, _ in
            guard view.phase == .acquiring || view.phase == .tracking else { return }
            let ok = alarms.all.contains { $0.tripId == tripId && $0.kind != .now && $0.state == .scheduled }
            if !ok { slotViolations.inc() }
        }
        let outcome = await world.runtime.start(meta: meta, destLat: trace.destLat, destLng: trace.destLng)
        #expect(outcome == .started, "\(key)")
        await world.settle()
        let run = TraceRun(world: world, trace: trace)
        await run.run(endT: trace.durationS)
        let events = world.seen.events
        func t(_ atMs: Int64) -> Int { Int((atMs - trace.startMs) / 1000) }
        for w in c.expect where checked.contains(w.event) {
            let first = events.first { matches(w, $0) }
            #expect(first != nil, "\(key): no \(w.event) \(w.reason ?? "")")
            if let f = first {
                let at = t(f.atMs)
                #expect(at >= w.notBefore && at <= w.notAfter, "\(key): \(w.event) \(w.reason ?? "") at \(at) not in [\(w.notBefore), \(w.notAfter)]")
            }
        }
        for f in c.forbid { #expect(!events.contains { eventName($0) == f }, "\(key): forbidden \(f)") }
        // Invariants.
        let ringNowEvents = events.filter { if case let .alarm(a) = $0 { return a.ringNow }; return false }.count
        let nowSchedules = world.alarms.scheduledRequests().filter { $0.kind == .now }.count
        // 1–1 (review #12): every Alarm(ringNow) is one schedule(.now), one planner FallbackFired, or a live "now" ring.
        let lines = world.journal.all
        let fedPlanner = lines.filter { $0.ev == "fb_fired" && $0.fields["src"] == "planner" }.count
        let live = lines.filter { $0.ev == "ring_live" }.count
        // Review T17.2.2 nit: a swallowed ring rung later (ring_swallowed{op:ring}) is a schedule(.now) without its own event.
        let swallowed = lines.filter { $0.ev == "ring_swallowed" && $0.fields["op"] == "ring" }.count
        #expect(ringNowEvents == nowSchedules - swallowed + fedPlanner + live,
                "\(key): ringNow events \(ringNowEvents) vs now alarms \(nowSchedules) − swallowed \(swallowed) + fed \(fedPlanner) + live \(live)")
        // IU36 over the ITR30 journal: no coordinates, no destination name, no distances.
        let lat = String(format: "%.4f", trace.destLat), lng = String(format: "%.4f", trace.destLng)
        for l in lines {
            let text = l.fields.values.joined(separator: " ")
            #expect(!text.contains(lat) && !text.contains(lng) && !text.contains(meta.destinationName), "\(key): journal \(l.ev)")
            #expect(!l.fields.keys.contains { $0.lowercased().contains("lat") || $0.lowercased().contains("lng") || $0.lowercased().contains("dist") })
        }
        #expect(slotViolations.value == 0, "\(key): no fallback slot while ACQUIRING/TRACKING")
        #expect(world.alarms.doubleRings == 0, "\(key): two alarms of the trip alerting at once")
        let ops = world.log.ops
        var lastRing = -1
        for (i, op) in ops.enumerated() where op.hasPrefix("schedule.now") {
            #expect(ops[(lastRing + 1)..<i].contains("writeActive"), "\(key): persistNow before ringNow #\(i)")
            lastRing = i
        }
        #expect(world.warns.isEmpty, "\(key): warnings \(world.warns)")
        #expect(run.fixesDelivered > 0)
        if let expected = c.expectOutcome {
            #expect(world.store.finished[meta.tripId]?.outcome == expected, "\(key): outcome")
        }
        let first = world.seen.firstAlarm()
        let schedules = world.alarms.scheduledRequests().count
        let cancels = world.alarms.cancels.count
        // L19 through the runtime: end the trip; the record equals TripEnded.summary; nothing left behind.
        if world.store.finished[meta.tripId] == nil {
            await world.runtime.userAction(tripId: meta.tripId, .stopTrip)
            await world.settle()
        }
        var endedEvent: TripEvent.TripEnded?
        for case let .tripEnded(e) in world.seen.events { endedEvent = e }
        let ended = try #require(endedEvent, "\(key): TripEnded")
        #expect(world.store.finished[meta.tripId] == FinishedRecordBuilder.fromEvent(tripId: meta.tripId, ended), "\(key): record")
        #expect(await world.runtime.mode() == .idle)
        #expect(!world.alarms.all.contains { $0.tripId == meta.tripId }, "\(key): alarms left")
        #expect(!world.location.isRunningNow)
        #expect(world.store.activeTrip == nil)
        world.sleeper.releaseAll()
        return Result(firstAlarm: first, startMs: trace.startMs, schedules: schedules, cancels: cancels,
                      hours: Double(trace.durationS) / 3600, world: world)
    }

    @Test("ITR30 + ITR30p: base traces through the runtime, first alarm = Kotlin L30", arguments: caseIds)
    func itr30(_ key: String) async throws {
        let r = try await Self.runCase(key)
        // ITR30p.
        let table = try FirstAlarmTable.load()
        let parts = key.split(separator: "/").map(String.init)
        let row = try #require(table.first { $0.trace == parts[0] && $0.caseId == parts[1] }, "\(key): not in first-alarms.json")
        let mine = r.firstAlarm.map { $0.atMs - r.startMs }
        #expect(r.firstAlarm?.reason.jsonName == row.reason, "\(key): first alarm reason \(r.firstAlarm?.reason.jsonName ?? "nil") vs Kotlin \(row.reason ?? "nil")")
        if let m = mine, let k = row.atMsRel {
            #expect(abs(m - k) <= 1000, "\(key): first alarm at \(m) ms vs Kotlin \(k) ms")
        } else {
            #expect(mine == nil && row.atMsRel == nil, "\(key): first alarm presence")
        }
        // ITR33 (information only): AlarmKit command counts.
        let line = "\(key)\tschedule=\(r.schedules)\tcancel=\(r.cancels)\tperHour=\(Int(Double(r.schedules + r.cancels) / max(r.hours, 1.0 / 60)))\n"
        RTPaths.write("\(RTPaths.reportDir)/ios-ak-rate/\(key.replacingOccurrences(of: "/", with: "__")).txt", line)
    }

    @Test("ITR30p table covers exactly the L30 cases")
    func tableCoversCases() throws {
        let table = try FirstAlarmTable.load()
        #expect(Set(table.map { "\($0.trace)/\($0.caseId)" }) == Set(Self.caseIds))
        // Counted from expect.json (T17.2.2: TR44 made it 13), every base trace read (a missing one fails, not skipped).
        var l30 = 0
        for id in RuntimeFixtures.baseTraces { l30 += RuntimeFixtures.l30Cases(try RuntimeFixtures.read(id)).count }
        #expect(l30 > 0 && Self.caseIds.count == l30 && table.count == l30)
    }
}

struct FirstAlarmRow: Sendable {
    let trace: String
    let caseId: String
    let reason: String?
    let atMsRel: Int64?
}

enum FirstAlarmTable {
    static func load() throws -> [FirstAlarmRow] {
        let data = try Data(contentsOf: URL(fileURLWithPath: RTPaths.runtimeDir + "/first-alarms.json"))
        let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return arr.map { o in
            FirstAlarmRow(trace: o["trace"] as? String ?? "", caseId: o["case"] as? String ?? "", reason: o["reason"] as? String,
                          atMsRel: (o["atMsRel"] as? NSNumber)?.int64Value)
        }
    }
}
