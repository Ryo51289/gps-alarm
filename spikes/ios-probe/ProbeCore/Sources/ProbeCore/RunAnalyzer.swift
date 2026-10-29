import Foundation

public enum Verdict: String, Sendable {
    case PASS
    case WARN
    case FAIL
}

/// What the log says about the alarm of one run (S3 §6.7).
public struct AlarmResult: Equatable, Sendable {
    public var planned: Date?
    public var triggeredAt: Date?
    /// fix | test | prearm | nil
    public var src: String?
    /// Lateness judged against the thresholds (S3 §5.4 "kêu − mốc"):
    /// src=fix: max(triggerLateS, ringLateS); src=prearm: ringLateS (vs. the fallback's own time); nil = not measurable.
    public var lateS: Double?
    /// src=fix: alarm_trigger − deadline (`lateMs`).
    public var triggerLateS: Double?
    /// First real ring time of the source's kind (ak_state alerting / notif_delivered.deliveredAt; never alarm_stop) −
    /// deadline (src=fix, kind=now) or − the last successful prearm `at` (src=prearm, kind=prearm).
    public var ringLateS: Double?
    /// All `kind=now` schedule calls (ak_schedule / notif_add) succeeded; nil when there were none.
    public var scheduleOk: Bool?
    public var alertingSeen: Bool
    /// `deliveredAt` of this run's delivered notifications, sorted.
    public var delivered: [Date]
    public var stopVia: String?
    /// alarm_stop − first ring evidence (ak_state alerting, else first delivery, else trigger).
    public var stopAfterS: Double?

    public init(
        planned: Date? = nil, triggeredAt: Date? = nil, src: String? = nil, lateS: Double? = nil,
        triggerLateS: Double? = nil, ringLateS: Double? = nil,
        scheduleOk: Bool? = nil, alertingSeen: Bool = false, delivered: [Date] = [],
        stopVia: String? = nil, stopAfterS: Double? = nil
    ) {
        self.planned = planned
        self.triggeredAt = triggeredAt
        self.src = src
        self.lateS = lateS
        self.triggerLateS = triggerLateS
        self.ringLateS = ringLateS
        self.scheduleOk = scheduleOk
        self.alertingSeen = alertingSeen
        self.delivered = delivered
        self.stopVia = stopVia
        self.stopAfterS = stopAfterS
    }
}

public struct RunSummary: Equatable, Sendable {
    public var runId: String
    public var scenario: String
    public var channel: String
    public var ios: String
    public var model: String
    public var durationS: Double
    public var stoppedBy: String?
    public var fixCount: [Phase: Int]
    public var fixGapMaxS: [Phase: Double]
    /// proc_start lines inside the run.
    public var launches: Int
    /// proc_start inside the run whose previous process logged no self_exit_now / loc_suspend_user / will_terminate,
    /// not opened for a stop button, not after a reboot.
    public var unexpectedRelaunches: Int
    /// proc_start followed (same launch, within stopRelaunchWindowS) by alarm_stop via intent / notif_action:
    /// the system opened the app to run the stop button (S3-8), not evidence for H5.
    public var stopButtonRelaunches: Int
    /// proc_start whose `up` (system uptime) is lower than the previous event's: the device rebooted mid-run (§6.9).
    public var reboots: Int
    public var selfExit: Bool
    public var rescheduleOk: Int
    public var rescheduleErr: Int
    public var batteryStart: Double?
    public var batteryEnd: Double?
    public var lowPowerSeen: Bool
    /// locAuth, notifAuth, timeSensitive, alarmKitAuth from the first perm_snapshot of the run.
    public var authAtStart: [String: String]
    public var alarm: AlarmResult
    public var verdict: Verdict
    /// Vietnamese; FAIL and WARN reasons first, then "(thông tin) …" lines.
    public var reasons: [String]
}

