import Foundation
@testable import Trip
@testable import TripRuntime

/// Discrete-event driver of one runtime over a trace (port of TraceRun.kt, ITR30). Virtual 0 = GPX start. While the
/// location session runs, every GPX sample (5 s) is delivered at its time (Core Location ~1 Hz → FixThrottle in the
/// runtime); the in-process timer and system alarm transitions are delivered on time.
final class TraceRun: @unchecked Sendable {
    let world: World
    let trace: TraceCase
    private var idx = 0
    private(set) var fixesDelivered = 0
    /// Samples at t ≥ this are never delivered (simulated loss / process death).
    var dropFromT: Int?

    init(world: World, trace: TraceCase) {
        self.world = world
        self.trace = trace
    }

    func run(endT: Int, stopAtFirstAlarm: Bool = false, stopWhen: (() -> Bool)? = nil) async {
        let endV = Int64(endT) * 1000
        let samples = trace.samples
        while true {
            if stopAtFirstAlarm && world.seen.firstAlarm() != nil { return }
            if let s = stopWhen, s() { return }
            let v = world.time.v
            while idx < samples.count && Int64(samples[idx].t) * 1000 < v { idx += 1 }
            var sampleV: Int64?
            if world.location.isRunningNow, idx < samples.count, dropFromT.map({ samples[idx].t < $0 }) ?? true {
                sampleV = Int64(samples[idx].t) * 1000
            }
            let others = [world.timer.due?.v, world.alarms.nextTransitionV(wallBaseOffset: world.time.wallMs() - v)]
                .compactMap { $0 }
            let candidates = others + [sampleV].compactMap { $0 }
            guard let next = candidates.min(), next <= endV else {
                await world.advance(to: endV)
                return
            }
            await world.advance(to: next)
            if let s = sampleV, s == next, world.location.isRunningNow, world.time.v == s {
                let x = samples[idx]
                idx += 1
                fixesDelivered += 1
                await world.emit(RawFix(lat: x.lat, lng: x.lng, horizontalAccuracyM: x.accuracyM, speedMps: x.speedMps ?? -1,
                                        timestampWallMs: trace.startMs + Int64(x.t) * 1000))
            }
        }
    }
}

func eventName(_ e: TripEvent) -> String { e.fixtureName }

func matches(_ w: ExpectWindow, _ e: TripEvent) -> Bool {
    if eventName(e) != w.event { return false }
    if let r = w.reason { guard case let .alarm(a) = e, a.reason.jsonName == r else { return false } }
    if let rn = w.ringNow { guard case let .alarm(a) = e, a.ringNow == rn else { return false } }
    if let c = w.cause { guard case let .gpsLost(g) = e, g.cause.jsonName == c else { return false } }
    return true
}
