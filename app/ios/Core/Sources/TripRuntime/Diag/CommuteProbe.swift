// Spike T23.8-B0 (docs/spikes/T23.8.md): pure part of the region wake probe. Only the Runner uses it, and only under
// NAPSTOP_DIAG (`Runner/Native/DiagCommuteProbe.swift`). Nothing here holds coordinates or place names: the probe file
// stores event kinds, wall times, durations, distances rounded to 10 m and accuracy buckets only.
import Foundation

public enum ProbeApi: String, Codable, Sendable, CaseIterable {
    case clmonitor, legacy

    /// Short label of the report.
    public var label: String { self == .clmonitor ? "CLMonitor" : "Legacy" }
}

/// Which region APIs the probe arms (`both` = paired comparison of the event delay; H1 counts single-API runs only).
public enum ProbeApiMode: String, Codable, Sendable {
    case clmonitor, legacy, both

    public var apis: [ProbeApi] {
        switch self {
        case .clmonitor: return [.clmonitor]
        case .legacy: return [.legacy]
        case .both: return [.clmonitor, .legacy]
        }
    }
}

public enum ProbePoint: String, Codable, Sendable, CaseIterable { case a = "A", b = "B" }

public enum ProbeRegionState: String, Codable, Sendable { case unknown, inside, outside }

/// Spec T23.8 D6 on probe data: only outside → inside is an entry; the first known state is never one (H8).
public enum ProbeTransition: String, Codable, Sendable { case first, entry, exit, same }

public struct CommuteProbeConfig: Codable, Sendable, Equatable {
    public var apiMode: ProbeApiMode
    /// H2b: keep a `CLServiceSession(authorization: .always)` (iOS 18+), re-created at every launch.
    public var serviceSession: Bool
    /// Length of the continuous location session started by an entry.
    public var holdMin: Int
    /// H3: AlarmKit alarm this many minutes after the entry (0 = none).
    public var alarmMin: Int
    public var radiusM: Int
    /// Points with a region (A, B).
    public var points: [ProbePoint]

    public init(apiMode: ProbeApiMode, serviceSession: Bool, holdMin: Int, alarmMin: Int, radiusM: Int,
                points: [ProbePoint]) {
        self.apiMode = apiMode
        self.serviceSession = serviceSession
        self.holdMin = holdMin
        self.alarmMin = alarmMin
        self.radiusM = radiusM
        self.points = points
    }
}

/// Gaps between received fixes of one continuous session (receipt wall time, not fix time: suspension shows up here).
public struct ProbeFixStats: Codable, Sendable, Equatable {
    public static let bigGapMs: Int64 = 60_000

    public private(set) var count = 0
    public private(set) var firstWallMs: Int64?
    public private(set) var lastWallMs: Int64?
    public private(set) var maxGapMs: Int64 = 0
    /// Gaps longer than `bigGapMs` (spike §4: none allowed while locked).
    public private(set) var bigGaps = 0

    public init() {}

    /// Adds one fix; returns the gap to the previous fix when it is longer than `bigGapMs`.
    @discardableResult
    public mutating func add(wallMs: Int64) -> Int64? {
        defer {
            count += 1
            lastWallMs = max(lastWallMs ?? wallMs, wallMs)
        }
        guard let last = lastWallMs else {
            firstWallMs = wallMs
            return nil
        }
        let gap = max(0, wallMs - last)
        maxGapMs = max(maxGapMs, gap)
        if gap > Self.bigGapMs {
            bigGaps += 1
            return gap
        }
        return nil
    }
}

/// One region event as received (all APIs, all states).
public struct ProbeEventRecord: Codable, Sendable, Equatable {
    public let api: ProbeApi
    public let point: ProbePoint
    public let state: ProbeRegionState
    public let transition: ProbeTransition
    /// `CLMonitor.Event.date`; nil for the legacy API (no event date).
    public let eventWallMs: Int64?
    public let receivedWallMs: Int64
    /// `active` / `inactive` / `background` when received.
    public let appState: String
    /// Seconds since this process started.
    public let procAgeS: Int
    /// The process was launched in the background (not by the user).
    public let launchedInBackground: Bool
    /// First region event of this process.
    public let firstOfProcess: Bool

    public init(api: ProbeApi, point: ProbePoint, state: ProbeRegionState, transition: ProbeTransition,
                eventWallMs: Int64?, receivedWallMs: Int64, appState: String, procAgeS: Int,
                launchedInBackground: Bool, firstOfProcess: Bool) {
        self.api = api
        self.point = point
        self.state = state
        self.transition = transition
        self.eventWallMs = eventWallMs
        self.receivedWallMs = receivedWallMs
        self.appState = appState
        self.procAgeS = procAgeS
        self.launchedInBackground = launchedInBackground
        self.firstOfProcess = firstOfProcess
    }

    /// Delay between the system's event date and its delivery to the app, seconds (nil without an event date).
    public var ageS: Int? { eventWallMs.map { Int(max(0, receivedWallMs - $0) / 1000) } }