public enum RunAnalyzer {
    public static let densePassS = 60.0
    public static let denseFailS = 180.0
    public static let sparseWarnS = 900.0
    public static let lateWarnS = 15.0
    /// S3 §5.4: the TS channel passes up to 30 s late.
    public static let lateWarnTsS = 30.0
    public static let lateFailS = 120.0
    public static let pendingGraceS = 180.0
    /// A proc_start counts as "opened for the stop button" if alarm_stop follows within this many seconds.
    public static let stopRelaunchWindowS = 15.0

    /// Events after which a new process is expected (S3 §6.7 `unexpectedRelaunches`) and location gaps are not judged.
    static let intentionalStops: Set<String> = ["self_exit_now", "loc_suspend_user", "will_terminate"]

    private struct Findings {
        var fail: [String] = []
        var warn: [String] = []
        var info: [String] = []

        var verdict: Verdict {
            if !fail.isEmpty { return .FAIL }
            if !warn.isEmpty { return .WARN }
            return .PASS
        }
    }

    public static func analyze(_ events: [ProbeEvent], now: Date) -> RunSummary {
        let sorted = events.sorted { a, b in
            if a.t != b.t { return a.t < b.t }
            return a.seq < b.seq
        }
        guard let start = sorted.first(where: { $0.ev == "run_start" }) else {
            return noRunStart(sorted)
        }
        let startT = start.t
        let inRun = sorted.filter { $0.t >= startT }
        let stop = inRun.first { $0.ev == "run_stop" }
        let endT = stop?.t ?? (inRun.last?.t ?? startT)
        let stoppedBy = stop?.str("by")
        let channel = start.str("channel") ?? "?"
        let scenario = start.str("scenario") ?? "?"
        var f = Findings()

        // ---- plan ----
        let delayMin = Double(start.int("delayMin") ?? 0)
        let durationMin = Double(start.int("durationMin") ?? start.int("delayMin") ?? 0)
        let denseMin = Double(start.int("densePhaseMin") ?? Int64(durationMin))
        let planned = start.date("deadline") ?? startT.addingTimeInterval(max(delayMin, durationMin) * 60)
        let durationS = durationMin * 60
        let denseStart = TriggerLogic.denseStart(runStart: startT, durationS: durationS, densePhaseS: denseMin * 60)
        let ended = stop != nil || now >= planned.addingTimeInterval(pendingGraceS)
        if !ended { f.info.append("lượt đang chạy") }

        // ---- location gaps (judged up to the deadline, and only until location was stopped on purpose) ----
        let firstIntentional = inRun.first { intentionalStops.contains($0.ev) }?.t
        var judgeEnd = min(endT, planned)
        if let fi = firstIntentional { judgeEnd = min(judgeEnd, fi) }
        let fixTimes = inRun.filter { $0.ev == "fix" }.map { $0.t }
        var fixCount: [Phase: Int] = [.sparse: 0, .dense: 0]
        var fixGapMax: [Phase: Double] = [.sparse: 0, .dense: 0]
        for fixT in fixTimes {
            let phase: Phase = fixT >= denseStart ? .dense : .sparse
            fixCount[phase, default: 0] += 1
        }
        let windows: [(Phase, Date, Date)] = [
            (.sparse, startT, min(denseStart, judgeEnd)),
            (.dense, max(startT, denseStart), judgeEnd),
        ]
        for (phase, winStart, winEnd) in windows where winEnd > winStart {
            let inside = fixTimes.filter { $0 >= winStart && $0 <= winEnd }
            let marks = [winStart] + inside + [winEnd]
            var maxGap = 0.0
            for k in 1..<marks.count {
                maxGap = max(maxGap, marks[k].timeIntervalSince(marks[k - 1]))
            }
            fixGapMax[phase] = maxGap
            let g = Int(maxGap.rounded())
            switch phase {
            case .dense:
                if maxGap > denseFailS {
                    f.fail.append("mất vị trí \(g) s ở pha dày")
                } else if maxGap > densePassS {
                    f.warn.append("khoảng trống vị trí \(g) s ở pha dày")
                }
            case .sparse:
                if maxGap > sparseWarnS { f.warn.append("khoảng trống vị trí \(g) s ở pha thưa") }
            }
        }
        if let fi = firstIntentional, fi < planned {
            f.info.append("vị trí được dừng có chủ đích lúc +\(DurationText.vi(fi.timeIntervalSince(startT)))")
        }

        // ---- process launches ----
        var launches = 0
        var unexpected = 0
        var stopRelaunches = 0
        var stopRelaunchesUnclear = 0
        var reboots = 0
        var sawIntentional = false
        var lastUp: Double?
        for (idx, e) in inRun.enumerated() {
            if e.ev == "proc_start" {
                launches += 1
                let rebooted = (e.double("up") ?? 0) < (lastUp ?? -1)
                let forStopButton = inRun[(idx + 1)...]
                    .prefix(while: { $0.t.timeIntervalSince(e.t) <= stopRelaunchWindowS })
                    .contains { next in
                        next.launch == e.launch && next.ev == "alarm_stop"
                            && (next.str("via") == "intent" || next.str("via") == "notif_action")
                    }
                if rebooted {
                    reboots += 1
                } else if forStopButton {
                    stopRelaunches += 1
                    if !sawIntentional { stopRelaunchesUnclear += 1 }
                } else if !sawIntentional {
                    unexpected += 1
                }
                sawIntentional = false
            } else if intentionalStops.contains(e.ev) {
                sawIntentional = true
            }
            if let up = e.double("up") { lastUp = up }
        }
        if unexpected > 0 { f.warn.append("app bị khởi động lại ngoài ý muốn (\(unexpected) lần)") }
        if reboots > 0 { f.warn.append("máy khởi động lại giữa lượt (\(reboots) lần) — lượt bị gián đoạn") }
        if stopRelaunches > 0 { f.info.append("app được mở lại để xử lý nút Tắt (\(stopRelaunches) lần)") }
        if stopRelaunchesUnclear > 0 {
            // Review R2-3: expected after a swipe-kill (S3-8); elsewhere it may be a system kill (H1/H5).
            f.info.append("trước lần mở lại do nút Tắt, process trước kết thúc không rõ lý do (\(stopRelaunchesUnclear) lần)")
        }
        let selfExit = inRun.contains { $0.ev == "self_exit_now" }

        // ---- fallback re-arm ----
        let reschedules = inRun.filter { $0.ev == "prearm_reschedule" }
        let rescheduleOk = reschedules.filter { $0.bool("ok") == true }.count
        let rescheduleErr = reschedules.count - rescheduleOk
        if rescheduleErr > 0 { f.warn.append("đặt lại báo dự phòng lỗi \(rescheduleErr) lần") }
        if inRun.contains(where: { $0.ev == "prearm_set" && $0.bool("ok") == false }) {
            f.warn.append("đặt báo dự phòng lỗi")
        }

        // ---- device ----
        let snapshot = inRun.first { $0.ev == "perm_snapshot" }
        var authAtStart: [String: String] = [:]
        for key in ["locAuth", "notifAuth", "timeSensitive", "alarmKitAuth"] {
            if let v = snapshot?.str(key) { authAtStart[key] = v }
        }
        var battery: [Double] = []
        for e in inRun {
            if e.ev == "perm_snapshot", let b = e.double("batt") { battery.append(b) }
            if e.ev == "battery", let b = e.double("lvl") { battery.append(b) }
        }
        let lowPowerSeen = inRun.contains {
            ($0.ev == "perm_snapshot" && $0.bool("lowPower") == true) || ($0.ev == "lowpower" && $0.bool("on") == true)
        }
        let channelAuthKey = channel == "AK" ? "alarmKitAuth" : "notifAuth"
        if let auth = authAtStart[channelAuthKey], auth != "authorized" {
            f.warn.append("quyền kênh \(channel) lúc bắt đầu: \(auth)")
        }
        if channel != "AK", let ts = authAtStart["timeSensitive"], ts != "enabled" {
            f.info.append("Time Sensitive = \(ts)")
        }

        // ---- alarm ----
        var alarm = AlarmResult(planned: planned)
        let trigger = inRun.first { $0.ev == "alarm_trigger" }
        // Ring evidence (time, kind): ak_state alerting, alarm_stop (not user_stop/timeout), notif_delivered.
        var evidence: [(Date, String)] = []
        // Real ring times only (no alarm_stop: that is when the user pressed Stop).
        var ringTimes: [(Date, String)] = []
        for e in inRun {
            switch e.ev {
            case "ak_state" where e.str("state") == "alerting":
                alarm.alertingSeen = true
                evidence.append((e.t, e.str("kind") ?? ""))
                ringTimes.append((e.t, e.str("kind") ?? ""))
            case "alarm_stop" where e.str("via") != "user_stop" && e.str("via") != "timeout":
                evidence.append((e.t, e.str("kind") ?? ""))
            case "notif_delivered":
                let at = e.date("deliveredAt") ?? e.t
                alarm.delivered.append(at)
                evidence.append((at, e.str("kind") ?? ""))
                ringTimes.append((at, e.str("kind") ?? ""))
            default:
                break
            }
        }
        alarm.delivered.sort()
        evidence.sort { $0.0 < $1.0 }
        ringTimes.sort { $0.0 < $1.0 }
        let hasEvidence = !evidence.isEmpty
        let hasNowEvidence = evidence.contains { $0.1 == "now" }
        let firstNowRing = ringTimes.first { $0.1 == "now" }?.0
        let firstPrearmRing = ringTimes.first { $0.1 == "prearm" }?.0
        let okPrearms = inRun.filter {
            ($0.ev == "prearm_set" || $0.ev == "prearm_reschedule") && $0.bool("ok") == true
        }
        let prearmAt = okPrearms.last?.date("at") ?? planned.addingTimeInterval(TriggerLogic.prearmDelayS)
        let triggerSrc = trigger?.str("src")
        if triggerSrc == "fix", let trigger {
            alarm.src = "fix"
            alarm.triggeredAt = trigger.t
            let triggerLate = trigger.double("lateMs").map { $0 / 1000 } ?? trigger.t.timeIntervalSince(planned)
            alarm.triggerLateS = triggerLate
            if let ring = firstNowRing {
                let ringLate = ring.timeIntervalSince(planned)
                alarm.ringLateS = ringLate
                alarm.lateS = max(triggerLate, ringLate)
            } else {
                alarm.lateS = triggerLate
            }
        } else if let first = evidence.first, first.1 == "prearm" {
            alarm.src = "prearm"
            alarm.triggeredAt = firstPrearmRing ?? first.0
            if let ring = firstPrearmRing {
                let ringLate = ring.timeIntervalSince(prearmAt)
                alarm.ringLateS = ringLate
                alarm.lateS = ringLate
            } else {
                f.info.append("không đo được giờ kêu của báo dự phòng (chỉ có giờ bấm Tắt)")
            }
        } else if let trigger {
            alarm.src = triggerSrc
            alarm.triggeredAt = trigger.t
        }
        let nowSchedules = inRun.filter { ($0.ev == "ak_schedule" || $0.ev == "notif_add") && $0.str("kind") == "now" }
        if !nowSchedules.isEmpty {
            alarm.scheduleOk = nowSchedules.allSatisfy { $0.bool("ok") == true }
        }
        if let stopEvent = inRun.first(where: { $0.ev == "alarm_stop" }) {
            alarm.stopVia = stopEvent.str("via")
            let ringStart = inRun.first(where: { $0.ev == "ak_state" && $0.str("state") == "alerting" })?.t
                ?? alarm.delivered.first ?? alarm.triggeredAt
            if let ringStart { alarm.stopAfterS = stopEvent.t.timeIntervalSince(ringStart) }
        }

        if ended && trigger == nil && !hasEvidence {
            f.fail.append("không kích hoạt")
        }
        if alarm.scheduleOk == false && !hasEvidence {
            let err = nowSchedules.first { $0.bool("ok") != true }?.str("err") ?? ""
            f.fail.append("đặt báo thức lỗi" + (err.isEmpty ? "" : ": \(err)"))
        }
        let warnLate = channel == "AK" ? lateWarnS : lateWarnTsS
        if let late = alarm.lateS {
            let l = Int(late.rounded())
            if late > lateFailS {
                f.fail.append("trễ \(l) s (> \(Int(lateFailS)) s)")
            } else if late > warnLate {
                f.warn.append("trễ \(l) s (> \(Int(warnLate)) s)")
            }
        }
        if alarm.src == "prearm" { f.warn.append("kích hoạt bằng dự phòng") }
        if trigger != nil && !hasEvidence {
            f.warn.append("đã đặt, chưa có bằng chứng kêu — xem biên bản")
        }
        if alarm.src == "fix" && hasEvidence && !hasNowEvidence {
            f.warn.append("chỉ báo dự phòng kêu; báo đặt lúc kích hoạt chưa có bằng chứng kêu")
        }
        if alarm.src == "fix" && hasNowEvidence && alarm.ringLateS == nil {
            // Review R2-1: only alarm_stop (the Stop press) for kind=now, no real ring time → lateness unknown.
            f.warn.append("không đo được giờ kêu của báo đặt lúc kích hoạt — xem biên bản")
        }
        if f.fail.isEmpty && f.warn.isEmpty {
            // PASS needs src=fix, a successful schedule and ring evidence (§6.7).
            if alarm.src != "fix" || alarm.scheduleOk != true || !hasNowEvidence {
                var missing: [String] = []
                if alarm.src != "fix" { missing.append("chưa kích hoạt từ vị trí") }
                if alarm.scheduleOk == false { missing.append("đặt báo thức có lỗi") }
                if alarm.scheduleOk == nil { missing.append("không có log đặt báo thức") }
                if !hasNowEvidence { missing.append("chưa có bằng chứng kêu của báo đặt lúc kích hoạt") }
                f.warn.append("chưa đủ điều kiện PASS: " + missing.joined(separator: ", "))
            }
        }

        return RunSummary(
            runId: start.run,
            scenario: scenario,
            channel: channel,
            ios: start.str("ios") ?? "",
            model: start.str("model") ?? "",
            durationS: endT.timeIntervalSince(startT),
            stoppedBy: stoppedBy,
            fixCount: fixCount,
            fixGapMaxS: fixGapMax,
            launches: launches,
            unexpectedRelaunches: unexpected,
            stopButtonRelaunches: stopRelaunches,
            reboots: reboots,
            selfExit: selfExit,
            rescheduleOk: rescheduleOk,
            rescheduleErr: rescheduleErr,
            batteryStart: battery.first,
            batteryEnd: battery.last,
            lowPowerSeen: lowPowerSeen,
            authAtStart: authAtStart,
            alarm: alarm,
            verdict: f.verdict,
            reasons: f.fail + f.warn + f.info.map { "(thông tin) " + $0 }
        )
    }

