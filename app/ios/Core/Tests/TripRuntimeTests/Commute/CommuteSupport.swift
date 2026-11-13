import Foundation
@testable import Trip
@testable import TripRuntime

/// Builders and JSON helpers for the T23.8 commute tests (fixtures/commute/README.md).
enum CS {
    static let ring = RingSettings(soundId: "default", volume: 0.8, rampUp: true, vibration: "medium", flash: false,
                                   preferHeadphones: false, dismissMethod: "button")

    static func template(_ name: String, mode: AlarmMode = .distance, distanceM: Int? = 1000, timeMin: Int? = nil,
                         tripId: String = "commute-template", vehicle: VehicleKind = .bus,
                         params: String? = nil) -> TripMeta {
        TripMeta(tripId: tripId, destinationName: name, mode: mode, distanceThresholdM: distanceM, timeThresholdMin: timeMin,
                 preAlertEnabled: true, vehicleHint: vehicle, alarm: ring, engineParamsJson: params)
    }

    static func window(_ start: Int = 420, _ end: Int = 480, mask: Int = CommuteWindow.weekdays,
                       enabled: Bool = true) -> CommuteWindow {
        CommuteWindow(enabled: enabled, startMinute: start, endMinute: end, weekdayMask: mask)
    }

    /// A ≈ 5 km south of B on the same meridian (synthetic points).
    static func route(revision: Int = 1, enabled: Bool = true, towardB: CommuteWindow = window(),
                      towardA: CommuteWindow = window(1050, 1170), bLat: Double = 21.045,
                      templateB: TripMeta = template("Trạm B"), templateA: TripMeta = template("Trạm A")) -> CommuteRoute {
        CommuteRoute(revision: revision, enabled: enabled, nameA: "Trạm A", nameB: "Trạm B", aLat: 21.0, aLng: 105.8,
                     bLat: bLat, bLng: 105.8, towardB: towardB, towardA: towardA, templateTowardB: templateB,
                     templateTowardA: templateA)
    }

    static let fullAccess = LocationAccess(whenInUseOrAlways: true, fullAccuracy: true, servicesEnabled: true, always: true)

    static func ctx(now: Int64, offsetS: Int = 7 * 3600, access: LocationAccess = fullAccess, tripActive: Bool = false,
                    osSupported: Bool = true) -> TriggerContext {
        TriggerContext(nowWallMs: now, utcOffsetS: offsetS, access: access, tripActive: tripActive, osSupported: osSupported)
    }

