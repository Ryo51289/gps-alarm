import Foundation
import Testing
@testable import TripRuntime

/// Tester T17.1: `LastKnownMath` (Swift port) against the answers of the Kotlin original, read from
/// `fixtures/parity/last_known_math.json` (written by `LastKnownMathParityExportTest.kt`). Same inputs, same bits.
@Suite("T17.1 LastKnownMath parity with Kotlin")
struct LastKnownParityTests {
    static let file: String = URL(fileURLWithPath: RTPaths.tracesDir).deletingLastPathComponent()
        .appendingPathComponent("parity/last_known_math.json").path

    static func table() throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func double(_ hex: Any?) throws -> Double {
        let s = try #require(hex as? String)
        return Double(bitPattern: try #require(UInt64(s, radix: 16), "bad hex \(s)"))
    }

    static func hex(_ d: Double) -> String {
        let s = String(d.bitPattern, radix: 16)
        return String(repeating: "0", count: 16 - s.count) + s
    }

    @Test("roundForDisplay: every input of the Kotlin table gives the same bits")
    func round() throws {
        let rows = try #require(try Self.table()["roundForDisplay"] as? [[String: Any]])
        #expect(rows.count > 4_500)
        var mismatches: [String] = []
        for r in rows {
            let m = try Self.double(r["in"])
            let expected = try #require(r["out"] as? String)
            let mine = Self.hex(LastKnownMath.roundForDisplay(m))
            if mine != expected { mismatches.append("\(m): Swift \(mine) vs Kotlin \(expected)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(5))")
    }

    @Test("validPairs: same verdict as Kotlin for every list of the table")
    func pairs() throws {
        let rows = try #require(try Self.table()["validPairs"] as? [[String: Any]])
        #expect(rows.count >= 19)
        for r in rows {
            let list = try (try #require(r["in"] as? [Any])).map { try Self.double($0) }
            let expected = try #require(r["out"] as? Bool)
            #expect(LastKnownMath.validPairs(list) == expected, "\(list.prefix(4)) count \(list.count)")
        }
    }

    /// A probe that hands out the cached fix whatever the permission (the real `PermissionProbe` hides it): the
    /// permission check of `LastKnownMath.usableFix` must hold on its own.
    final class LeakyProbe: PermissionProbing, @unchecked Sendable {
        let fix: RawFix
        let authorized: Bool
        let services: Bool
        init(fix: RawFix, authorized: Bool, services: Bool) {
            self.fix = fix
            self.authorized = authorized
            self.services = services
        }
        func readings() async -> PermissionReadings {
            PermissionReadings(location: .denied, accuracy: .full, servicesEnabled: services, notifications: .denied,
                               alarmKit: .unavailable)
        }
        func requestLocation(timeoutMs: Int64) async {}
        func requestNotifications() async {}
        func requestAlarmKit() async {}
        func lastKnown() async -> (fix: RawFix?, authorized: Bool, servicesEnabled: Bool) { (fix, authorized, services) }
        func distancesM(from fix: RawFix, to pairs: [Double]) -> [Double] { [1_234] }
    }

    @Test("distances: no permission or location off gives nil even when the platform still returns a cached fix")
    func noPermissionNeverMeasures() async {
        let now: Int64 = 1_700_000_000_000
        let fix = RawFix(lat: 17.48, lng: 106.6, horizontalAccuracyM: 10, speedMps: -1, timestampWallMs: now)
        let pairs = [17.4689199, 106.5997285]
        func run(_ authorized: Bool, _ services: Bool) async -> [Double]? {
            await LastKnownMath.distances(pairs, maxAgeMs: 600_000,
                                          probe: LeakyProbe(fix: fix, authorized: authorized, services: services),
                                          nowWallMs: { now })
        }
        #expect(await run(true, true) == [1_200])
        #expect(await run(false, true) == nil)
        #expect(await run(true, false) == nil)
        #expect(await run(false, false) == nil)
    }

    @Test("isFresh (wall ms) = Kotlin freshest (elapsed ns) for the same age and limit")
    func fresh() throws {
        let rows = try #require(try Self.table()["fresh"] as? [[String: Any]])
        #expect(rows.count == 75)
        let now: Int64 = 1_700_000_000_000
        for r in rows {
            let age = try #require((r["ageMs"] as? NSNumber)?.int64Value)
            let max = try #require((r["maxAgeMs"] as? NSNumber)?.int64Value)
            let expected = try #require(r["fresh"] as? Bool)
            #expect(LastKnownMath.isFresh(fixWallMs: now - age, nowWallMs: now, maxAgeMs: max) == expected,
                    "age \(age) max \(max)")
        }
    }
}
