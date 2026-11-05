import Foundation
import Testing
@testable import TripRuntime

/// T17.1 PU01–PU06 (docs/specs/T17.1.md): permission mapping of T21 §9, LastKnownMath (parity with the Kotlin
/// `LastKnownMathTest`), the request gate, the distances pipeline on a fake probe, and a privacy scan.
@Suite("T17.1 Permissions")
struct PermissionsTests {
    static let akCases: [AlarmKitAuth] = [.unavailable, .notDetermined, .denied, .authorized]

    static func every() -> [PermissionReadings] {
        var out: [PermissionReadings] = []
        for l in LocationAuthRaw.allCases {
            for a in AccuracyRaw.allCases {
                for s in [false, true] {
                    for n in NotificationAuthRaw.allCases {
                        for k in akCases {
                            out.append(PermissionReadings(location: l, accuracy: a, servicesEnabled: s, notifications: n, alarmKit: k))
                        }
                    }
                }
            }
        }
        return out
    }

    // The table of T21 §9, written out (not computed by the code under test).
    static let locationTable: [LocationAuthRaw: LocationAccessDTO] = [
        .notDetermined: .notDetermined, .restricted: .denied, .denied: .denied, .whenInUse: .whileInUse, .always: .always,
    ]
    static let notificationTable: [NotificationAuthRaw: PermissionStateDTO] = [
        .notDetermined: .notDetermined, .denied: .denied, .authorized: .granted, .provisional: .denied, .ephemeral: .granted,
    ]
    static func alarmKitExpected(_ a: AlarmKitAuth) -> PermissionStateDTO {
        switch a {
        case .unavailable: .notApplicable
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .granted
        }
    }

    @Test("PU01 PermissionMapper: every one of the 400 readings maps cell by cell (T21 §9)")
    func pu01() {
        let all = Self.every()
        #expect(all.count == 400)
        #expect(Set(all.map { "\($0)" }).count == 400)
        for r in all {
            let s = PermissionMapper.status(r)
            #expect(s.location == Self.locationTable[r.location], "\(r)")
            let granted = r.location == .whenInUse || r.location == .always
            let precise: PermissionStateDTO = granted ? (r.accuracy == .full ? .granted : .denied) : .notDetermined
            #expect(s.precise == precise, "\(r)")
            #expect(s.precise != .notApplicable)
            #expect(s.locationServicesEnabled == r.servicesEnabled)
            #expect(s.notifications == Self.notificationTable[r.notifications], "\(r)")
            #expect(s.alarmKit == Self.alarmKitExpected(r.alarmKit), "\(r)")
            #expect((s.alarmKit == .notApplicable) == (r.alarmKit == .unavailable))
            #expect(s.fullScreenIntent == .notApplicable)
            #expect(s.exactAlarm == .notApplicable)
            #expect(s.batteryOptimizationIgnored == .notApplicable)
        }
    }

    @Test("PU01 DTO names are the Pigeon case names")
    func pu01Names() {
        #expect(LocationAccessDTO.whileInUse.rawValue == "whileInUse")
        #expect(PermissionStateDTO.notApplicable.rawValue == "notApplicable")
    }

    @Test("PU02 validPairs (same cases as LastKnownMathTest.kt)")
    func pu02() {
        let valid100 = (0..<50).flatMap { i in [Double(i) - 25, Double(i) * 3 - 75] }
        #expect(valid100.count == 100)
        let cases: [([Double], Bool)] = [
            ([], false),
            ([16.0], false),
            (Array(repeating: 10.0, count: 101), false),
            (valid100, true),
            ([Double.nan, 0], false),
            ([0, Double.infinity], false),
            ([90.0001, 0], false),
            ([0, -180], true),
            ([0, 180.0001], false),
        ]
        for (p, ok) in cases {
            #expect(LastKnownMath.validPairs(p) == ok, "\(p.prefix(4)) count \(p.count)")
        }
        #expect(LastKnownMath.validPairs([90, 180, -90, -180]))
        #expect(!LastKnownMath.validPairs(Array(repeating: 10.0, count: 102)))
        #expect(LastKnownMath.maxNumbers == 100)
    }

    @Test("PU03 roundForDisplay (same values as Kotlin)")
    func pu03() {
        let cases: [(Double, Double)] = [
            (-1, 0), (0, 0), (.nan, 0), (.infinity, 0), (4, 0), (5, 10), (994, 990), (995, 1_000), (999.9, 1_000),
            (1_049, 1_000), (1_050, 1_100), (12_345, 12_300),
        ]
        for (m, r) in cases {
            #expect(LastKnownMath.roundForDisplay(m) == r, "\(m)")
        }
    }

    @Test("PU04 isFresh: future, 0, maxAge, maxAge + 1")
    func pu04() {
        let now: Int64 = 1_700_000_000_000, max: Int64 = 600_000
        #expect(LastKnownMath.isFresh(fixWallMs: now + 5_000, nowWallMs: now, maxAgeMs: max))
        #expect(LastKnownMath.isFresh(fixWallMs: now, nowWallMs: now, maxAgeMs: max))
        #expect(LastKnownMath.isFresh(fixWallMs: now - max, nowWallMs: now, maxAgeMs: max))
        #expect(!LastKnownMath.isFresh(fixWallMs: now - max - 1, nowWallMs: now, maxAgeMs: max))
        #expect(!LastKnownMath.isFresh(fixWallMs: Int64.min, nowWallMs: Int64.max, maxAgeMs: max))
    }