    /// H1: the system launched the app for this event (background launch, first event, within `relaunchWindowS`).
    public var relaunched: Bool {
        launchedInBackground && firstOfProcess && procAgeS <= CommuteProbe.relaunchWindowS
    }
}

/// One entry (outside → inside) and the continuous session it started, if any.
public struct ProbeWakeRecord: Codable, Sendable, Equatable {
    public let id: String
    public let event: ProbeEventRecord
    /// nil = started; else why not (`running`, `not-always`, `start-failed:<type>`).
    public var notStarted: String?
    public var serviceSession: Bool
    public var stats = ProbeFixStats()
    /// Distance from the region centre at the first fix, rounded to 10 m (how late the wake was).
    public var firstFixDistM: Int?
    public var firstFixAccuracy: String?
    /// H3: nil = no alarm asked; "ok" or the error type.
    public var alarm: String?
    /// H4: the notification's Stop action ran.
    public var stopTapped = false
    public var endedWallMs: Int64?
    /// `hold` (hold time reached), `stop-action`, `stop-intent`, `auth`, `interrupted` (process died), `error`.
    public var endReason: String?

    public init(id: String, event: ProbeEventRecord, notStarted: String?, serviceSession: Bool) {
        self.id = id
        self.event = event
        self.notStarted = notStarted
        self.serviceSession = serviceSession
    }

    public var started: Bool { notStarted == nil }

    /// Covered length of the session: start (event receipt) → last fix.
    public var coveredMs: Int64 {
        guard let last = stats.lastWallMs else { return 0 }
        return max(0, last - event.receivedWallMs)
    }

    /// Spike §4 H2: ≥ 60 minutes of fixes, no gap > 60 s.
    public var sessionPassed: Bool {
        started && coveredMs >= CommuteProbe.passSessionMs && stats.bigGaps == 0
    }
}

public struct CommuteProbeFile: Codable, Sendable, Equatable {
    public var version = 1
    public var config: CommuteProbeConfig?
    /// Last known state per "<api>.<point>".
    public var states: [String: ProbeRegionState] = [:]
    public var events: [ProbeEventRecord] = []
    public var wakes: [ProbeWakeRecord] = []
    /// Wake whose session is running (or was running when the process died).
    public var activeWakeId: String?

    public init() {}

    public static func stateKey(_ api: ProbeApi, _ point: ProbePoint) -> String { "\(api.rawValue).\(point.rawValue)" }

    /// Keeps the newest `CommuteProbe.maxEvents` events and `maxWakes` wakes.
    public mutating func trim() {
        if events.count > CommuteProbe.maxEvents { events.removeFirst(events.count - CommuteProbe.maxEvents) }
        if wakes.count > CommuteProbe.maxWakes {
            let drop = wakes.count - CommuteProbe.maxWakes
            let dropped = Set(wakes.prefix(drop).map(\.id))
            wakes.removeFirst(drop)
            if let a = activeWakeId, dropped.contains(a) { activeWakeId = nil }
        }
    }
}

/// Live device state for the report header (read by the Runner).
public struct ProbeLiveStatus: Sendable, Equatable {
    public let authorization: String
    public let fullAccuracy: Bool
    public let backgroundRefresh: String
    public let lowPower: Bool
    public let sessionRunning: Bool
    public let monitored: [String]

    public init(authorization: String, fullAccuracy: Bool, backgroundRefresh: String, lowPower: Bool,
                sessionRunning: Bool, monitored: [String]) {
        self.authorization = authorization
        self.fullAccuracy = fullAccuracy
        self.backgroundRefresh = backgroundRefresh
        self.lowPower = lowPower
        self.sessionRunning = sessionRunning
        self.monitored = monitored
    }
}

public enum CommuteProbe {
    public static let relaunchWindowS = 120
    public static let passSessionMs: Int64 = 3_600_000
    public static let maxEvents = 400
    public static let maxWakes = 120
    public static let reportRecent = 10

    public static func transition(prev: ProbeRegionState, new: ProbeRegionState) -> ProbeTransition {
        switch (prev, new) {
        case (_, .unknown): return .same
        case (.unknown, _): return .first
        case (.outside, .inside): return .entry
        case (.inside, .outside): return .exit
        default: return .same
        }
    }

    /// Horizontal accuracy bucket (`bad` = negative, i.e. invalid).
    public static func accuracyBucket(_ m: Double) -> String {
        guard m >= 0, m.isFinite else { return "bad" }
        for b in [10.0, 20, 50, 100, 500] where m < b { return "<\(Int(b))" }
        return ">=500"
    }

    public static func roundTo10(_ m: Double) -> Int { Int((max(0, m) / 10).rounded()) * 10 }

