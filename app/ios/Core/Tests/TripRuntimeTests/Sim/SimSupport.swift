import Foundation
@testable import Trip
@testable import TripRuntime

/// Fixture GPX files as the bundled assets (app/assets/sim holds byte copies, T18 `bundle-sim`). `extra` adds synthetic
/// traces; `hold` blocks `open` until signalled (SIU11 timeout).
final class FixtureTraceStore: Locked, TraceStore, @unchecked Sendable {
    var extra: [String: Data] = [:]
    var hold: DispatchSemaphore?
    private var opened: [String] = []

    var opens: [String] { locked { opened } }

    func open(_ traceId: String) -> Data? {
        let h: DispatchSemaphore? = locked {
            opened.append(traceId)
            return hold
        }
        h?.wait()
        if let d = locked({ extra[traceId] }) { return d }
        return try? Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.tracesDir)/\(traceId).gpx"))
    }
}

/// Deterministic generator for the timer jitter of SIU10.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Drives one world with a simulated trip on virtual real time: system alarm transitions on time, the in-process timer
/// `jitter` ms late (random in [0, maxJitterMs] per arming when a seed is given, T18.2: a late timer).
final class SimRun: @unchecked Sendable {
    let world: World
    private var rng: SplitMix64?
    let maxJitterMs: Int64
    private var armed: (gen: Int64, v: Int64, at: Int64)?
    private(set) var timerDeliveries = 0

    init(world: World, seed: UInt64? = nil, maxJitterMs: Int64 = 0) {
        self.world = world
        rng = seed.map { SplitMix64(seed: $0) }
        self.maxJitterMs = maxJitterMs
    }

    /// Runs until `stop` is true or virtual real time would pass `maxV`.
    func run(maxV: Int64, stop: () -> Bool) async {
        var spins = 0
        while !stop(), spins < 2_000_000 {
            spins += 1
            var timerAt: Int64?
            if let d = world.timer.due {
                if armed?.gen != d.gen || armed?.v != d.v {
                    let j = maxJitterMs > 0 ? Int64((rng?.next() ?? 0) % UInt64(maxJitterMs + 1)) : 0
                    armed = (d.gen, d.v, d.v + j)
                }
                timerAt = max(armed!.at, world.time.v)
            }
            let alarmAt = world.alarms.nextTransitionV(wallBaseOffset: world.time.wallMs() - world.time.v)
            guard let next = [timerAt, alarmAt].compactMap({ $0 }).min(), next <= maxV else {
                if maxV > world.time.v { world.time.v = maxV }
                world.alarms.tick()
                await world.settle()
                return
            }
            if next > world.time.v { world.time.v = next }
            world.alarms.tick()
            await world.settle()
            if let d = world.timer.due, let a = armed, a.gen == d.gen, a.at <= world.time.v {
                world.timer.consume()
                armed = nil
                timerDeliveries += 1
                await world.runtime.onTimer(generation: d.gen)
                await world.settle()
            }
        }
    }
}

enum SimFixtures {
    static func simMeta(_ t: TraceCase, _ c: ExpectCase, speed: Double) -> TripMeta {
        RuntimeFixtures.meta(t, c).with(simulation: SimSpec(traceId: t.traceId, speedFactor: speed))
    }

    /// One line per Step (Publish): trip s.ms of the view, phase, events with their own time and alarm reason.
    static func transcript(_ entries: [Seen.Entry], startMs: Int64, untilMs: Int64) -> [String] {
        entries.filter { $0.view.atMs <= untilMs }.map { e in
            let ev = e.events.map { x -> String in
                var s = "\(x.fixtureName)@\(x.atMs - startMs)"
                if case let .alarm(a) = x { s += "[\(a.reason.jsonName),\(a.ringNow)]" }
                if case let .gpsLost(g) = x { s += "[\(g.cause.jsonName)]" }
                return s
            }
            return "\(e.view.atMs - startMs) \(e.view.phase.jsonName) \(ev.joined(separator: " "))"
        }
    }
}
