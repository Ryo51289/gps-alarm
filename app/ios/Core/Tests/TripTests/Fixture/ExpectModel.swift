import Foundation
@testable import Trip

/// expect.json model (README §3, §5). Trace level is parsed leniently (unknown keys ignored); every object inside
/// `cases[i]` is must-understand: an unknown key fails that case with the exact key path.
struct ModelError: Error, CustomStringConvertible, Equatable {
    let description: String
}

struct At: Sendable, Equatable {
    let t: Int?
    let anchor: String?
    let offsetS: Int
}

struct EventFilter: Sendable, Equatable {
    let event: String
    let reason: String?
    let ringNow: Bool?
    let cause: String?
}

struct ExpectItem: Sendable { let filter: EventFilter; let notBefore: Int; let notAfter: Int }
struct ExpectAfterItem: Sendable { let filter: EventFilter; let after: At; let lo: Int; let hi: Int }
struct ExpectFallbackSpec: Sendable { let asOfT: Int; let notBefore: Int; let notAfter: Int }
struct KillSweepSpec: Sendable { let from: At; let everyS: Int; let notAfter: At; let earlyFrom: At; let statsOnly: Bool }
struct ForbidAfterItem: Sendable { let filter: EventFilter; let after: At }

struct CaseConfig: Sendable {
    let mode: String
    let thresholdM: Int?
    let thresholdMin: Int?
    let preAlert: Bool
    let vehicleHint: String?
    let params: [(String, JsonValue)]
    let battery: [(t: Int, levelPct: Int, charging: Bool)]
    let actions: [(at: At, action: String)]
    let kill: At?
    let relaunch: (at: At, status: String)?
    let osDismissOffsetS: Int?
    let osSim: Bool
    let osRingMaxS: Int?
}

struct CaseSpec: Sendable {
    let id: String
    let testIds: [String]
    let config: CaseConfig
    let samplingModes: [String]?
    let policyPhaseSweep: Bool
    /// T10.3: P02 is not checked for this case (V14–V16 in T11.2 §3).
    let allowFallbackFirst: Bool
    let expect: [ExpectItem]
    let expectAfter: [ExpectAfterItem]
    let expectFallback: ExpectFallbackSpec?
    let killSweep: KillSweepSpec?
    let expectOutcome: String?
    let expectSummary: String?
    let forbid: [String]
    let forbidMatch: [EventFilter]
    let forbidAfter: [ForbidAfterItem]
}

struct TraceFile: Sendable {
    let traceId: String
    let vehicle: String
    let gpx: String
    let startTime: String
    let startMs: Int64
    let intervalS: Int
    let durationS: Int
    let sampleCount: Int
    let destLat: Double
    let destLng: Double
    let arrivalT: Int
    let gpsGaps: [(fromT: Int, toT: Int)]
    let overshootT: Int?
    let closestT: Int?
    let closestDepartT: Int?
    let routeT: [Int: Int]
    let straightT: [Int: Int]
    /// Raw `cases[i]` (parsed per case so one bad case does not hide the others).
    let rawCases: [JsonValue]

    func caseId(_ i: Int) -> String { rawCases[i]["id"]?.stringValue ?? "case\(i)" }
}

enum ExpectModel {
    static func parseTrace(_ text: String) throws -> TraceFile {
        let root: JsonValue
        do { root = try MiniJson.parse(text) } catch { throw ModelError(description: "expect.json: \(error)") }
        guard let version = root["schemaVersion"]?.asLongExact() else { throw ModelError(description: "schemaVersion missing") }
        if version > 1 { throw ModelError(description: "schemaVersion \(version) > 1 unsupported") }
        guard let trace = root["trace"], let dest = root["destination"], let truth = root["truth"],
              let traceId = trace["id"]?.stringValue, let vehicle = trace["vehicle"]?.stringValue,
              let gpx = trace["gpx"]?.stringValue, let startTime = trace["startTime"]?.stringValue,
              let interval = trace["sampleIntervalS"]?.asIntExact(), let duration = trace["durationS"]?.asIntExact(),
              let count = trace["sampleCount"]?.asIntExact(), let lat = dest["lat"]?.asDouble(), let lng = dest["lng"]?.asDouble(),
              let arrival = truth["arrivalT"]?.asIntExact(), let cases = root["cases"]?.arrayValue else {
            throw ModelError(description: "expect.json: missing required trace keys")
        }
        var gaps: [(Int, Int)] = []
        for g in truth["gpsGaps"]?.arrayValue ?? [] {
            if let f = g["fromT"]?.asIntExact(), let t = g["toT"]?.asIntExact() { gaps.append((f, t)) }
        }
        var routeT: [Int: Int] = [:], straightT: [Int: Int] = [:]
        for m in root["milestones"]?["distance"]?.arrayValue ?? [] {
            guard let thr = m["thresholdM"]?.asIntExact() else { continue }
            if let r = m["routeT"]?.asIntExact() { routeT[thr] = r }
            if let s = m["straightT"]?.asIntExact() { straightT[thr] = s }
        }
        return TraceFile(traceId: traceId, vehicle: vehicle, gpx: gpx, startTime: startTime,
                         startMs: try IsoTime.parseMs(startTime), intervalS: interval, durationS: duration, sampleCount: count,
                         destLat: lat, destLng: lng, arrivalT: arrival, gpsGaps: gaps,
                         overshootT: truth["overshoot"]?["t"]?.asIntExact(), closestT: truth["closest"]?["t"]?.asIntExact(),
                         closestDepartT: truth["closest"]?["departT"]?.asIntExact(), routeT: routeT, straightT: straightT,
                         rawCases: cases)
    }