    @Test("PU05 one source of truth with the T17 runtime (LocationAccess, ChannelAccess)")
    func pu05() {
        for r in Self.every() {
            let s = PermissionMapper.status(r)
            let loc = r.locationAccess, ch = r.channelAccess
            #expect((s.location == .whileInUse || s.location == .always) == loc.whenInUseOrAlways, "\(r)")
            if loc.whenInUseOrAlways {
                #expect((s.precise == .granted) == loc.fullAccuracy, "\(r)")
            }
            #expect(loc.servicesEnabled == s.locationServicesEnabled)
            #expect((s.notifications == .granted) == ch.notifications, "\(r)")
            #expect(ch.alarmKit == r.alarmKit)
        }
        // Provisional is "no" on both sides.
        let p = PermissionReadings(location: .whenInUse, accuracy: .full, servicesEnabled: true, notifications: .provisional,
                                   alarmKit: .unavailable)
        #expect(!p.channelAccess.notifications && PermissionMapper.status(p).notifications == .denied)
    }

    @Test("Request gate: one prompt at a time, free again afterwards")
    func gate() {
        let g = PermissionRequestGate()
        #expect(g.tryEnter())
        #expect(!g.tryEnter())
        g.leave()
        #expect(g.tryEnter())
        g.leave()
        #expect(PermissionConstants.promptTimeoutMs == 60_000)
    }

    @Test("distancesFromLastKnownM pipeline: input, permission, services, freshness, invalid fix, rounding")
    func distances() async {
        let now: Int64 = 1_700_000_000_000
        let fix = RawFix(lat: 16.46, lng: 107.59, horizontalAccuracyM: 20, speedMps: -1, timestampWallMs: now - 1_000)
        let pairs = [17.47, 106.60, 16.46, 107.60]
        func run(_ p: FakeProbe, _ pairs: [Double], maxAge: Int64 = 600_000) async -> [Double]? {
            await LastKnownMath.distances(pairs, maxAgeMs: maxAge, probe: p, nowWallMs: { now })
        }
        let ok = FakeProbe(fix: fix, distances: [123_456.7, 1_064])
        #expect(await run(ok, pairs) == [123_500, 1_100])
        #expect(ok.lastKnownCalls == 1)
        // Invalid input: the position is not even read.
        let untouched = FakeProbe(fix: fix, distances: [1])
        #expect(await run(untouched, [91, 0]) == nil)
        #expect(await run(untouched, []) == nil)
        #expect(await run(untouched, [1, 2], maxAge: 0) == nil)
        #expect(untouched.lastKnownCalls == 0)
        #expect(await run(FakeProbe(fix: fix, authorized: false, distances: [1, 2]), pairs) == nil)
        #expect(await run(FakeProbe(fix: fix, services: false, distances: [1, 2]), pairs) == nil)
        #expect(await run(FakeProbe(fix: nil, distances: [1, 2]), pairs) == nil)
        let old = RawFix(lat: 16.46, lng: 107.59, horizontalAccuracyM: 20, speedMps: -1, timestampWallMs: now - 600_001)
        #expect(await run(FakeProbe(fix: old, distances: [1, 2]), pairs) == nil)
        let invalid = RawFix(lat: 16.46, lng: 107.59, horizontalAccuracyM: -1, speedMps: -1, timestampWallMs: now)
        #expect(await run(FakeProbe(fix: invalid, distances: [1, 2]), pairs) == nil)
        // Wrong count from the platform → nil, never a shifted list.
        #expect(await run(FakeProbe(fix: fix, distances: [1]), pairs) == nil)
    }

    @Test("PU06 privacy scan: PermissionProbe, IOSPermissionHostApi, BackupExclusion log no position or distance")
    func pu06() throws {
        let files = [
            "\(RTPaths.packageDir)/Sources/NapStopIOS/PermissionProbe.swift",
            "\(RTPaths.packageDir)/Sources/NapStopIOS/BackupExclusion.swift",
            "\(RTPaths.repoRoot)/app/ios/Runner/Bridge/IOSPermissionHostApi.swift",
            "\(RTPaths.packageDir)/Sources/TripRuntime/Permissions.swift",
        ]
        let banned = ["lat", "lng", "latitude", "longitude", "distance", "meters", "pairs", "fix", "coordinate"]
        for f in files {
            let text = try String(contentsOfFile: f, encoding: .utf8)
            for call in ["print(", "NSLog(", "debugPrint(", "dump(", "os_log("] {
                #expect(!text.contains(call), "\(f): \(call)")
            }
            for line in text.split(separator: "\n") where line.contains("logger.") || line.contains("journal.record") {
                let lower = line.lowercased()
                for word in banned {
                    #expect(!lower.contains(word), "\(f): log line mentions \(word): \(line)")
                }
            }
        }
    }
}

/// Fake `PermissionProbing` for the distances pipeline.
final class FakeProbe: Locked, PermissionProbing, @unchecked Sendable {
    let fix: RawFix?
    let authorized: Bool
    let services: Bool
    let out: [Double]
    private var calls = 0
    var lastKnownCalls: Int { locked { calls } }

    init(fix: RawFix?, authorized: Bool = true, services: Bool = true, distances: [Double]) {
        self.fix = fix
        self.authorized = authorized
        self.services = services
        self.out = distances
    }

    func readings() async -> PermissionReadings {
        PermissionReadings(location: .whenInUse, accuracy: .full, servicesEnabled: services, notifications: .authorized,
                           alarmKit: .unavailable)
    }

    func requestLocation(timeoutMs: Int64) async {}
    func requestNotifications() async {}
    func requestAlarmKit() async {}

    func lastKnown() async -> (fix: RawFix?, authorized: Bool, servicesEnabled: Bool) {
        locked { calls += 1 }
        return (authorized ? fix : nil, authorized, services)
    }

    func distancesM(from fix: RawFix, to pairs: [Double]) -> [Double] { out }
}
