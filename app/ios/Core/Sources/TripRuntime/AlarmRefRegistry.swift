// id → (tripId, kind, generation, fireAt) of the alarms this app scheduled (docs/specs/T17.md §4.2; AlarmKit's `Alarm`
// carries no metadata). Persisted next to the ledger. Pure Foundation so the race rules are tested on Linux.
import Foundation

public final class AlarmRefRegistry: @unchecked Sendable {
    public struct Ref: Codable, Equatable, Sendable {
        public let tripId: String
        public let kind: SystemAlarmKind
        public let generation: Int64
        public let fireAtWallMs: Int64
        /// When the ref was written (wall ms); nil in files written before review T17 #2.
        public var putAtWallMs: Int64?

        public init(tripId: String, kind: SystemAlarmKind, generation: Int64, fireAtWallMs: Int64, putAtWallMs: Int64? = nil) {
            self.tripId = tripId
            self.kind = kind
            self.generation = generation
            self.fireAtWallMs = fireAtWallMs
            self.putAtWallMs = putAtWallMs
        }
    }

    private let lock = NSLock()
    private let url: URL?
    private let now: @Sendable () -> Int64
    private let graceMs: Int64
    private var refs: [String: Ref] = [:]
    /// Ids between `beginSchedule` and `endSchedule`: never dropped by `retain`.
    private var pending: Set<String> = []

    /// `graceMs`: a ref younger than this survives `retain` even when the system list does not show it yet (an
    /// `alarmUpdates` snapshot taken before the alarm was added may be handled after `put`, review T17 #2).
    public init(url: URL?, now: @escaping @Sendable () -> Int64, graceMs: Int64 = 120_000) {
        self.url = url
        self.now = now
        self.graceMs = graceMs
        if let url, let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([String: Ref].self, from: d) { refs = r }
    }

    private func save(_ snapshot: [String: Ref]) {
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        if let url, let d = try? LedgerCodec.encode(snapshot) { try? d.write(to: url, options: options) }
    }

    private func mutate(_ body: (inout [String: Ref], inout Set<String>) -> Void) {
        lock.lock()
        body(&refs, &pending)
        let snapshot = refs
        lock.unlock()
        save(snapshot)
    }

    /// Before `AlarmManager.schedule`: the ref exists and is protected until `endSchedule`.
    public func beginSchedule(_ id: String, _ r: Ref) {
        var r = r
        r.putAtWallMs = now()
        mutate { refs, pending in
            refs[id] = r
            pending.insert(id)
        }
    }

    /// After `AlarmManager.schedule` returned (`ok`) or threw.
    public func endSchedule(_ id: String, ok: Bool) {
        let t = now()
        mutate { refs, pending in
            pending.remove(id)
            if ok { refs[id]?.putAtWallMs = t } else { refs[id] = nil }
        }
    }

    public func get(_ id: String) -> Ref? {
        lock.lock()
        defer { lock.unlock() }
        return refs[id]
    }

    /// Drops refs of alarms the system no longer has, except pending ones and refs younger than `graceMs`.
    public func retain(_ ids: Set<String>) {
        let t = now()
        lock.lock()
        let gone = refs.filter { id, r in
            !ids.contains(id) && !pending.contains(id) && (r.putAtWallMs.map { t - $0 > graceMs } ?? true)
        }.map(\.key)
        lock.unlock()
        if gone.isEmpty { return }
        mutate { refs, _ in for g in gone { refs[g] = nil } }
    }
}
