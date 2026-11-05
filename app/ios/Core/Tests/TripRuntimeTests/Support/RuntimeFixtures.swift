import Foundation
@testable import Trip
@testable import TripRuntime

/// Paths (fixtures/traces, fixtures/runtime, ARB, report dir), found from #filePath like TripTests.FixturePaths.
enum RTPaths {
    static let repoRoot: String = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("fixtures/traces/README.md").path) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return "."
    }()

    static var tracesDir: String {
        if let env = ProcessInfo.processInfo.environment["NAPSTOP_FIXTURES_DIR"], !env.isEmpty { return env }
        return repoRoot + "/fixtures/traces"
    }

    static var runtimeDir: String { URL(fileURLWithPath: tracesDir).deletingLastPathComponent().appendingPathComponent("runtime").path }
    static var l10nDir: String { repoRoot + "/app/lib/l10n" }
    static var packageDir: String { repoRoot + "/app/ios/Core" }

    static let reportDir: String = {
        if let env = ProcessInfo.processInfo.environment["NAPSTOP_REPORT_DIR"], !env.isEmpty { return env }
        return packageDir + "/.build/napstop-report"
    }()

    static func write(_ path: String, _ content: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct GpxSample: Sendable {
    let t: Int
    let lat: Double
    let lng: Double
    let accuracyM: Double
    let speedMps: Double?
}

struct ExpectWindow: Sendable {
    let event: String
    let reason: String?
    let ringNow: Bool?
    let cause: String?
    let notBefore: Int
    let notAfter: Int
}

struct ExpectCase: Sendable {
    let id: String
    let status: String
    let mode: String
    let thresholdM: Int?
    let thresholdMin: Int?
    let preAlert: Bool
    let vehicleHint: String?
    let excludedKeys: [String]
    let osRingMaxS: Int?
    let expect: [ExpectWindow]
    let forbid: [String]
    let expectOutcome: String?
}

struct TraceCase: Sendable {
    let traceId: String
    let vehicle: String
    let intervalS: Int
    let durationS: Int
    let destLat: Double
    let destLng: Double
    let startMs: Int64
    let samples: [GpxSample]
    let cases: [ExpectCase]
    let arrivalT: Int
}

/// Port of ExpectReader.kt (T15) on Foundation; GPX by string scanning (XMLParser needs libxml2 on Linux).
enum RuntimeFixtures {
    static let baseTraces = ["train_hn_dh", "coach_md_tb", "bus_hn_brt01", "coach_dn_langco_tunnel", "coach_gb_phuly_overshoot",
                             "bus_hn_brt01_noisy"]

    private static func num(_ x: Any?) -> NSNumber? { x as? NSNumber }

    static func read(_ traceId: String) throws -> TraceCase {
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.tracesDir)/\(traceId).expect.json"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trace = root["trace"] as? [String: Any], let dest = root["destination"] as? [String: Any],
              let truth = root["truth"] as? [String: Any], let cases = root["cases"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var out: [ExpectCase] = []
        for c in cases {
            let cfg = c["config"] as? [String: Any] ?? [:]
            var excluded = ["kill", "relaunch", "osDismiss", "params", "battery", "actions"].filter { cfg[$0] != nil }
            if c["killSweep"] != nil { excluded.append("killSweep") }
            let windows = (c["expect"] as? [[String: Any]] ?? []).map { e in
                ExpectWindow(event: e["event"] as? String ?? "", reason: e["reason"] as? String,
                             ringNow: num(e["ringNow"])?.boolValue, cause: e["cause"] as? String,
                             notBefore: num(e["notBefore"])?.intValue ?? 0, notAfter: num(e["notAfter"])?.intValue ?? 0)
            }
            out.append(ExpectCase(
                id: c["id"] as? String ?? "", status: c["status"] as? String ?? "", mode: cfg["mode"] as? String ?? "",
                thresholdM: num(cfg["thresholdM"])?.intValue, thresholdMin: num(cfg["thresholdMin"])?.intValue,
                preAlert: num(cfg["preAlert"])?.boolValue ?? false, vehicleHint: cfg["vehicleHint"] as? String,
                excludedKeys: excluded, osRingMaxS: num(cfg["osRingMaxS"])?.intValue, expect: windows,
                forbid: c["forbid"] as? [String] ?? [], expectOutcome: c["expectOutcome"] as? String))
        }
        let gpxName = trace["gpx"] as? String ?? "\(traceId).gpx"
        let gpxText = try String(contentsOfFile: "\(RTPaths.tracesDir)/\(gpxName)", encoding: .utf8)
        let (startMs, samples) = try readGpx(gpxText)
        return TraceCase(traceId: trace["id"] as? String ?? traceId, vehicle: trace["vehicle"] as? String ?? "unknown",
                         intervalS: num(trace["sampleIntervalS"])?.intValue ?? 5, durationS: num(trace["durationS"])?.intValue ?? 0,
                         destLat: num(dest["lat"])?.doubleValue ?? 0, destLng: num(dest["lng"])?.doubleValue ?? 0,
                         startMs: startMs, samples: samples, cases: out, arrivalT: num(truth["arrivalT"])?.intValue ?? 0)
    }

    static func l30Cases(_ t: TraceCase) -> [ExpectCase] { t.cases.filter { $0.status == "final" && $0.excludedKeys.isEmpty } }

    static func meta(_ t: TraceCase, _ c: ExpectCase) -> TripMeta {
        let raw = "\(t.traceId)-\(c.id)"
        let id = String(String(raw.unicodeScalars.map { s -> Character in
            let ok = (s >= "A" && s <= "Z") || (s >= "a" && s <= "z") || (s >= "0" && s <= "9") || s == "_" || s == "-"
            return ok ? Character(s) : "_"
        }).prefix(64))
        let mode: AlarmMode = c.mode == "distance" ? .distance : c.mode == "time" ? .time : .smart
        let vehicle: VehicleKind
        switch c.vehicleHint ?? t.vehicle {
        case "train": vehicle = .train
        case "coach": vehicle = .coach
        case "bus": vehicle = .bus
        default: vehicle = .unknown
        }
        return TripMeta(tripId: id, destinationName: "Đích thử", mode: mode, distanceThresholdM: c.thresholdM,
                        timeThresholdMin: c.thresholdMin, preAlertEnabled: c.preAlert, vehicleHint: vehicle,
                        alarm: TestData.settings, engineParamsJson: nil)
    }

    // MARK: GPX (fixed tracegen format, README §2)

    static func readGpx(_ text: String) throws -> (Int64, [GpxSample]) {
        let b = Array(text.utf8)
        var raw: [(Int64, Double, Double, Double, Double?)] = []
        var pos = 0
        let open = Array("<trkpt ".utf8), close = Array("</trkpt>".utf8)
        while let start = find(b, open, pos) {
            guard let end = find(b, close, start) else { throw CocoaError(.fileReadCorruptFile) }
            let el = Array(b[start..<end])
            guard let lat = attr(el, "lat").flatMap(Double.init), let lon = attr(el, "lon").flatMap(Double.init),
                  let time = tag(el, "time"), let acc = tag(el, "napstop:acc").flatMap(Double.init) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            raw.append((try isoMs(time), lat, lon, acc, tag(el, "napstop:spd").flatMap(Double.init)))
            pos = end + close.count
        }
        guard let first = raw.first else { throw CocoaError(.fileReadCorruptFile) }
        return (first.0, raw.map { GpxSample(t: Int(($0.0 - first.0) / 1000), lat: $0.1, lng: $0.2, accuracyM: $0.3, speedMps: $0.4) })
    }

    private static func find(_ hay: [UInt8], _ needle: [UInt8], _ from: Int) -> Int? {
        var i = from
        while i + needle.count <= hay.count {
            if hay[i] == needle[0] {
                var ok = true
                for k in 1..<needle.count where hay[i + k] != needle[k] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }

    private static func attr(_ el: [UInt8], _ name: String) -> String? {
        let key = Array(" \(name)=\"".utf8)
        guard let i = find(el, key, 0) else { return nil }
        var e = i + key.count
        while e < el.count && el[e] != 0x22 { e += 1 }
        return String(decoding: el[(i + key.count)..<e], as: UTF8.self)
    }

    private static func tag(_ el: [UInt8], _ name: String) -> String? {
        let o = Array("<\(name)>".utf8), c = Array("</\(name)>".utf8)
        guard let i = find(el, o, 0), let j = find(el, c, i) else { return nil }
        return String(decoding: el[(i + o.count)..<j], as: UTF8.self)
    }

    /// YYYY-MM-DDTHH:MM:SSZ → epoch ms.
    static func isoMs(_ s: String) throws -> Int64 {
        let b = Array(s.utf8)
        guard b.count == 20 else { throw CocoaError(.fileReadCorruptFile) }
        func n(_ f: Int, _ l: Int) -> Int64 { var v: Int64 = 0; for i in f..<(f + l) { v = v * 10 + Int64(b[i] - 0x30) }; return v }
        let y0 = n(0, 4), m = n(5, 2), d = n(8, 2)
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
        return (days * 86400 + n(11, 2) * 3600 + n(14, 2) * 60 + n(17, 2)) * 1000
    }
}
