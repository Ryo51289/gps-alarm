import Foundation
import XCTest
@testable import ProbeCore

/// Builds synthetic event logs. Times are seconds relative to `start`; every event goes through FlatJson
/// (encode + ProbeEvent.parse) so the traces exercise the real log format.
private struct Trace {
    let start: Date
    let runId: String
    var events: [ProbeEvent] = []
    var seq = 0
    var pid = 100

    init(start: Date = Date(timeIntervalSince1970: 1_793_284_000), runId: String = "20261029-212640-S3-1-AK") {
        self.start = start
        self.runId = runId
    }

    func time(_ s: Double) -> Date { start.addingTimeInterval(s) }

    func iso(_ s: Double) -> String { IsoTime.format(time(s), offsetSeconds: 7 * 3600) }

    mutating func add(_ ev: String, at s: Double, _ fields: [String: JSONScalar] = [:]) {
        seq += 1
        var map = fields
        map["ev"] = .string(ev)
        map["t"] = .string(iso(s))
        if map["up"] == nil { map["up"] = .double(1000 + s) }
        map["run"] = .string(runId)
        map["pid"] = .num(pid)
        map["seq"] = .num(seq)
        map["launch"] = .string("L\(pid)")
        let line = try! FlatJson.encode(map)
        events.append(try! ProbeEvent.parse(line))
    }

    mutating func runStart(channel: String = "AK", scenario: String = "S3-1", delayMin: Int = 2,
                           durationMin: Int? = nil, densePhaseMin: Int? = nil) {
        let duration = durationMin ?? delayMin
        add("run_start", at: 0, [
            "scenario": .string(scenario), "channel": .string(channel), "delayMin": .num(delayMin),
            "durationMin": .num(duration), "densePhaseMin": .num(densePhaseMin ?? duration), "prearm": true,
            "deadline": .string(iso(Double(duration * 60))), "ios": "27.0", "model": "iPhone17,4",
        ])
    }

    mutating func snapshot(at s: Double = 0.5, alarmKit: String = "authorized", notif: String = "authorized",
                           timeSensitive: String = "disabled", batt: Double = 90) {
        add("perm_snapshot", at: s, [
            "locAuth": "whenInUse", "notifAuth": .string(notif), "timeSensitive": .string(timeSensitive),
            "alarmKitAuth": .string(alarmKit), "lowPower": false, "batt": .num(batt),
        ])
    }

    mutating func fixes(from a: Double, to b: Double, every step: Double = 1) {
        var s = a
        var n = 0
        while s <= b {
            n += 1
            add("fix", at: s, ["n": .num(n), "acc": 5.0, "spd": .null, "ageMs": 120, "dM": .null])
            s += step
        }
    }

    mutating func newProcess(at s: Double) {
        pid += 1
        seq = 0
        add("proc_start", at: s, ["appState": "background", "activeRun": .string(runId), "prevCleanExit": false])
    }
}

final class RunAnalyzerTests: XCTestCase {
    private let deadline = 120.0

    /// U7: S3-1 happy path on AlarmKit.
    private func passingAlarmKitRun() -> Trace {
        var tr = Trace()
        tr.runStart()
        tr.snapshot()
        tr.add("prearm_set", at: 0.6, ["channel": "AK", "at": .string(tr.iso(180)), "ok": true, "err": .null, "ms": 12])
        tr.fixes(from: 1, to: deadline + 45)
        tr.add("alarm_trigger", at: deadline + 3, [
            "src": "fix", "planned": .string(tr.iso(deadline)), "lateMs": 3000, "appState": "background",
            "protectedData": false,
        ])
        tr.add("ak_schedule", at: deadline + 3.2, [
            "kind": "now", "id": "A1", "fireAt": .string(tr.iso(deadline + 8)), "ok": true, "err": .null, "ms": 30,
        ])
        tr.add("ak_state", at: deadline + 8, ["id": "A1", "kind": "now", "state": "alerting"])
        tr.add("alarm_stop", at: deadline + 48, ["via": "intent", "id": "A1", "kind": "now"])
        tr.add("run_stop", at: deadline + 48.5, ["by": "alarm_stopped"])
        return tr
    }

