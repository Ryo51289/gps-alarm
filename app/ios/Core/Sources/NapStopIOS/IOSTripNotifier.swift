// Trip notices (docs/specs/T17.md §5.10): UNUserNotificationCenter, id "napstop.<tripId>.<kind>", userInfo tripId only.
// No delegate is registered (Flutter plugins own it). Texts from NativeCopy (D19).
#if os(iOS)
import Foundation
import Trip
import TripRuntime
import UserNotifications

public final class IOSTripNotifier: TripNotifier, @unchecked Sendable {
    let locale: @Sendable () -> String
    static let kinds = ["noGpsYet", "permissionRevoked", "servicesOff", "fallbackFailed", "interrupted", "preAlert", "ringFailed"]

    public init(locale: @escaping @Sendable () -> String) { self.locale = locale }

    static func id(_ tripId: String, _ kind: String) -> String { "napstop.\(tripId).\(kind)" }

    public func show(tripId: String, _ notice: TripNotice, destinationName: String?) async {
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings()
        guard s.authorizationStatus == .authorized || s.authorizationStatus == .ephemeral else { return }
        let text = NativeCopy.notice(notice, destinationName: destinationName, locale: locale())
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.interruptionLevel = .active
        content.userInfo = ["tripId": tripId]
        if case .preAlert = notice { content.sound = .default }
        try? await center.add(UNNotificationRequest(identifier: Self.id(tripId, notice.kindName), content: content, trigger: nil))
    }

    public func clear(tripId: String, _ notice: TripNotice) async {
        let ids = [Self.id(tripId, notice.kindName)]
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ids)
        c.removeDeliveredNotifications(withIdentifiers: ids)
    }

    public func clearAll(tripId: String) async {
        let ids = Self.kinds.map { Self.id(tripId, $0) }
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ids)
        c.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// Diagnostics journal (§5.13): NDJSON in Documents/napstop_diag/, rotated at 5 MB. Fields never hold coordinates,
/// distances or the destination name (the runtime only records such fields). Enabled only through RuntimeOptions.
public final class FileJournal: RuntimeJournal, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.napstop.diag.journal", qos: .utility)
    private let url: URL
    private let maxBytes: Int
    private let time = IOSTime()

    public init(maxBytes: Int = RuntimeConstants.default.journalMaxBytes) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("napstop_diag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("journal.ndjson")
        self.maxBytes = maxBytes
    }

    public func record(_ event: String, _ fields: [String: String]) {
        var obj: [String: String] = fields
        obj["ev"] = event
        obj["w"] = String(time.wallMs())
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        let url = self.url, maxBytes = self.maxBytes
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = url.deletingLastPathComponent().appendingPathComponent("journal.1.ndjson")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile()
            h.write(d + Data("\n".utf8))
            try? h.close()
        }
    }
}
#endif
