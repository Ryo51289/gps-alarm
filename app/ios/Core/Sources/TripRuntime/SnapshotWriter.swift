// Background snapshot writer (docs/specs/T17.md §5.7): always writes the newest snapshot, never throws into the runtime.
import Foundation

/// Resumes its waiter once, whichever of several racers fires first (persistNow: write vs budget, D7).
final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    func fire() {
        lock.lock()
        if fired { lock.unlock(); return }
        fired = true
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired { lock.unlock(); c.resume(); return }
            waiter = c
            lock.unlock()
        }
    }
}

actor SnapshotWriter {
    private let store: RuntimeStore
    private let warn: @Sendable (String) -> Void
    private let journal: RuntimeJournal
    private var pending: StoredTrip?
    private var writing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// The last attempt failed: the runtime writes again at the next Step (§5.7 "thử lại … ở Step kế tiếp").
    private(set) var lastFailed = false
    private(set) var failedAttempts = 0

    init(store: RuntimeStore, warn: @escaping @Sendable (String) -> Void, journal: RuntimeJournal) {
        self.store = store
        self.warn = warn
        self.journal = journal
    }

    func submit(_ t: StoredTrip) {
        pending = t
        if !writing {
            writing = true
            Task { await self.run() }
        }
    }

    private func run() async {
        while let t = pending {
            pending = nil
            let store = self.store
            let result: String? = await Task.detached {
                do {
                    try store.writeActive(t)
                    return nil
                } catch {
                    return String(describing: type(of: error))
                }
            }.value
            if let err = result {
                lastFailed = true
                failedAttempts += 1
                warn("snapshot write failed (\(err))")
                journal.record("persist", ["ok": "false", "err": err])
            } else {
                lastFailed = false
                journal.record("persist", ["ok": "true"])
            }
        }
        writing = false
        let w = waiters
        waiters = []
        for c in w { c.resume() }
    }

    /// Returns when nothing is pending or being written.
    func waitIdle() async {
        if !writing && pending == nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Drops anything not yet started (trip ended) and waits for the write in flight.
    func cancelPendingAndWait() async {
        pending = nil
        await waitIdle()
    }
}