    func testU7PassingAlarmKitRun() throws {
        let tr = passingAlarmKitRun()
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.alarm.src, "fix")
        // Lateness = ring (ak_state alerting kind=now at +8) − deadline, not the callback (+3).
        XCTAssertEqual(try XCTUnwrap(s.alarm.lateS), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.alarm.triggerLateS), 3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.alarm.ringLateS), 8, accuracy: 0.001)
        XCTAssertTrue(s.alarm.alertingSeen)
        XCTAssertEqual(s.alarm.scheduleOk, true)
        XCTAssertEqual(s.alarm.stopVia, "intent")
        XCTAssertEqual(try XCTUnwrap(s.alarm.stopAfterS), 40, accuracy: 0.5)
        XCTAssertEqual(s.verdict, .PASS, "reasons: \(s.reasons)")
        XCTAssertEqual(s.stoppedBy, "alarm_stopped")
        XCTAssertEqual(s.scenario, "S3-1")
        XCTAssertEqual(s.fixCount[.sparse], 0)
        XCTAssertEqual(s.fixCount[.dense], 165)
        XCTAssertLessThanOrEqual(try XCTUnwrap(s.fixGapMaxS[.dense]), 1.001)
        XCTAssertEqual(s.unexpectedRelaunches, 0)
        XCTAssertEqual(s.authAtStart["alarmKitAuth"], "authorized")
        XCTAssertEqual(s.batteryStart, 90)
    }

    /// U8: S3-6, location stopped by the user, the fallback alarm rings, stopped from a new process.
    func testU8FallbackAlarmIsWarn() {
        var tr = Trace(runId: "20261029-212640-S3-6-AK")
        tr.runStart(scenario: "S3-6")
        tr.snapshot()
        tr.fixes(from: 1, to: 10)
        tr.add("loc_suspend_user", at: 11)
        tr.add("loc_stop", at: 11.1, ["phase": "dense", "accuracy": "best", "bgSession": false])
        tr.add("app_state", at: 15, ["state": "background"])
        tr.newProcess(at: deadline + 70)
        tr.add("alarm_stop", at: deadline + 75, ["via": "intent", "id": "P1", "kind": "prearm"])
        tr.add("run_stop", at: deadline + 75.5, ["by": "alarm_stopped"])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.alarm.src, "prearm")
        XCTAssertEqual(s.stopButtonRelaunches, 1)
        XCTAssertEqual(s.verdict, .WARN, "reasons: \(s.reasons)")
        XCTAssertTrue(s.reasons.contains("kích hoạt bằng dự phòng"), "reasons: \(s.reasons)")
        XCTAssertEqual(s.unexpectedRelaunches, 0)
        XCTAssertEqual(s.launches, 1)
        XCTAssertFalse(s.reasons.contains { $0.hasPrefix("mất vị trí") })
        // Review #4: only the Stop time is known, so the fallback's lateness is not measured (no false "trễ").
        XCTAssertNil(s.alarm.lateS)
        XCTAssertFalse(s.reasons.contains { $0.hasPrefix("trễ") }, "reasons: \(s.reasons)")
    }

    /// Review R2-1: U7 without the `ak_state alerting` line: only the Stop press is known → not PASS.
    func testFixRunWithoutRingTimeIsNotPass() {
        var tr = passingAlarmKitRun()
        tr.events.removeAll { $0.ev == "ak_state" }
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.alarm.src, "fix")
        XCTAssertNil(s.alarm.ringLateS)
        XCTAssertNotEqual(s.verdict, .PASS, "reasons: \(s.reasons)")
        XCTAssertTrue(
            s.reasons.contains("không đo được giờ kêu của báo đặt lúc kích hoạt — xem biên bản"), "reasons: \(s.reasons)"
        )
    }

    /// Review #1(a): the callback was on time but the "now" alarm only alerted 70 s after the deadline → not PASS.
    func testLateRingIsJudgedNotTheCallback() throws {
        var tr = Trace()
        tr.runStart()
        tr.snapshot()
        tr.fixes(from: 1, to: deadline + 90)
        tr.add("alarm_trigger", at: deadline + 3, [
            "src": "fix", "planned": .string(tr.iso(deadline)), "lateMs": 3000, "appState": "background",
            "protectedData": false,
        ])
        tr.add("ak_schedule", at: deadline + 3.2, ["kind": "now", "id": "A1", "ok": true])
        tr.add("ak_state", at: deadline + 70, ["id": "A1", "kind": "now", "state": "alerting"])
        tr.add("alarm_stop", at: deadline + 90, ["via": "intent", "id": "A1", "kind": "now"])
        tr.add("run_stop", at: deadline + 90.5, ["by": "alarm_stopped"])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(try XCTUnwrap(s.alarm.lateS), 70, accuracy: 0.001)
        XCTAssertEqual(s.verdict, .WARN, "reasons: \(s.reasons)")
        XCTAssertTrue(s.reasons.contains("trễ 70 s (> 15 s)"), "reasons: \(s.reasons)")
    }

    /// Review #1(b): fix-triggered run where only the fallback (kind=prearm) rang → not PASS.
    func testOnlyFallbackEvidenceInFixRunIsNotPass() {
        var tr = Trace()
        tr.runStart()
        tr.snapshot()
        tr.add("prearm_set", at: 0.6, ["channel": "AK", "at": .string(tr.iso(deadline + 60)), "ok": true])
        tr.fixes(from: 1, to: deadline + 90)
        tr.add("alarm_trigger", at: deadline + 2, [
            "src": "fix", "planned": .string(tr.iso(deadline)), "lateMs": 2000, "appState": "background",
            "protectedData": false,
        ])
        tr.add("ak_schedule", at: deadline + 2.1, ["kind": "now", "id": "A1", "ok": true])
        tr.add("ak_state", at: deadline + 60, ["id": "P1", "kind": "prearm", "state": "alerting"])
        tr.add("alarm_stop", at: deadline + 80, ["via": "intent", "id": "P1", "kind": "prearm"])
        tr.add("run_stop", at: deadline + 80.5, ["by": "alarm_stopped"])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.alarm.src, "fix")
        XCTAssertNotEqual(s.verdict, .PASS, "reasons: \(s.reasons)")
        XCTAssertTrue(
            s.reasons.contains("chỉ báo dự phòng kêu; báo đặt lúc kích hoạt chưa có bằng chứng kêu"),
            "reasons: \(s.reasons)"
        )
    }

    /// Review #4: the fallback's lateness is measured against its own time (prearm `at`), from a real ring event.
    func testFallbackLatenessAgainstPrearmTime() throws {
        var tr = Trace(runId: "20261029-212640-S3-7-AK")
        tr.runStart(scenario: "S3-7")
        tr.snapshot()
        tr.add("prearm_set", at: 0.6, ["channel": "AK", "at": .string(tr.iso(deadline + 60)), "ok": true])
        tr.fixes(from: 1, to: 30)
        tr.add("self_exit_scheduled", at: 31)
        tr.add("self_exit_now", at: 61)
        tr.newProcess(at: deadline + 61)
        tr.add("ak_state", at: deadline + 62, ["id": "P1", "kind": "prearm", "state": "alerting"])
        tr.add("alarm_stop", at: deadline + 85, ["via": "intent", "id": "P1", "kind": "prearm"])
        tr.add("run_stop", at: deadline + 85.5, ["by": "alarm_stopped"])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.alarm.src, "prearm")
        XCTAssertEqual(try XCTUnwrap(s.alarm.lateS), 2, accuracy: 0.001)
        XCTAssertEqual(s.verdict, .WARN)
        XCTAssertFalse(s.reasons.contains { $0.hasPrefix("trễ") }, "reasons: \(s.reasons)")
        XCTAssertEqual(s.unexpectedRelaunches, 0)
        XCTAssertTrue(s.selfExit)
    }

    /// Review #5: S3-8, app swiped away (no will_terminate), then opened by the system for the Stop button.
    func testStopButtonRelaunchIsNotUnexpected() {
        var tr = Trace(runId: "20261029-212640-S3-8-AK")
        tr.runStart(scenario: "S3-8")
        tr.snapshot()
        tr.fixes(from: 1, to: 20)
        tr.newProcess(at: deadline + 70)
        tr.add("run_resume", at: deadline + 70.2, ["appState": "background"])
        tr.add("alarm_stop", at: deadline + 72, ["via": "intent", "id": "P1", "kind": "prearm"])
        tr.add("run_stop", at: deadline + 72.5, ["by": "alarm_stopped"])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.unexpectedRelaunches, 0)
        XCTAssertEqual(s.stopButtonRelaunches, 1)
        XCTAssertFalse(s.reasons.contains { $0.hasPrefix("app bị khởi động lại") }, "reasons: \(s.reasons)")
        XCTAssertTrue(s.reasons.contains("(thông tin) app được mở lại để xử lý nút Tắt (1 lần)"), "reasons: \(s.reasons)")
        // Review R2-3: no will_terminate before the relaunch → flagged as info, not WARN.
        XCTAssertTrue(
            s.reasons.contains("(thông tin) trước lần mở lại do nút Tắt, process trước kết thúc không rõ lý do (1 lần)"),
            "reasons: \(s.reasons)"
        )
    }

    /// Review #8: system uptime going backwards at a proc_start = the device rebooted mid-run.
    func testRebootMidRunIsReported() {
        var tr = passingAlarmKitRun()
        tr.pid += 1
        tr.seq = 0
        tr.add("proc_start", at: 60, ["appState": "background", "up": 12.5])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.reboots, 1)
        XCTAssertEqual(s.unexpectedRelaunches, 0)
        XCTAssertEqual(s.verdict, .WARN)
        XCTAssertTrue(s.reasons.contains("máy khởi động lại giữa lượt (1 lần) — lượt bị gián đoạn"), "reasons: \(s.reasons)")
    }

    /// U9: nothing fired, 200 s after the deadline, run not stopped.
    func testU9NoTriggerIsFail() {
        var tr = Trace()
        tr.runStart()
        tr.snapshot()
        tr.fixes(from: 1, to: deadline + 200)
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(deadline + 200))
        XCTAssertEqual(s.verdict, .FAIL)
        XCTAssertTrue(s.reasons.contains("không kích hoạt"), "reasons: \(s.reasons)")
        XCTAssertNil(s.stoppedBy)
    }

    func testRunStillPendingIsNotFail() {
        var tr = Trace()
        tr.runStart()
        tr.snapshot()
        tr.fixes(from: 1, to: 60)
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(61))
        XCTAssertNotEqual(s.verdict, .FAIL, "reasons: \(s.reasons)")
        XCTAssertTrue(s.reasons.contains("(thông tin) lượt đang chạy"))
    }

    /// U10: TS channel, three notifications delivered (read on the next app open).
    private func tsRun(timeSensitive: String) -> Trace {
        var tr = Trace(runId: "20261029-212640-S3-9-TS")
        tr.runStart(channel: "TS", scenario: "S3-9")
        tr.snapshot(timeSensitive: timeSensitive)
        tr.fixes(from: 1, to: deadline + 70)
        tr.add("alarm_trigger", at: deadline + 4, [
            "src": "fix", "planned": .string(tr.iso(deadline)), "lateMs": 4000, "appState": "background",
            "protectedData": false,
        ])
        for (k, delay) in [0.0, 30, 60].enumerated() {
            tr.add("notif_add", at: deadline + 4.1, [
                "kind": "now", "id": .string("N\(k)"), "fireAt": .string(tr.iso(deadline + 4 + delay)), "ok": true,
                "err": .null,
            ])
        }
        tr.add("app_state", at: deadline + 90, ["state": "active"])
        for (k, delay) in [4.0, 34, 64].enumerated() {
            tr.add("notif_delivered", at: deadline + 90.5, [
                "kind": "now", "id": .string("N\(k)"), "deliveredAt": .string(tr.iso(deadline + delay)),
            ])
        }
        tr.add("run_stop", at: deadline + 95, ["by": "user"])
        return tr
    }

    func testU10TimeSensitiveRunPasses() throws {
        let tr = tsRun(timeSensitive: "enabled")
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.alarm.delivered.count, 3)
        XCTAssertEqual(try XCTUnwrap(s.alarm.lateS), 4, accuracy: 0.001)
        XCTAssertEqual(s.verdict, .PASS, "reasons: \(s.reasons)")
        XCTAssertFalse(s.reasons.contains { $0.contains("Time Sensitive") })
    }

    func testU10TimeSensitiveNotSupportedAddsReasonButPasses() {
        let tr = tsRun(timeSensitive: "notSupported")
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.verdict, .PASS, "reasons: \(s.reasons)")
        XCTAssertTrue(s.reasons.contains("(thông tin) Time Sensitive = notSupported"), "reasons: \(s.reasons)")
    }

    /// U12: a new process mid-run with no intentional stop before it.
    func testU12UnexpectedRelaunchIsWarn() {
        var tr = passingAlarmKitRun()
        tr.newProcess(at: 60)
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.unexpectedRelaunches, 1)
        XCTAssertEqual(s.verdict, .WARN)
        XCTAssertTrue(s.reasons.contains("app bị khởi động lại ngoài ý muốn (1 lần)"), "reasons: \(s.reasons)")
    }

    /// U13: long run, dense-phase gap of 200 s → FAIL; 90 s → WARN.
    private func longRun(denseGap: Double) -> Trace {
        var tr = Trace(runId: "20261029-212640-S3-12-AK")
        tr.runStart(scenario: "S3-12", delayMin: 30, durationMin: 30, densePhaseMin: 10)
        tr.snapshot()
        let end = 1800.0
        let denseStart = 1200.0
        tr.fixes(from: 30, to: denseStart - 1, every: 60)            // sparse: one fix a minute
        let gapStart = 1500.0
        tr.fixes(from: denseStart, to: gapStart)
        tr.fixes(from: gapStart + denseGap, to: end + 40)
        tr.add("alarm_trigger", at: end + 2, [
            "src": "fix", "planned": .string(tr.iso(end)), "lateMs": 2000, "appState": "background",
            "protectedData": false,
        ])
        tr.add("ak_schedule", at: end + 2.1, ["kind": "now", "id": "A1", "fireAt": .string(tr.iso(end + 7)), "ok": true])
        tr.add("ak_state", at: end + 7, ["id": "A1", "kind": "now", "state": "alerting"])
        tr.add("alarm_stop", at: end + 30, ["via": "intent", "id": "A1", "kind": "now"])
        tr.add("run_stop", at: end + 31, ["by": "alarm_stopped"])
        return tr
    }

    func testU13DenseGapFailAndWarn() {
        let failRun = longRun(denseGap: 200)
        let f = RunAnalyzer.analyze(failRun.events, now: failRun.time(4000))
        XCTAssertEqual(f.verdict, .FAIL)
        XCTAssertTrue(f.reasons.contains("mất vị trí 200 s ở pha dày"), "reasons: \(f.reasons)")

        let warnRun = longRun(denseGap: 90)
        let w = RunAnalyzer.analyze(warnRun.events, now: warnRun.time(4000))
        XCTAssertEqual(w.verdict, .WARN, "reasons: \(w.reasons)")
        XCTAssertTrue(w.reasons.contains("khoảng trống vị trí 90 s ở pha dày"), "reasons: \(w.reasons)")
        XCTAssertGreaterThan(w.fixCount[.sparse] ?? 0, 0)
    }

    func testDenseGapIgnoredAfterIntentionalStop() {
        var tr = longRun(denseGap: 200)
        tr.add("loc_suspend_user", at: 1400)
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(4000))
        XCTAssertFalse(s.reasons.contains { $0.hasPrefix("mất vị trí") }, "reasons: \(s.reasons)")
    }

    /// U14: AlarmKit schedule failed, no evidence of ringing.
    func testU14ScheduleErrorIsFail() {
        var tr = Trace()
        tr.runStart()
        tr.snapshot()
        tr.fixes(from: 1, to: deadline + 30)
        tr.add("alarm_trigger", at: deadline + 1, [
            "src": "fix", "planned": .string(tr.iso(deadline)), "lateMs": 1000, "appState": "background",
            "protectedData": false,
        ])
        tr.add("ak_schedule", at: deadline + 1.1, [
            "kind": "now", "id": "A1", "fireAt": .string(tr.iso(deadline + 6)), "ok": false,
            "err": "maximumLimitReached",
        ])
        tr.add("run_stop", at: deadline + 200, ["by": "user"])
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.verdict, .FAIL)
        XCTAssertEqual(s.alarm.scheduleOk, false)
        XCTAssertTrue(s.reasons.contains { $0.hasPrefix("đặt báo thức lỗi") }, "reasons: \(s.reasons)")
    }

    /// U15: one failed re-arm out of 120.
    func testU15RescheduleErrorIsWarn() {
        var tr = passingAlarmKitRun()
        for k in 0..<120 {
            let ok = k != 57
            tr.add("prearm_reschedule", at: 1 + Double(k) * 0.5, [
                "channel": "AK", "at": .string(tr.iso(180)), "ok": .flag(ok), "err": ok ? JSONScalar.null : JSONScalar.string("boom"), "ms": 20,
            ])
        }
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(600))
        XCTAssertEqual(s.rescheduleOk, 119)
        XCTAssertEqual(s.rescheduleErr, 1)
        XCTAssertEqual(s.verdict, .WARN)
    }

    /// U16: rendered summary of U7.
    func testU16RenderEndsWithVerdictAndHasNoCoordinates() {
        let tr = passingAlarmKitRun()
        let text = RunAnalyzer.render(RunAnalyzer.analyze(tr.events, now: tr.time(600)), offsetSeconds: 7 * 3600)
        let last = text.split(separator: "\n").last.map { String($0) } ?? ""
        XCTAssertTrue(last.hasPrefix("Gợi ý: PASS"), text)
        XCTAssertFalse(text.lowercased().contains("lat"), text)
        XCTAssertFalse(text.lowercased().contains("lng"), text)
        XCTAssertTrue(text.contains("mốc 21:28:40"), text)
    }

    func testNoRunStartIsFail() {
        var tr = Trace()
        tr.add("proc_start", at: 0)
        let s = RunAnalyzer.analyze(tr.events, now: tr.time(10))
        XCTAssertEqual(s.verdict, .FAIL)
    }

    func testParseLinesCountsCorruptLines() {
        let tr = passingAlarmKitRun()
        var text = ""
        for e in tr.events.prefix(3) {
            text += (try! FlatJson.encode(e.fields)) + "\n"
        }
        text += "{\"ev\":\"fix\",\"t\":\"2026-10-29T21:2\n\n"
        let parsed = ProbeEvent.parseLines(text)
        XCTAssertEqual(parsed.events.count, 3)
        XCTAssertEqual(parsed.corrupt, 1)
    }
}
