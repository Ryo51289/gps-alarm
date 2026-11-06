import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// NTR30 (docs/specs/T17.3.md): the ITR30 cases with no AlarmKit (iOS 16–25 / AlarmKit denied), every alarm on the
/// notification channel (3 requests, no alarmUpdates, D5 polls). Same expect.json windows and invariants as ITR30, the
/// first alarm with the same reason as the Kotlin L30 table, the pending requests of the trip within NOTIF_PENDING_BUDGET
/// at all times, and never two logical alarms of the trip alerting at once.
@Suite("NotificationTrace")
struct NotificationTraceTests {
    @Test("NTR30 ITR30 cases on the notification channel", arguments: RuntimeTraceTests.caseIds)
    func ntr30(_ key: String) async throws {
        let r = try await RuntimeTraceTests.runCase(key) { w in
            w.env.channels = ChannelAccess(alarmKit: .unavailable, notifications: true)
        }
        let w = r.world
        let requests = w.alarms.scheduledRequests()
        #expect(!requests.isEmpty && requests.allSatisfy { $0.channel == .notification }, "\(key): notification channel only")
        #expect(w.alarms.center.maxPending <= RuntimeConstants.default.notifPendingBudget,
                "\(key): \(w.alarms.center.maxPending) pending requests")
        #expect(w.alarms.budgetRejections == 0, "\(key): budget refusals")
        #expect(w.alarms.doubleRings == 0, "\(key): two logical alarms of the trip alerting at once")
        #expect(w.alarms.center.snapshot().pending.isEmpty && w.alarms.center.snapshot().delivered.isEmpty,
                "\(key): notifications left after the trip")
        let table = try FirstAlarmTable.load()
        let parts = key.split(separator: "/").map(String.init)
        let row = try #require(table.first { $0.trace == parts[0] && $0.caseId == parts[1] }, "\(key): not in first-alarms.json")
        #expect(r.firstAlarm?.reason.jsonName == row.reason,
                "\(key): first alarm reason \(r.firstAlarm?.reason.jsonName ?? "nil") vs ITR30/Kotlin \(row.reason ?? "nil")")
        let mine = r.firstAlarm.map { $0.atMs - r.startMs }
        if let m = mine, let k = row.atMsRel {
            // A fallback slot is seen at its D5 poll (+1 s) instead of an alarmUpdate.
            #expect(abs(m - k) <= 2_000, "\(key): first alarm at \(m) ms vs \(k) ms")
        } else {
            #expect(mine == nil && row.atMsRel == nil, "\(key): first alarm presence")
        }
        let line = "\(key)\tschedule=\(r.schedules)\tcancel=\(r.cancels)\tmaxPending=\(w.alarms.center.maxPending)\n"
        RTPaths.write("\(RTPaths.reportDir)/ios-notif/\(key.replacingOccurrences(of: "/", with: "__")).txt", line)
    }
}