    /// Lower median of integers (nil when empty).
    public static func median(_ xs: [Int]) -> Int? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[(s.count - 1) / 2]
    }

    /// "dd/MM HH:mm" of a wall time at a fixed UTC offset (Gregorian, proleptic; no Calendar so Linux = Apple).
    public static func localStamp(_ wallMs: Int64, utcOffsetS: Int) -> String {
        let secs = Int64((Double(wallMs) / 1000).rounded(.down)) + Int64(utcOffsetS)
        var days = secs >= 0 ? secs / 86_400 : (secs - 86_399) / 86_400
        let sod = secs - days * 86_400
        // Civil from days (H. Hinnant).
        days += 719_468
        let era = (days >= 0 ? days : days - 146_096) / 146_097
        let doe = days - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        func two(_ v: Int64) -> String { v < 10 ? "0\(v)" : "\(v)" }
        return "\(two(d))/\(two(m)) \(two(sod / 3600)):\(two(sod % 3600 / 60))"
    }

    // MARK: Report

    /// Vietnamese text summary (Shortcuts result). No coordinates exist in the inputs.
    public static func report(_ f: CommuteProbeFile, live: ProbeLiveStatus, utcOffsetS: Int) -> String {
        var out: [String] = ["NapStop probe vùng (T23.8 B0)"]
        if let c = f.config {
            out.append("Cấu hình: \(c.apiMode.rawValue), phiên Always: \(c.serviceSession ? "bật" : "tắt"), giữ \(c.holdMin) phút, "
                + "báo sau \(c.alarmMin == 0 ? "tắt" : "\(c.alarmMin) phút"), bán kính \(c.radiusM) m, "
                + "vùng: \(c.points.isEmpty ? "chưa có" : c.points.map(\.rawValue).joined(separator: ", "))")
        } else {
            out.append("Cấu hình: chưa đặt vùng")
        }
        out.append("Quyền: \(live.authorization)\(live.fullAccuracy ? "" : " (không chính xác)") · Làm mới nền: "
            + "\(live.backgroundRefresh) · Nguồn điện thấp: \(live.lowPower ? "bật" : "tắt")")
        out.append("Đang theo dõi liên tục: \(live.sessionRunning ? "có" : "không") · Hệ thống đang canh: "
            + (live.monitored.isEmpty ? "không" : live.monitored.joined(separator: ", ")))
        for api in ProbeApi.allCases {
            let w = f.wakes.filter { $0.event.api == api }
            guard !w.isEmpty else {
                out.append("\(api.label): chưa có lần vào vùng")
                continue
            }
            let relaunched = w.filter(\.event.relaunched).count
            let fg = w.filter { $0.event.appState == "active" }.count
            var line = "\(api.label): vào vùng \(w.count) (khởi chạy lại \(relaunched), app đang mở \(fg), "
                + "app còn chạy nền \(w.count - relaunched - fg))"
            let ages = w.compactMap(\.event.ageS)
            if let med = median(ages), let mx = ages.max() { line += "; trễ giao sự kiện trung vị \(med) s, tối đa \(mx) s" }
            out.append(line)
            let started = w.filter(\.started)
            let done = started.filter { $0.endedWallMs != nil || $0.id != f.activeWakeId }
            let passed = done.filter(\.sessionPassed).count
            let maxGap = started.map(\.stats.maxGapMs).max() ?? 0
            out.append("  Phiên: \(started.count) bắt đầu, \(passed)/\(done.count) đạt (≥ 60 phút, không trống > 60 s); "
                + "trống lớn nhất \(maxGap / 1000) s")
        }
        let firsts = f.events.filter { $0.transition == .first }
        if !firsts.isEmpty {
            let parts = firsts.suffix(6).map { "\($0.api.label) \($0.point.rawValue) \($0.state == .inside ? "trong" : "ngoài")" }
            out.append("Lần xác định đầu: " + parts.joined(separator: "; "))
        }
        let recent = f.wakes.suffix(reportRecent)
        if !recent.isEmpty {
            out.append("\(recent.count) lần vào vùng gần nhất:")
            for r in recent.reversed() { out.append("  " + line(r, active: r.id == f.activeWakeId, utcOffsetS: utcOffsetS)) }
        }
        return out.joined(separator: "\n")
    }

    static func line(_ r: ProbeWakeRecord, active: Bool, utcOffsetS: Int) -> String {
        let e = r.event
        var s = "\(localStamp(e.receivedWallMs, utcOffsetS: utcOffsetS)) \(e.api.label) \(e.point.rawValue) "
        s += e.relaunched ? "khởi chạy lại" : (e.appState == "active" ? "app đang mở" : "app còn chạy nền")
        if let a = e.ageS { s += ", trễ \(a) s" }
        guard r.started else { return s + ", không bật: \(r.notStarted ?? "?")" }
        s += ", phiên \(r.coveredMs / 60_000) phút, \(r.stats.count) fix, trống tối đa \(r.stats.maxGapMs / 1000) s"
        if r.stats.bigGaps > 0 { s += " (\(r.stats.bigGaps) lần > 60 s)" }
        if let d = r.firstFixDistM { s += ", fix đầu cách tâm \(d) m" }
        if let a = r.alarm { s += ", báo: \(a)" }
        if r.stopTapped { s += ", đã bấm Dừng" }
        s += ", kết thúc: \(r.endReason ?? (active ? "đang chạy" : "?"))"
        return s
    }
}