    /// Wall ms of an ISO 8601 date with offset, whole seconds ("2026-11-17T07:30:00+07:00").
    static func ms(_ iso: String) -> Int64 {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else { fatalError("bad ISO date \(iso)") }
        return Int64((d.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: JSON

    static func load(_ file: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: RTPaths.repoRoot + "/fixtures/commute/" + file)
        let data = try Data(contentsOf: url)
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { fatalError("\(file): not an object") }
        return o
    }

    /// Objects on both sides merge recursively; anything else in `over` replaces.
    static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var r = base
        for (k, v) in over {
            if let b = r[k] as? [String: Any], let o = v as? [String: Any] { r[k] = deepMerge(b, o) } else { r[k] = v }
        }
        return r
    }

    static func shallowMerge(_ base: [String: Any], _ over: [String: Any]?) -> [String: Any] {
        var r = base
        for (k, v) in over ?? [:] { r[k] = v }
        return r
    }

    /// Whole JSON numbers only: 420.5 is nil (not truncated), so a mistyped fixture fails here as it would in Kotlin/Dart.
    static func int(_ o: Any?) -> Int? {
        if let d = o as? Double {
            guard d.isFinite, d == d.rounded(.towardZero), abs(d) <= 9_007_199_254_740_992 else { return nil }
            return Int(d)
        }
        return o as? Int
    }

    static func int64(_ o: Any?) -> Int64? { int(o).map(Int64.init) }

    static func dbl(_ o: Any?) -> Double {
        if let d = o as? Double { return d }
        if let i = o as? Int { return Double(i) }
        return (o as? NSNumber)?.doubleValue ?? .nan
    }
    static func bool(_ o: Any?, _ dflt: Bool = false) -> Bool { (o as? Bool) ?? dflt }
    static func str(_ o: Any?) -> String? { o as? String }

    static func windowJ(_ o: Any?) -> CommuteWindow {
        let w = o as? [String: Any] ?? [:]
        return CommuteWindow(enabled: bool(w["enabled"]), startMinute: int(w["startMinute"]) ?? -999,
                             endMinute: int(w["endMinute"]) ?? -999, weekdayMask: int(w["weekdayMask"]) ?? -999)
    }

    static func templateJ(_ o: Any?) -> TripMeta {
        let t = o as? [String: Any] ?? [:]
        let modes: [String: AlarmMode] = ["distance": .distance, "time": .time, "smart": .smart]
        let vehicles: [String: VehicleKind] = ["train": .train, "coach": .coach, "bus": .bus, "unknown": .unknown]
        let alarm = RingSettings(soundId: str(t["soundId"]) ?? "", volume: dbl(t["volume"]), rampUp: true, vibration: "medium",
                                 flash: false, preferHeadphones: false, dismissMethod: "button")
        return TripMeta(tripId: str(t["tripId"]) ?? "", destinationName: str(t["destinationName"]) ?? "",
                        mode: modes[str(t["mode"]) ?? ""] ?? .smart, distanceThresholdM: int(t["distanceThresholdM"]),
                        timeThresholdMin: int(t["timeThresholdMin"]), preAlertEnabled: bool(t["preAlertEnabled"]),
                        vehicleHint: vehicles[str(t["vehicleHint"]) ?? ""] ?? .unknown, alarm: alarm,
                        engineParamsJson: str(t["engineParamsJson"]))
    }

    /// Full route (validation_cases.json) or trigger route without coordinates (trigger_cases.json: defaults filled in).
    static func routeJ(_ r: [String: Any]) -> CommuteRoute {
        CommuteRoute(revision: int(r["revision"]) ?? 0, enabled: bool(r["enabled"]), nameA: str(r["nameA"]) ?? "Trạm A",
                     nameB: str(r["nameB"]) ?? "Trạm B", aLat: r["aLat"] == nil ? 21.0 : dbl(r["aLat"]),
                     aLng: r["aLng"] == nil ? 105.8 : dbl(r["aLng"]), bLat: r["bLat"] == nil ? 21.045 : dbl(r["bLat"]),
                     bLng: r["bLng"] == nil ? 105.8 : dbl(r["bLng"]), towardB: windowJ(r["towardB"]),
                     towardA: windowJ(r["towardA"]),
                     templateTowardB: r["templateTowardB"] == nil ? template("Trạm B") : templateJ(r["templateTowardB"]),
                     templateTowardA: r["templateTowardA"] == nil ? template("Trạm A") : templateJ(r["templateTowardA"]))
    }

    static func pointMap<T>(_ o: Any?, _ f: (Any) -> T?) -> [CommutePoint: T] {
        var r: [CommutePoint: T] = [:]
        for (k, v) in o as? [String: Any] ?? [:] {
            guard let p = CommutePoint(rawValue: k), let x = f(v) else { fatalError("bad point map entry \(k)") }
            r[p] = x
        }
        return r
    }

    static func stateJ(_ s: [String: Any]) -> CommuteState {
        CommuteState(revision: int(s["revision"]) ?? 0,
                     lastState: pointMap(s["lastState"]) { RegionState(rawValue: $0 as? String ?? "") },
                     lastEventAtMs: pointMap(s["lastEventAtMs"]) { int64($0) },
                     firedKeys: s["firedKeys"] as? [String] ?? [])
    }
}