    // MARK: must-understand case parsing

    static let caseKeys: Set<String> = ["id", "status", "testIds", "config", "samplingModes", "policyPhaseSweep", "allowFallbackFirst", "expect",
                                        "expectAfter", "expectFallback", "killSweep", "expectOutcome", "expectSummary",
                                        "forbid", "forbidMatch", "forbidAfter"]
    static let configKeys: Set<String> = ["mode", "thresholdM", "thresholdMin", "preAlert", "vehicleHint", "params", "battery",
                                          "actions", "kill", "relaunch", "osDismiss", "osSim", "osRingMaxS"]
    static let atKeys: Set<String> = ["t", "anchor", "offsetS"]
    static let filterKeys: Set<String> = ["event", "reason", "ringNow", "cause"]

    private static func obj(_ v: JsonValue?, _ path: String, _ allowed: Set<String>) throws -> JsonValue {
        guard let v, case let .object(pairs) = v else { throw ModelError(description: "\(path): expected object") }
        for (k, _) in pairs where !allowed.contains(k) { throw ModelError(description: "unknown key \(path).\(k)") }
        return v
    }

    private static func int(_ v: JsonValue?, _ path: String) throws -> Int {
        guard let x = v?.asIntExact() else { throw ModelError(description: "\(path): expected int") }
        return x
    }

    private static func str(_ v: JsonValue?, _ path: String) throws -> String {
        guard let x = v?.stringValue else { throw ModelError(description: "\(path): expected string") }
        return x
    }

    private static func bool(_ v: JsonValue?, _ path: String) throws -> Bool {
        guard let x = v?.boolValue else { throw ModelError(description: "\(path): expected bool") }
        return x
    }

    private static func arr(_ v: JsonValue?, _ path: String) throws -> [JsonValue] {
        guard let x = v?.arrayValue else { throw ModelError(description: "\(path): expected array") }
        return x
    }

    static func at(_ v: JsonValue?, _ path: String) throws -> At {
        let o = try obj(v, path, atKeys)
        let t = o["t"] == nil ? nil : try int(o["t"], "\(path).t")
        let anchor = o["anchor"] == nil ? nil : try str(o["anchor"], "\(path).anchor")
        let off = o["offsetS"] == nil ? 0 : try int(o["offsetS"], "\(path).offsetS")
        if t == nil && anchor == nil { throw ModelError(description: "\(path): At needs t or anchor") }
        return At(t: t, anchor: anchor, offsetS: off)
    }

    private static func filter(_ o: JsonValue, _ path: String) throws -> EventFilter {
        EventFilter(event: try str(o["event"], "\(path).event"),
                    reason: o["reason"] == nil ? nil : try str(o["reason"], "\(path).reason"),
                    ringNow: o["ringNow"] == nil ? nil : try bool(o["ringNow"], "\(path).ringNow"),
                    cause: o["cause"] == nil ? nil : try str(o["cause"], "\(path).cause"))
    }