    private static func noRunStart(_ events: [ProbeEvent]) -> RunSummary {
        RunSummary(
            runId: events.first?.run ?? "",
            scenario: "?", channel: "?", ios: "", model: "",
            durationS: 0, stoppedBy: nil,
            fixCount: [.sparse: 0, .dense: 0], fixGapMaxS: [.sparse: 0, .dense: 0],
            launches: 0, unexpectedRelaunches: 0, stopButtonRelaunches: 0, reboots: 0, selfExit: false,
            rescheduleOk: 0, rescheduleErr: 0,
            batteryStart: nil, batteryEnd: nil, lowPowerSeen: false,
            authAtStart: [:], alarm: AlarmResult(),
            verdict: .FAIL, reasons: ["không có run_start trong log"]
        )
    }

    /// Multi-line Vietnamese text; the last line is "Gợi ý: PASS/WARN/FAIL — lý do".
    /// Times use `offsetSeconds` (device time zone by default).
    public static func render(_ s: RunSummary, offsetSeconds: Int? = nil) -> String {
        func clock(_ d: Date?) -> String {
            guard let d else { return "—" }
            return IsoTime.clock(d, offsetSeconds: offsetSeconds ?? TimeZone.current.secondsFromGMT(for: d))
        }
        func yesNo(_ b: Bool) -> String { b ? "có" : "không" }
        func pct(_ v: Double?) -> String {
            guard let v else { return "?" }
            return "\(Int(v.rounded()))%"
        }
        let a = s.alarm
        var lines: [String] = []
        lines.append("Lượt: \(s.runId)")
        lines.append("Kịch bản: \(s.scenario) · Kênh: \(s.channel) · iOS \(s.ios) · \(s.model)")
        lines.append("Thời lượng: \(DurationText.vi(s.durationS)) · Kết thúc: \(s.stoppedBy ?? "chưa kết thúc")")
        let auth = s.authAtStart
        lines.append(
            "Quyền lúc bắt đầu: vị trí=\(auth["locAuth"] ?? "?"), thông báo=\(auth["notifAuth"] ?? "?"), "
                + "Time Sensitive=\(auth["timeSensitive"] ?? "?"), AlarmKit=\(auth["alarmKitAuth"] ?? "?")"
        )
        let sc = s.fixCount[.sparse] ?? 0
        let dc = s.fixCount[.dense] ?? 0
        let sg = Int((s.fixGapMaxS[.sparse] ?? 0).rounded())
        let dg = Int((s.fixGapMaxS[.dense] ?? 0).rounded())
        lines.append("Vị trí: pha thưa \(sc) điểm (trống tối đa \(sg) s) · pha dày \(dc) điểm (trống tối đa \(dg) s)")
        lines.append(
            "Khởi động app trong lượt: \(s.launches) (ngoài ý muốn: \(s.unexpectedRelaunches), do nút Tắt: "
                + "\(s.stopButtonRelaunches), sau khi máy khởi động lại: \(s.reboots)) · Tự thoát: \(yesNo(s.selfExit))"
        )
        lines.append("Báo dự phòng đặt lại: được \(s.rescheduleOk), lỗi \(s.rescheduleErr)")
        lines.append("Pin: \(pct(s.batteryStart)) → \(pct(s.batteryEnd)) · Nguồn điện thấp: \(yesNo(s.lowPowerSeen))")
        var alarmLine = "Báo thức: mốc \(clock(a.planned)) · kích hoạt \(clock(a.triggeredAt)) (nguồn: \(a.src ?? "—"))"
        if let late = a.lateS { alarmLine += " · trễ \(Int(late.rounded())) s" }
        if let tl = a.triggerLateS { alarmLine += " (callback vị trí sau mốc \(Int(tl.rounded())) s)" }
        let sched: String
        switch a.scheduleOk {
        case .some(true): sched = "được"
        case .some(false): sched = "lỗi"
        case .none: sched = "—"
        }
        alarmLine += " · đặt: \(sched)"
        lines.append(alarmLine)
        lines.append(
            "AlarmKit kêu (alerting): \(yesNo(a.alertingSeen)) · Thông báo đã giao: \(a.delivered.count)"
                + (a.delivered.isEmpty ? "" : " (" + a.delivered.map { clock($0) }.joined(separator: ", ") + ")")
        )
        if let via = a.stopVia {
            var stopLine = "Tắt: \(via)"
            if let after = a.stopAfterS { stopLine += " sau \(DurationText.vi(after))" }
            lines.append(stopLine)
        }
        if !s.reasons.isEmpty {
            lines.append("Lý do:")
            for r in s.reasons { lines.append("- \(r)") }
        }
        let main = s.reasons.filter { !$0.hasPrefix("(thông tin)") }
        let why = main.isEmpty ? "đạt mọi tiêu chí" : main.joined(separator: "; ")
        lines.append("Gợi ý: \(s.verdict.rawValue) — \(why)")
        return lines.joined(separator: "\n")
    }
}
