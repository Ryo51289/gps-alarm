import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// Tester T18.1 (docs/test-reports/T18.1.md): edges outside the SIU table.
@Suite("TesterT181")
struct TesterT181Tests {
    typealias R = SimRuntimeTests

    /// A GPX of `n` samples every 5 s at `lat`, `lng` (synthetic, same schema as fixtures/traces).
    static func gpx(n: Int, lat: Double, lng: Double) -> Data {
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="tester" xmlns="http://www.topografix.com/GPX/1/1" xmlns:napstop="https://napstop.app/xmlns/trace/1">
          <trk><trkseg>

        """
        for i in 0..<n {
            let sec = String(format: "%02d", i * 5 % 60), min = String(format: "%02d", i * 5 / 60)
            s += "<trkpt lat=\"\(lat)\" lon=\"\(lng)\"><time>2026-03-14T01:\(min):\(sec)Z</time>"
            s += "<extensions><napstop:acc>8</napstop:acc><napstop:spd>15</napstop:spd></extensions></trkpt>\n"
        }
        s += "</trkseg></trk></gpx>\n"
        return Data(s.utf8)
    }

    @Test("Catch-up split into many commands (limit 3 events) with a 30 s late timer at 600×: same engine sequence as ITR30")
    func chunkedCatchUp() async throws {
        let trace = try RuntimeFixtures.read("bus_hn_brt01")
        let c = try #require(trace.cases.first { $0.id == "distance_1000" })
        let ref = await SimTraceTests.realRun(trace, c)
        var k = RuntimeConstants.default
        k.simCatchUpMaxEvents = 3
        let world = World(startWall: trace.startMs, constants: k, traces: FixtureTraceStore())
        await world.listen()
        #expect(await world.runtime.start(meta: SimFixtures.simMeta(trace, c, speed: 600), destLat: trace.destLat,
                                          destLng: trace.destLng) == .started)
        await world.settle()
        let end = trace.startMs + Int64(trace.durationS) * 1000
        let seen = world.seen
        await SimRun(world: world, seed: 7, maxJitterMs: 30_000).run(maxV: Int64(trace.durationS) * 1000 + 3_600_000) {
            seen.entries.contains { $0.view.atMs > end || $0.view.phase == .ended }
        }
        let lines = SimFixtures.transcript(world.seen.entries, startMs: trace.startMs, untilMs: end)
        #expect(world.journal.all.contains { $0.ev == "sim_catchup" && $0.fields["more"] == "true" }, "the catch-up was split")
        if let d = SimTraceTests.firstDifference(ref.lines, lines) {
            Issue.record(Comment(rawValue: "first difference vs ITR30 at \(d.text)"))
        }
        #expect(world.seen.firstAlarm()?.reason == .distance)
        world.sleeper.releaseAll()
        ref.world.sleeper.releaseAll()
    }

    @Test("Trace that ends far from the destination (3 samples, 30 km away) at 60×: the trip does not stall, a ring still comes")
    func traceEndsEarly() async {
        let store = FixtureTraceStore()
        let lat = TestData.destLat - 30 / 111.2
        store.extra["tester_short"] = Self.gpx(n: 3, lat: lat, lng: TestData.destLng)
        let w = World(traces: store)
        await w.listen()
        let meta = TestData.meta("s9").with(simulation: SimSpec(traceId: "tester_short", speedFactor: 60))
        #expect(await w.runtime.start(meta: meta, destLat: TestData.destLat, destLng: TestData.destLng) == .started)
        await w.settle()
        let seen = w.seen
        let alarms = w.alarms
        // 6 virtual hours at 60× = 6 real minutes.
        await SimRun(world: w).run(maxV: 6 * 60_000) {
            seen.firstAlarm()?.ringNow == true || alarms.scheduledRequests().contains { $0.kind == .fallback || $0.kind == .now }
        }
        let last = w.seen.entries.last?.view.atMs ?? 0
        #expect(last > w.startWall + 10_000, "the engine kept running after the trace ended")
        let rang = w.alarms.scheduledRequests().filter { $0.kind == .fallback || $0.kind == .now }
        #expect(!rang.isEmpty, "a system alarm was set to wake the user after the trace ran out")
        #expect(w.seen.events.contains { if case .gpsLost = $0 { return true }; return false }, "GPS lost after the trace")
        w.sleeper.releaseAll()
    }

    @Test("Single-sample trace: starts, delivers the sample once, then runs on engine wakes only")
    func singleSample() async {
        let store = FixtureTraceStore()
        store.extra["tester_one"] = Self.gpx(n: 1, lat: TestData.destLat - 0.5 / 111.2, lng: TestData.destLng)
        let w = World(traces: store)
        await w.listen()
        let meta = TestData.meta("s8").with(simulation: SimSpec(traceId: "tester_one", speedFactor: 10))
        #expect(await w.runtime.start(meta: meta, destLat: TestData.destLat, destLng: TestData.destLng) == .started)
        await w.settle()
        let seen = w.seen
        await SimRun(world: w).run(maxV: 120_000) { seen.firstAlarm() != nil }
        // 500 m from the destination with DISTANCE 1 000: the one sample makes the engine ring.
        #expect(w.seen.firstAlarm()?.reason == .distance)
        w.sleeper.releaseAll()
    }

    @Test("A second start while a simulated trip runs (real or simulated) is refused trip-active; the simulated trip goes on")
    func secondStartRefused() async {
        let w = await R.startedBus(speed: 60)
        let real = await w.runtime.start(meta: TestData.meta("t2"), destLat: TestData.destLat, destLng: TestData.destLng)
        #expect(real == .rejected(code: "trip-active", message: nil, details: nil))
        let sim2 = await w.runtime.start(meta: R.simMeta(tripId: "s2"), destLat: R.bus.destLat, destLng: R.bus.destLng)
        #expect(sim2 == .rejected(code: "trip-active", message: nil, details: nil))
        #expect(await w.runtime.current()?.meta.tripId == "s1")
        #expect(await w.runtime.current()?.meta.simulation?.speedFactor == 60)
        w.sleeper.releaseAll()
    }
}
