// The order of the StopIntent (docs/specs/T17.md D12, §5.6.5; T10 §7.2), testable on Linux. The App Intent in the Runner
// (`NapStopStopIntent.perform`) only supplies the closures.
import Foundation

public enum StopIntentFlow {
    /// (1) write the ring event to disk before anything else; (2) stop the system alarm where iOS did not (26.0);
    /// (3) hand the record to the runtime, also when (1) failed (the runtime keeps it in memory, tester T17 #2).
    /// Returns whether step (1) succeeded.
    @discardableResult
    public static func perform(_ rec: RingEventRec, write: (RingEventRec) throws -> Void, stopSystemAlarm: () -> Void,
                               handOver: (RingEventRec) async -> Void) async -> Bool {
        var written = true
        do { try write(rec) } catch { written = false }
        stopSystemAlarm()
        await handOver(rec)
        return written
    }
}

extension StopIntentFlow {
    /// Review T17 R4-2: when step (1) failed, the diagnostics journal says so (device runs IM02/IM04). Only the flag:
    /// no ids, no data.
    public static func recordWriteFailure(written: Bool, _ journal: RuntimeJournal) {
        if !written { journal.record("stop_intent", ["written": "false"]) }
    }
}
