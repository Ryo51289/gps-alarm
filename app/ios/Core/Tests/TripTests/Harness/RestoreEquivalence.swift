@testable import Trip

/// I8 / P04 (T10 §7.3, T12 §8.5): restore PENDING at a checkpoint, continue with copies of osSim and harness state,
/// and compare every record after the checkpoint with the uninterrupted run.
enum RestoreEquivalence {
    static func checkpoints(duration d: Int, interval i: Int) -> [Int] {
        [(d / 4) / i * i, (d / 2) / i * i, (d * 9 / 10) / i * i]
    }

    /// Runs the case once, capturing runner copies at the checkpoints. Returns the uninterrupted run + captures.
    static func runWithCaptures(_ base: Runner) -> (Runner, [(Int, Runner)]) {
        var main = base
        let fixed = Set(checkpoints(duration: base.duration, interval: base.interval).filter { $0 <= base.duration })
        nonisolated(unsafe) var captures: [(Int, Runner)] = []
        main.runAll { t, copy in
            let alarmPoint = copy.firstAlarmT.map { $0 + copy.interval }
            if fixed.contains(t) || alarmPoint == t {
                if !captures.contains(where: { $0.0 == t }) { captures.append((t, copy)) }
            }
        }
        return (main, captures)
    }

    /// Failure messages for one checkpoint (empty = equivalent).
    static func check(original: Runner, checkpoint c: Int, captured: Runner) -> [String] {
        let tag = "[\(original.run) I8 c=\(c)]"
        guard captured.alive else { return [] }   // engine dead at c: skipped
        var copy = captured
        copy.probes = false   // the uninterrupted run already probed every Step (T10.4)
        let decoded: EngineState
        do { decoded = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(copy.state)) } catch {
            return ["\(tag) snapshot decode failed: \(error)"]
        }
        let step = TripEngine.restore(decoded, nowMs: copy.nowMs(c), info: RestoreInfo(status: .pending))
        if !step.events.isEmpty { return ["\(tag) restore Step has \(step.events.count) events"] }
        copy.state = step.state
        copy.lastView = step.view
        let before = copy.records.count
        copy.runTicks(fromIndex: c / copy.interval + 1, onTickEnd: nil)
        let a = Array(original.records.dropFirst(before)), b = Array(copy.records.dropFirst(before))
        if a.count != b.count { return ["\(tag) record count \(b.count) ≠ \(a.count)"] }
        for (x, y) in zip(a, b) where x.t != y.t || x.input != y.input || x.events != y.events || x.v != y.v {
            return ["\(tag) first difference at t=\(x.t)"]
        }
        return []
    }
}