    static func parseCase(_ v: JsonValue, index: Int) throws -> CaseSpec {
        let p = "cases[\(index)]"
        let c = try obj(v, p, caseKeys)
        let id = try str(c["id"], "\(p).id")
        _ = try str(c["status"], "\(p).status")
        let testIds = try (c["testIds"].map { try arr($0, "\(p).testIds") } ?? []).map { try str($0, "\(p).testIds[]") }

        let cp = "\(p).config"
        let cfg = try obj(c["config"], cp, configKeys)
        var params: [(String, JsonValue)] = []
        if let pv = cfg["params"] {
            guard case let .object(pairs) = pv else { throw ModelError(description: "\(cp).params: expected object") }
            for (k, x) in pairs {
                guard ParamTable.index(of: k) != nil else { throw ModelError(description: "unknown key \(cp).params.\(k)") }
                params.append((k, x))
            }
        }
        var battery: [(Int, Int, Bool)] = []
        let batteryItems: [JsonValue] = try cfg["battery"].map { try arr($0, "\(cp).battery") } ?? []
        for (i, b) in batteryItems.enumerated() {
            let bp = "\(cp).battery[\(i)]"
            let o = try obj(b, bp, ["t", "levelPct", "charging"])
            battery.append((try int(o["t"], "\(bp).t"), try int(o["levelPct"], "\(bp).levelPct"),
                            try bool(o["charging"], "\(bp).charging")))
        }
        var actions: [(At, String)] = []
        let actionsItems: [JsonValue] = try cfg["actions"].map { try arr($0, "\(cp).actions") } ?? []
        for (i, a) in actionsItems.enumerated() {
            let ap = "\(cp).actions[\(i)]"
            let o = try obj(a, ap, ["at", "action"])
            actions.append((try at(o["at"], "\(ap).at"), try str(o["action"], "\(ap).action")))
        }
        let kill = cfg["kill"] == nil ? nil : try at(cfg["kill"], "\(cp).kill")
        var relaunch: (At, String)? = nil
        if let r = cfg["relaunch"] {
            let o = try obj(r, "\(cp).relaunch", ["at", "fallbackStatus"])
            relaunch = (try at(o["at"], "\(cp).relaunch.at"), try str(o["fallbackStatus"], "\(cp).relaunch.fallbackStatus"))
        }
        var osDismiss: Int? = nil
        if let d = cfg["osDismiss"] {
            let o = try obj(d, "\(cp).osDismiss", ["offsetS"])
            osDismiss = try int(o["offsetS"], "\(cp).osDismiss.offsetS")
        }
        let config = CaseConfig(
            mode: try str(cfg["mode"], "\(cp).mode"),
            thresholdM: cfg["thresholdM"] == nil ? nil : try int(cfg["thresholdM"], "\(cp).thresholdM"),
            thresholdMin: cfg["thresholdMin"] == nil ? nil : try int(cfg["thresholdMin"], "\(cp).thresholdMin"),
            preAlert: try bool(cfg["preAlert"], "\(cp).preAlert"),
            vehicleHint: cfg["vehicleHint"] == nil ? nil : try str(cfg["vehicleHint"], "\(cp).vehicleHint"),
            params: params, battery: battery, actions: actions, kill: kill, relaunch: relaunch, osDismissOffsetS: osDismiss,
            osSim: cfg["osSim"] == nil ? true : try bool(cfg["osSim"], "\(cp).osSim"),
            osRingMaxS: cfg["osRingMaxS"] == nil ? nil : try int(cfg["osRingMaxS"], "\(cp).osRingMaxS"))

        let samplingModes = try c["samplingModes"].map { try arr($0, "\(p).samplingModes").map { try str($0, "\(p).samplingModes[]") } }
        let sweep = c["policyPhaseSweep"] == nil ? false : try bool(c["policyPhaseSweep"], "\(p).policyPhaseSweep")
        let allowFallbackFirst = c["allowFallbackFirst"] == nil ? false : try bool(c["allowFallbackFirst"], "\(p).allowFallbackFirst")

        var expect: [ExpectItem] = []
        for (i, e) in try arr(c["expect"], "\(p).expect").enumerated() {
            let ep = "\(p).expect[\(i)]"
            let o = try obj(e, ep, filterKeys.union(["notBefore", "notAfter", "window", "ref"]))
            if let w = o["window"] {
                let wo = try obj(w, "\(ep).window", ["notBefore", "notAfter"])
                if wo["notBefore"] != nil { _ = try at(wo["notBefore"], "\(ep).window.notBefore") }
                if wo["notAfter"] != nil { _ = try at(wo["notAfter"], "\(ep).window.notAfter") }
            }
            expect.append(ExpectItem(filter: try filter(o, ep), notBefore: try int(o["notBefore"], "\(ep).notBefore"),
                                     notAfter: try int(o["notAfter"], "\(ep).notAfter")))
        }
        var expectAfter: [ExpectAfterItem] = []
        let expectAfterItems: [JsonValue] = try c["expectAfter"].map { try arr($0, "\(p).expectAfter") } ?? []
        for (i, e) in expectAfterItems.enumerated() {
            let ep = "\(p).expectAfter[\(i)]"
            let o = try obj(e, ep, filterKeys.union(["after", "withinS", "ref"]))
            let w = try arr(o["withinS"], "\(ep).withinS")
            guard w.count == 2 else { throw ModelError(description: "\(ep).withinS: expected [lo, hi]") }
            expectAfter.append(ExpectAfterItem(filter: try filter(o, ep), after: try at(o["after"], "\(ep).after"),
                                               lo: try int(w[0], "\(ep).withinS[0]"), hi: try int(w[1], "\(ep).withinS[1]")))
        }
        var expectFallback: ExpectFallbackSpec? = nil
        if let f = c["expectFallback"] {
            let fp = "\(p).expectFallback"
            let o = try obj(f, fp, ["asOfT", "notBefore", "notAfter", "window", "ref"])
            if let w = o["window"] {
                let wo = try obj(w, "\(fp).window", ["modeAt", "modeAtT", "killT", "estimateT", "asOfStraightM",
                                                     "hintEstimateT", "toleranceS"])
                if wo["modeAt"] != nil { _ = try at(wo["modeAt"], "\(fp).window.modeAt") }
            }
            expectFallback = ExpectFallbackSpec(asOfT: try int(o["asOfT"], "\(fp).asOfT"),
                                                notBefore: try int(o["notBefore"], "\(fp).notBefore"),
                                                notAfter: try int(o["notAfter"], "\(fp).notAfter"))
        }
        var killSweep: KillSweepSpec? = nil
        if let k = c["killSweep"] {
            let kp = "\(p).killSweep"
            let o = try obj(k, kp, ["from", "everyS", "notAfter", "earlyFrom", "statsOnly"])
            killSweep = KillSweepSpec(from: try at(o["from"], "\(kp).from"), everyS: try int(o["everyS"], "\(kp).everyS"),
                                      notAfter: try at(o["notAfter"], "\(kp).notAfter"),
                                      earlyFrom: try at(o["earlyFrom"], "\(kp).earlyFrom"),
                                      statsOnly: o["statsOnly"] == nil ? false : try bool(o["statsOnly"], "\(kp).statsOnly"))
        }
        var expectSummary: String? = nil
        if let s = c["expectSummary"] {
            let o = try obj(s, "\(p).expectSummary", ["vehicleGuess"])
            expectSummary = try str(o["vehicleGuess"], "\(p).expectSummary.vehicleGuess")
        }
        let forbid = try arr(c["forbid"], "\(p).forbid").map { try str($0, "\(p).forbid[]") }
        var forbidMatch: [EventFilter] = []
        let forbidMatchItems: [JsonValue] = try c["forbidMatch"].map { try arr($0, "\(p).forbidMatch") } ?? []
        for (i, f) in forbidMatchItems.enumerated() {
            let fp = "\(p).forbidMatch[\(i)]"
            forbidMatch.append(try filter(try obj(f, fp, filterKeys), fp))
        }
        var forbidAfter: [ForbidAfterItem] = []
        let forbidAfterItems: [JsonValue] = try c["forbidAfter"].map { try arr($0, "\(p).forbidAfter") } ?? []
        for (i, f) in forbidAfterItems.enumerated() {
            let fp = "\(p).forbidAfter[\(i)]"
            let o = try obj(f, fp, filterKeys.union(["after"]))
            forbidAfter.append(ForbidAfterItem(filter: try filter(o, fp), after: try at(o["after"], "\(fp).after")))
        }
        return CaseSpec(id: id, testIds: testIds, config: config, samplingModes: samplingModes, policyPhaseSweep: sweep,
                        allowFallbackFirst: allowFallbackFirst,
                        expect: expect, expectAfter: expectAfter, expectFallback: expectFallback, killSweep: killSweep,
                        expectOutcome: c["expectOutcome"] == nil ? nil : try str(c["expectOutcome"], "\(p).expectOutcome"),
                        expectSummary: expectSummary, forbid: forbid, forbidMatch: forbidMatch, forbidAfter: forbidAfter)
    }
}

