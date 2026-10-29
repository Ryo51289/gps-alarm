import Foundation
import os

/// JSON Lines event log (S3 §6.6): `Documents/runs/<runId>/events.jsonl`, or `Documents/runs/orphan.jsonl` outside a run.
///
/// Callable from any thread. `seq` and the timestamp are taken under a lock and the line is queued in the same critical
/// section, so file order = seq order within a process. A serial queue appends with FileHandle and calls
/// `synchronize()` after important events and at least every 60 s. Lines that cannot be written (protected data
/// unavailable) stay in memory and are retried. Mirrored to `os.Logger` (public: the log never holds coordinates —
/// FlatJson refuses coordinate keys).
final class EventLog: @unchecked Sendable {
    static let shared = EventLog()

    /// Short id of this process launch.
    let launch: String
    let pid: Int
    let runsDir: URL
    /// System uptime when the log was created (≈ process launch: first used in didFinishLaunching).
    let startUptime: TimeInterval

    private let logger = Logger(subsystem: "app.napstop.probe", category: "events")
    private let lock = NSLock()
    private var seq = 0
    private var runId = ""
    private let queue = DispatchQueue(label: "app.napstop.probe.eventlog")

    // Confined to `queue`.
    private var openRun: String?
    private var handle: FileHandle?
    private var pending: [(run: String, line: String)] = []
    private var lastSyncUptime: TimeInterval = 0

    private static let syncPrefixes = ["run_", "alarm_", "ak_", "notif_", "prearm_"]
    private static let syncEvents: Set<String> = ["proc_start", "self_exit_now", "will_terminate", "loc_suspend_user"]
    private static let syncIntervalS: TimeInterval = 60
    private static let maxPending = 20_000
    private static let protection: [FileAttributeKey: Any] = [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
    ]

    private init() {
        startUptime = ProcessInfo.processInfo.systemUptime
        launch = String(UUID().uuidString.prefix(8)).lowercased()
        pid = Int(ProcessInfo.processInfo.processIdentifier)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        runsDir = docs.appendingPathComponent("runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true, attributes: Self.protection)
        try? FileManager.default.setAttributes(Self.protection, ofItemAtPath: runsDir.path)
    }

    /// Run that new events belong to ("" = orphan.jsonl).
    var currentRunId: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return runId
        }
        set {
            lock.lock()
            runId = newValue
            lock.unlock()
        }
    }

    func log(_ ev: String, _ fields: [String: JSONScalar] = [:]) {
        log(to: currentRunId, ev, fields)
    }

    /// Logs into an explicit run ("" = orphan.jsonl), independent of `currentRunId`.
    func log(to run: String, _ ev: String, _ fields: [String: JSONScalar] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        seq += 1
        let now = Date()
        var map = fields
        map["ev"] = .string(ev)
        map["t"] = .string(IsoTime.local(now))
        map["up"] = .double((ProcessInfo.processInfo.systemUptime * 1000).rounded() / 1000)
        map["run"] = .string(run)
        map["pid"] = .num(pid)
        map["seq"] = .num(seq)
        map["launch"] = .string(launch)
        let line: String
        do {
            line = try FlatJson.encode(map)
        } catch {
            // A forbidden (coordinate-like) key: drop the event, keep a trace that it happened.
            logger.error("dropped event \(ev, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        logger.info("\(line, privacy: .public)")
        let sync = Self.syncEvents.contains(ev) || Self.syncPrefixes.contains { ev.hasPrefix($0) }
        queue.async { self.write(run: run, line: line, sync: sync) }
    }

    /// Blocks until everything queued so far is written and fsync'ed (before exit(0), on will_terminate).
    func flushSync() {
        queue.sync { self.flushPending(forceSync: true) }
    }

    /// Retries lines kept in memory (call when protected data becomes available).
    func retryPending() {
        queue.async { self.flushPending(forceSync: true) }
    }

    // MARK: - Writing (queue only)

    private func write(run: String, line: String, sync: Bool) {
        pending.append((run: run, line: line))
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
        flushPending(forceSync: sync)
    }

    private func flushPending(forceSync: Bool) {
        while let first = pending.first {
            do {
                let h = try handleFor(first.run)
                try h.write(contentsOf: Data((first.line + "\n").utf8))
                pending.removeFirst()
            } catch {
                closeHandle()
                logger.error("event log write failed (\(self.pending.count) pending): \(String(describing: error), privacy: .public)")
                return
            }
        }
        let up = ProcessInfo.processInfo.systemUptime
        if forceSync || up - lastSyncUptime >= Self.syncIntervalS {
            try? handle?.synchronize()
            lastSyncUptime = up
        }
    }

    private func handleFor(_ run: String) throws -> FileHandle {
        if let current = handle, openRun == run { return current }
        closeHandle()
        let url = fileURL(run: run)
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: Self.protection
        )
        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: nil, attributes: Self.protection)
        }
        let h = try FileHandle(forWritingTo: url)
        _ = try h.seekToEnd()
        handle = h
        openRun = run
        return h
    }

    private func closeHandle() {
        if let current = handle {
            try? current.synchronize()
            try? current.close()
        }
        handle = nil
        openRun = nil
    }

    // MARK: - Reading

    func fileURL(run: String) -> URL {
        if run.isEmpty { return runsDir.appendingPathComponent("orphan.jsonl") }
        return runsDir.appendingPathComponent(run, isDirectory: true).appendingPathComponent("events.jsonl")
    }

    /// Run ids (directories under runs/), newest first.
    func listRuns() -> [String] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: runsDir.path)) ?? []
        return names.filter { name in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: runsDir.appendingPathComponent(name).path, isDirectory: &isDir) && isDir.boolValue
        }.sorted(by: >)
    }

    func readRun(_ run: String) -> (events: [ProbeEvent], corrupt: Int) {
        flushSync()
        guard let text = try? String(contentsOf: fileURL(run: run), encoding: .utf8) else { return ([], 0) }
        return ProbeEvent.parseLines(text)
    }

    func deleteRun(_ run: String) {
        guard !run.isEmpty else { return }
        queue.sync {
            if self.openRun == run { self.closeHandle() }
        }
        try? FileManager.default.removeItem(at: runsDir.appendingPathComponent(run, isDirectory: true))
    }
}
