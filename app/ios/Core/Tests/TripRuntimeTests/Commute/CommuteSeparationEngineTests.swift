import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T23.8 CU28 (docs/specs/T23.8.md §5.6a, D12): the stationary alarm reach R(m) that CommuteRouteValidator computes from the
/// public EngineParams must match the real engine. Standing still at R + 50 m: no Alarm in 10 virtual minutes; at R − 50 m:
/// an Alarm within the first 5 s with the mode's reason. If the engine's rules change, this test turns red.
@Suite("T23.8 CU28 commute separation vs engine")
struct CommuteSeparationEngineTests {
    static let destLat = 21.0
    static let destLng = 105.8
    static let t0: Int64 = 1_800_000_000_000

    /// Expected reason at R − 50 m per row of CommuteUnitTests.reachTable.
    static let reasons: [String: AlarmReason] = [
        "distance 1000": .distance, "distance 3000 x 1.5": .distance,
        "time 5 bus": .time, "time 10 bus": .time, "time 15 bus": .time,
        "smart bus": .smartTime, "smart train": .smartTime, "smart coach": .smartTime, "smart unknown": .smartTime,
        "smart bus slow 25": .smartSlowDistance, "smart bus target 1200": .smartTime,
        "time 10 bus 5 km/h, no ETA": .time,
    ]

    /// Starts a trip with the template's own params and feeds 1 Hz stationary fixes (speed 0, accuracy 10 m) `distanceM`
    /// south of the destination for 10 minutes. Returns every Alarm event.
    static func alarms(_ m: TripMeta, distanceM: Double) throws -> [TripEvent.Alarm] {
        let params = EngineParamsFactory.fromOverrides(m.engineParamsJson)
        var step = try TripEngine.start(config: m.config(destLat: destLat, destLng: destLng), params: params, nowMs: t0)
        var out: [TripEvent.Alarm] = []
        func collect(_ s: Step) {
            for case let .alarm(a) in s.events { out.append(a) }
        }
        collect(step)
        // Same meridian: the engine's equirectangular distance is exactly dLat · metres per degree.
        let lat = destLat - distanceM / Geo.kMetresPerDegLat
        for i in 1...600 {
            let t = t0 + Int64(i) * 1_000
            let fix = LocationFix(atMs: t, fixAtMs: t, lat: lat, lng: destLng, accuracyM: 10, speedMps: 0)
            step = TripEngine.reduce(step.state, .locationFix(fix))
            collect(step)
        }
        return out
    }

    @Test("CU28 R + 50 m: no Alarm in 10 min standing still; R − 50 m: Alarm within 5 s with the mode's reason")
    func cu28() throws {
        #expect(CommuteUnitTests.reachTable.count >= 10)
        for (name, m, _, _) in CommuteUnitTests.reachTable {
            let r = CommuteRouteValidator.stationaryReachM(m)
            let far = try Self.alarms(m, distanceM: r + 50)
            #expect(far.isEmpty, "\(name): alarmed at R + 50 m (\(far.map(\.reason)))")
            let near = try Self.alarms(m, distanceM: r - 50)
            let first = try #require(near.first, "\(name): no Alarm at R − 50 m")
            #expect(first.atMs - Self.t0 <= 5_000, "\(name): first Alarm after \(first.atMs - Self.t0) ms")
            #expect(first.reason == Self.reasons[name], "\(name): reason \(first.reason)")
        }
    }
}