/// A loaded trace: expect model + GPX samples indexed by tick.
struct LoadedTrace: Sendable {
    let file: TraceFile
    let samples: [TraceSample]
    let byTick: [Int?]   // sample index for tick t/I, nil in gaps

    static func load(_ expectName: String) throws -> LoadedTrace {
        let file = try ExpectModel.parseTrace(try FixturePaths.read(FixturePaths.tracesDir + "/" + expectName))
        let samples = try Gpx.read(try FixturePaths.read(FixturePaths.tracesDir + "/" + file.gpx), startMs: file.startMs,
                                   intervalS: file.intervalS)
        guard samples.count == file.sampleCount else { throw ModelError(description: "sampleCount mismatch") }
        guard let lastT = samples.last?.t, lastT == file.durationS, samples.first?.t == 0 else {
            throw ModelError(description: "GPX time range mismatch")
        }
        var byTick = [Int?](repeating: nil, count: file.durationS / file.intervalS + 1)
        for s in samples { byTick[s.t / file.intervalS] = s.index }
        return LoadedTrace(file: file, samples: samples, byTick: byTick)
    }

    /// All traces of the fixture directory, cached once per process.
    static let all: [LoadedTrace] = {
        (try? FixturePaths.expectFiles().compactMap { try? LoadedTrace.load($0) }) ?? []
    }()

    static func named(_ id: String) -> LoadedTrace? { all.first { $0.file.traceId == id } }
}
