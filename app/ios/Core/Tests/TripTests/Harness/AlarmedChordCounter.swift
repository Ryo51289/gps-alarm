import Foundation
@testable import Trip

/// T10.7 §10 (T13 "T10.7" #7; Kotlin `harness/AlarmedChordCounter.kt`): in a fuzz, the GPS-gap chord fixes taken after an alarm
/// (phase before the Step ALARMING or SNOOZED, from `GapProbe.phase`), the Overshoot events that follow one in the same trip
/// (with / without an Alarm(OVERSHOOT) in the same Step) and the wrong ones: Overshoot with a chord taken after the alarm
/// (`alarmedChordD != nil`, T10.7 round 2) while the truth has not passed the destination yet (truth distance > 0, the U116 b
/// definition). Trips are told apart by their tag (fed in order).
final class AlarmedChordCounter {
    var chordFixes = 0
    var overshootWithAlarm = 0
    var overshootNoAlarm = 0
    /// Overshoot events above whose Step state has `alarmedChordD != nil` (T10.7 round 2: nearD may come from the chord).
    var overshootFromChord = 0
    var wrong: [String] = []
    private var trip: String? = nil
    private var armed = false

    /// One Step on `input`; `truthD` = signed true distance to the destination at the Step (nil = unknown). Returns the
    /// wrong-wording line when this Step is one (also added to `wrong`).
    @discardableResult
    func onFix(_ tripTag: String, _ s0: EngineState, _ input: LocationFix, _ step: Step, _ truthD: Double?) -> String? {
        if tripTag != trip {
            trip = tripTag
            armed = false
        }
        if let g = GapProbe.of(s0, input, step), g.dChord != nil, g.phase == .alarming || g.phase == .snoozed {
            chordFixes += 1
            armed = true
        }
        let hasOvershoot = step.events.contains { if case .overshoot = $0 { return true } else { return false } }
        if !armed || !hasOvershoot { return nil }
        if step.events.alarms.contains(where: { $0.reason == .overshoot }) { overshootWithAlarm += 1 } else { overshootNoAlarm += 1 }
        if step.state.alarmedChordD != nil { overshootFromChord += 1 }
        if step.state.alarmedChordD != nil, let truthD, truthD > 0.0 {
            let minD = step.state.minD.map { String(KW.ki($0)) } ?? "null"
            let ac = step.state.alarmedChordD.map { String(KW.ki($0)) } ?? "null"
            let line = "\(tripTag) at \(step.state.nowMs - step.state.startedAtMs) ms truthD=\(KW.ki(truthD)) minD=\(minD) alarmedChordD=\(ac)"
            wrong.append(line)
            return line
        }
        return nil
    }

    func line(_ name: String) -> String {
        "\(name): alarmedChordFixes=\(chordFixes) overshootAfter(withAlarm=\(overshootWithAlarm), noAlarm=\(overshootNoAlarm), "
            + "withAlarmedChordD=\(overshootFromChord)) wrongWording=\(wrong.count)" + wrong.prefix(10).map { "\n  \($0)" }.joined()
    }

    /// Writes `unit/t107-alarmed-chord.txt` with every counter reported so far (any test order; Kotlin `t107-alarmed-chord.txt`).
    static func report(_ name: String, _ c: AlarmedChordCounter) { ChordLog.shared.add(name, c.line(name)) }
}

/// `t107-alarmed-chord.txt` lines by counter name (parallel tests; written sorted, under the lock, so the file is deterministic).
final class ChordLog: @unchecked Sendable {
    static let shared = ChordLog()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func add(_ name: String, _ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines[name] = line
        Report.shared.write("unit/t107-alarmed-chord.txt", lines.keys.sorted().map { lines[$0]! }.joined(separator: "\n") + "\n")
    }
}
