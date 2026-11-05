// Files of the trip runtime (docs/specs/T17.md D15, §5.7): Library/Application Support/napstop_trip/, excluded from
// backup, protection completeUntilFirstUserAuthentication, JSON, atomic writes. Never logs content.
#if os(iOS)
import Foundation
import Trip
import TripRuntime

public final class FileRuntimeStore: RuntimeStore, @unchecked Sendable {
    public let dir: URL
    private let lock = NSLock()
    private let warn: @Sendable (String) -> Void

    public init(dir: URL? = nil, warn: @escaping @Sendable (String) -> Void) {
        self.warn = warn
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.dir = dir ?? base.appendingPathComponent("napstop_trip", isDirectory: true)
        Self.prepare(self.dir)
        Self.prepare(self.dir.appendingPathComponent("finished", isDirectory: true))
    }

    static func prepare(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true  // [I-BAK]
        try? u.setResourceValues(values)
    }

    private var activeURL: URL { dir.appendingPathComponent("active_trip.json") }
    private var ledgerURL: URL { dir.appendingPathComponent("alarm_ledger.json") }
    private var eventsURL: URL { dir.appendingPathComponent("ring_events.json") }
    private var launchActionURL: URL { dir.appendingPathComponent("launch_action.json") }
    private var finishedDir: URL { dir.appendingPathComponent("finished", isDirectory: true) }
    public var alarmRefsURL: URL { dir.appendingPathComponent("alarm_refs.json") }

    private func write(_ d: Data, _ url: URL) throws {
        try d.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public func readActive() throws -> StoredTrip? {
        try sync {
            guard let d = try? Data(contentsOf: activeURL) else { return nil }
            do { return try StoredTripCodec.decode(d) } catch {
                try? FileManager.default.removeItem(at: activeURL)
                throw error
            }
        }
    }

    public func writeActive(_ t: StoredTrip) throws { try sync { try write(StoredTripCodec.encode(t), activeURL) } }
    public func deleteActive() { sync { try? FileManager.default.removeItem(at: activeURL) } }

    public func readLedger() -> AlarmLedger {
        sync {
            guard let d = try? Data(contentsOf: ledgerURL) else { return .empty }
            guard let l = try? LedgerCodec.decode(AlarmLedger.self, d) else {
                warn("ledger unreadable")
                return .empty
            }
            return l
        }
    }

    public func writeLedger(_ l: AlarmLedger) throws { try sync { try write(LedgerCodec.encode(l), ledgerURL) } }

    public func readRingEvents() -> [RingEventRec] {
        sync { (try? Data(contentsOf: eventsURL)).flatMap { try? LedgerCodec.decode([RingEventRec].self, $0) } ?? [] }
    }

    public func appendRingEvent(_ e: RingEventRec) throws {
        try sync {
            var all = (try? Data(contentsOf: eventsURL)).flatMap { try? LedgerCodec.decode([RingEventRec].self, $0) } ?? []
            all.append(e)
            if all.count > 16 { all.removeFirst(all.count - 16) }
            try write(LedgerCodec.encode(all), eventsURL)
        }
    }

    public func removeRingEvents(tripId: String) {
        sync {
            var all = (try? Data(contentsOf: eventsURL)).flatMap { try? LedgerCodec.decode([RingEventRec].self, $0) } ?? []
            all.removeAll { $0.tripId == tripId }
            if let d = try? LedgerCodec.encode(all) { try? write(d, eventsURL) }
        }
    }

    public func writeFinished(_ r: FinishedRecord) throws {
        try sync { try write(LedgerCodec.encode(r), finishedDir.appendingPathComponent("\(r.tripId).json")) }
    }

    public func readFinished() -> [FinishedRecord] {
        sync {
            let files = (try? FileManager.default.contentsOfDirectory(at: finishedDir, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "json" }.compactMap {
                (try? Data(contentsOf: $0)).flatMap { try? LedgerCodec.decode(FinishedRecord.self, $0) }
            }
        }
    }

    /// T17.2 D7: same directory (excluded from backup, same file protection).
    public func readLaunchAction() -> LaunchActionRec? {
        sync { (try? Data(contentsOf: launchActionURL)).flatMap { try? LedgerCodec.decode(LaunchActionRec.self, $0) } }
    }

    public func writeLaunchAction(_ r: LaunchActionRec) throws { try sync { try write(LedgerCodec.encode(r), launchActionURL) } }
    public func deleteLaunchAction() { sync { try? FileManager.default.removeItem(at: launchActionURL) } }

    public func deleteFinished(_ ids: [String]) {
        sync {
            for id in ids where !id.contains("/") {
                try? FileManager.default.removeItem(at: finishedDir.appendingPathComponent("\(id).json"))
            }
        }
    }
}
#endif
