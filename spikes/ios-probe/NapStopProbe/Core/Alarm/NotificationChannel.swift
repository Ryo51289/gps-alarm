import CoreLocation
import Foundation
import UserNotifications

/// Time Sensitive notification channel (S3 §6.4): fallback for iOS < 26, also used by channel AU and the walk (S3-13).
final class NotificationChannel: AlarmChannel {
    static let shared = NotificationChannel()
    static let category = "probe_alarm"
    static let stopAction = "probe_stop"

    private let center = UNUserNotificationCenter.current()
    private let store = RunStore.shared
    private let events = EventLog.shared

    func registerCategories() {
        let stop = UNNotificationAction(identifier: Self.stopAction, title: "Tắt", options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.category, actions: [stop], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            events.log("notif_auth", ["granted": .flag(granted)])
            return granted
        } catch {
            events.log("notif_auth", ["granted": false, "err": .str(String(describing: error))])
            return false
        }
    }

    func content(kind: String, runId: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        switch kind {
        case "test":
            c.title = "NapStop Probe — thử thông báo"
            c.body = "Thông báo thử sau 10 giây."
        case "walk":
            c.title = "NapStop Probe — ra khỏi vùng"
            c.body = "Bạn đã đi ra khỏi vùng 200 m."
        default:
            c.title = "NapStop Probe — tới mốc"
            c.body = "Báo thức thử. Bấm Tắt để dừng."
        }
        c.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: ToneFile.fileName))
        c.interruptionLevel = .timeSensitive
        c.categoryIdentifier = Self.category
        c.threadIdentifier = "napstop-probe"
        c.userInfo = ["runId": runId, "kind": kind]
        return c
    }

    /// Adds one request and logs `notif_add`. `after` nil = deliver now.
    @discardableResult
    func add(id: String, kind: String, runId: String, after seconds: TimeInterval?) async -> ScheduleResult {
        var trigger: UNNotificationTrigger?
        if let seconds {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        }
        let request = UNNotificationRequest(identifier: id, content: content(kind: kind, runId: runId), trigger: trigger)
        let start = Date()
        var result = ScheduleResult(ok: true, err: nil, ms: 0)
        do {
            try await center.add(request)
        } catch {
            result.ok = false
            result.err = String(describing: error)
        }
        result.ms = Elapsed.ms(since: start)
        events.log(to: runId, "notif_add", [
            "kind": .str(kind), "id": .str(id), "fireAt": .str(IsoTime.local(start.addingTimeInterval(seconds ?? 0))),
            "ok": .flag(result.ok), "err": .str(result.err),
        ])
        return result
    }

    /// S3-0 quick test: notification 10 s from now, outside any run.
    func test() async {
        await add(id: "test-" + IsoTime.compact(Date(), offsetSeconds: 0), kind: "test", runId: "", after: 10)
    }

    /// S3-13 safety net: notify on leaving the region, even if the app is not running.
    func addLocationTrigger(region: CLRegion, runId: String) async {
        let id = Self.walkId(runId)
        let request = UNNotificationRequest(
            identifier: id, content: content(kind: "walk", runId: runId),
            trigger: UNLocationNotificationTrigger(region: region, repeats: false)
        )
        var err: String?
        do {
            try await center.add(request)
        } catch {
            err = String(describing: error)
        }
        events.log(to: runId, "notif_add", ["kind": "walk", "id": .str(id), "fireAt": .null, "ok": .flag(err == nil), "err": .str(err)])
    }

    // MARK: - ids

    static func prearmId(_ runId: String) -> String { "\(runId)-prearm" }

    static func nowId(_ runId: String, _ k: Int) -> String { "\(runId)-now-\(k)" }

    static func walkId(_ runId: String) -> String { "\(runId)-walk" }

    private static func allIds(_ runId: String) -> [String] {
        [prearmId(runId), walkId(runId)] + (0..<TriggerLogic.tsRepeat).map { nowId(runId, $0) }
    }

    // MARK: - AlarmChannel

    func prearm(at date: Date, runId: String) async -> ScheduleResult {
        await add(id: Self.prearmId(runId), kind: "prearm", runId: runId, after: date.timeIntervalSinceNow)
    }

    /// Same identifier → the pending request is replaced.
    func reschedulePrearm(at date: Date, runId: String) async -> ScheduleResult {
        await add(id: Self.prearmId(runId), kind: "prearm", runId: runId, after: date.timeIntervalSinceNow)
    }

    /// TS_REPEAT requests added at once (now, +30 s, +60 s), so they are delivered even if the app is suspended later.
    /// Review #3 (approved deviation from §6.8): the fallback request is removed only after at least one "now" request
    /// was added successfully.
    func fireNow(runId: String) async {
        var anyOk = false
        for k in 0..<TriggerLogic.tsRepeat {
            let delay: TimeInterval? = k == 0 ? nil : TriggerLogic.tsRepeatIntervalS * Double(k)
            let result = await add(id: Self.nowId(runId, k), kind: "now", runId: runId, after: delay)
            if result.ok { anyOk = true }
        }
        if anyOk {
            center.removePendingNotificationRequests(withIdentifiers: [Self.prearmId(runId)])
        } else {
            events.log(to: runId, "prearm_kept", ["channel": "TS", "reason": "now_failed"])
        }
    }

    func cancelAll(runId: String) async {
        let ids = Self.allIds(runId)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - notif_delivered

    /// Logs delivered notifications not logged yet (on app open / while the run is alive).
    func syncDelivered() async {
        let delivered = await center.deliveredNotifications()
        logDelivered(delivered)
    }

    func logDelivered(_ notifications: [UNNotification]) {
        guard !notifications.isEmpty else { return }
        let fresh = store.claimDelivered(notifications.map { $0.request.identifier })
        for n in notifications where fresh.contains(n.request.identifier) {
            let info = n.request.content.userInfo
            let runId = info["runId"] as? String ?? ""
            events.log(to: runId, "notif_delivered", [
                "kind": .str(info["kind"] as? String ?? "?"), "id": .str(n.request.identifier),
                "deliveredAt": .str(IsoTime.local(n.date)),
            ])
        }
    }
}
