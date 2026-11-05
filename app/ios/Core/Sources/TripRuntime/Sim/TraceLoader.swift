// Loads a bundled trace at start (docs/specs/T18.1.md §5): the blocking read + parse run in a detached task, raced against
// SIM_TRACE_LOAD_BUDGET_MS on the runtime sleeper. Error codes of T18 §11.
import Foundation

enum TraceLoadResult: Sendable {
    case loaded(SimTrace)
    /// `simulation-unavailable` message (TraceNotFound / TraceInvalid / TraceLoadTimeout).
    case failed(String)
}

/// First value wins; later offers are ignored.
final class FirstValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    private var waiter: CheckedContinuation<T, Never>?

    func offer(_ v: T) {
        lock.lock()
        if value != nil { lock.unlock(); return }
        value = v
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(returning: v)
    }

    func wait() async -> T {
        await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
            lock.lock()
            if let v = value { lock.unlock(); c.resume(returning: v); return }
            waiter = c
            lock.unlock()
        }
    }
}

enum TraceLoader {
    static func load(_ id: String, store: TraceStore, sleeper: RuntimeSleeper, budgetMs: Int64) async -> TraceLoadResult {
        let box = FirstValue<TraceLoadResult>()
        Task.detached {
            guard let data = store.open(id) else { return box.offer(.failed("TraceNotFound")) }
            do {
                let samples = try TraceGpx.parse(data)
                box.offer(.loaded(SimTrace(id: id, samples: samples)))
            } catch {
                box.offer(.failed("TraceInvalid"))
            }
        }
        Task {
            await sleeper.sleep(ms: budgetMs)
            box.offer(.failed("TraceLoadTimeout"))
        }
        return await box.wait()
    }
}
