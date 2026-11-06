// The order of the StopIntent (docs/specs/T17.md D12, §5.6.5; T10 §7.2) and of the snooze intent (T17.2.1 §2), testable on
// Linux. The App Intents in the Runner (`NapStopStopIntent.perform`, `NapStopSnoozeIntent.perform`) only supply the closures.
import Foundation
import Trip

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

// MARK: - Snooze intent (docs/specs/T17.2.1.md §2)

/// What the runtime did with a snooze ring event (T17.2.1 §2 step 3).
public enum SnoozeHandOverOutcome: String, Sendable, Equatable {
    /// The engine snoozed (or the trip already is SNOOZED): a slot for the snooze end exists.
    case snoozed
    /// The engine refused the snooze (no snooze left, T17.2 D6): the alarm keeps ringing.
    case refused
    /// Unknown or ended trip: the runtime cancelled that alarm.
    case unknownTrip
    /// The runtime did not answer within SNOOZE_HANDOVER_BUDGET_MS (set by the flow, never by the runtime).
    case timeout
}

/// Values the intent needs before the runtime is loaded (§2.1): a read-only copy of the running trip, or the defaults.
public struct SnoozeRescueParams: Sendable, Equatable {
    public let snoozeS: Int
    public let fallbackLagS: Int
    /// T17.2 D10 bundle file; nil = system default sound.
    public let soundFile: String?
    /// For the alarm title only (NativeCopy); NEVER log.
    public let destinationName: String?

    public init(snoozeS: Int, fallbackLagS: Int, soundFile: String?, destinationName: String?) {
        self.snoozeS = snoozeS
        self.fallbackLagS = fallbackLagS
        self.soundFile = soundFile
        self.destinationName = destinationName
    }

    /// A process that has not loaded the trip yet: `EngineParams` defaults, default sound, no name.
    public static var defaults: SnoozeRescueParams {
        let p = EngineParams.defaults
        return SnoozeRescueParams(snoozeS: p.snoozeS, fallbackLagS: p.fallbackLagS, soundFile: nil, destinationName: nil)
    }
}

public enum SnoozeIntentFlow {
    public struct Result: Sendable, Equatable {
        /// Step (1) reached the disk.
        public let written: Bool
        /// Step (2): the rescue alarm was scheduled.
        public let rescueScheduled: Bool
        public let outcome: SnoozeHandOverOutcome
        /// Step (4): the ringing alarm was stopped.
        public let stopped: Bool
    }

    /// The ring event and the rescue alarm of one tap (§2). The rescue is a fallback alarm of the trip with
    /// RESCUE_GENERATION, no secondary button, at tap + snoozeS + fallbackLagS.
    public static func prepare(tripId: String, alarmId: String, kind: SystemAlarmKind, tapWallMs: Int64, rescueId: String,
                               params: SnoozeRescueParams, locale: String,
                               channel: AlarmChannelKind = .alarmKit) -> (rec: RingEventRec, rescue: SystemAlarmRequest) {
        let at = tapWallMs + Int64(params.snoozeS) * 1000 + Int64(params.fallbackLagS) * 1000
        let rec = RingEventRec(tripId: tripId, alarmId: alarmId, kind: kind, action: .snooze, atWallMs: tapWallMs,
                               rescueAlarmId: rescueId, rescueAtWallMs: at)
        let title = NativeCopy.alarmTitle(.snoozeEnd, destinationName: params.destinationName, locale: locale)
        let rescue = SystemAlarmRequest(id: rescueId, tripId: tripId, kind: .fallback,
                                        generation: RuntimeConstants.rescueGeneration, fireAtWallMs: at, title: title,
                                        channel: channel, secondary: nil, soundFile: params.soundFile)
        return (rec, rescue)
    }

    /// Step (4) rule: stop the ring only when something is known to ring for this snooze. "Not sure → keep ringing".
    /// A refused snooze never stops it (the alarm rings on, the user taps Stop). On a timeout the rescue alarm must exist
    /// and its ring event must be on disk (otherwise a new process would not know the rescue belongs to this snooze).
    public static func shouldStop(written: Bool, rescueScheduled: Bool, outcome: SnoozeHandOverOutcome) -> Bool {
        switch outcome {
        case .snoozed, .unknownTrip: return true
        case .refused: return false
        case .timeout: return rescueScheduled && written
        }
    }

    /// (1) write `rec` before anything else; (2) schedule the rescue alarm; (3) hand over to the runtime for at most
    /// `budgetMs`; (4) stop the ringing alarm per `shouldStop`. Step (5) of the spec (refused → cancel the rescue) is left to
    /// the runtime, which owns the rescue: it cancels it, or keeps it as the slot when the ring is already gone (review
    /// T17.2.1 #1: a refusal arriving after the budget, when this flow had stopped the ring).
    /// `journal`: ids and flags only (SM01 reads the order of `ak schedule gen 0` and `ak stop`).
    public static func perform(_ rec: RingEventRec, rescue: SystemAlarmRequest, budgetMs: Int64,
                               write: (RingEventRec) throws -> Void,
                               schedule: (SystemAlarmRequest) async throws -> Void,
                               handOver: @escaping @Sendable (RingEventRec) async -> SnoozeHandOverOutcome,
                               stopSystemAlarm: () async -> Void,
                               journal: RuntimeJournal? = nil,
                               sleep: @escaping @Sendable (Int64) async -> Void = SnoozeIntentFlow.taskSleep) async -> Result {
        var written = true
        do { try write(rec) } catch { written = false }
        var scheduled = true
        var err: String?
        do { try await schedule(rescue) } catch {
            scheduled = false
            err = String(describing: type(of: error))
        }
        var fields = ["op": "schedule", "kind": rescue.kind.rawValue, "gen": "\(rescue.generation)",
                      "ok": scheduled ? "true" : "false", "src": "rescue"]
        if let err { fields["err"] = err }
        journal?.record("ak", fields)
        let outcome = await firstOf(budgetMs: budgetMs, { await handOver(rec) }, sleep: sleep)
        let stop = shouldStop(written: written, rescueScheduled: scheduled, outcome: outcome)
        if stop {
            journal?.record("ak", ["op": "stop", "src": "snoozeIntent"])
            await stopSystemAlarm()
        }
        journal?.record("snooze_flow", ["outcome": outcome.rawValue, "stopped": stop ? "true" : "false",
                                        "written": written ? "true" : "false"])
        return Result(written: written, rescueScheduled: scheduled, outcome: outcome, stopped: stop)
    }

    public static let taskSleep: @Sendable (Int64) async -> Void = { ms in
        try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
    }

    /// The hand-over result, or `.timeout` after `budgetMs`. The hand-over keeps running after a timeout (its runtime
    /// command is queued and completes on its own).
    static func firstOf(budgetMs: Int64, _ handOver: @escaping @Sendable () async -> SnoozeHandOverOutcome,
                        sleep: @escaping @Sendable (Int64) async -> Void) async -> SnoozeHandOverOutcome {
        let box = FirstResult()
        let work = Task { box.offer(await handOver()) }
        let timer = Task {
            await sleep(budgetMs)
            box.offer(.timeout)
        }
        let r = await box.wait()
        timer.cancel()
        _ = work
        return r
    }
}

/// First value wins; `wait` returns it.
final class FirstResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SnoozeHandOverOutcome?
    private var waiter: CheckedContinuation<SnoozeHandOverOutcome, Never>?

    func offer(_ v: SnoozeHandOverOutcome) {
        lock.lock()
        if value != nil { lock.unlock(); return }
        value = v
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(returning: v)
    }

    func wait() async -> SnoozeHandOverOutcome {
        await withCheckedContinuation { (c: CheckedContinuation<SnoozeHandOverOutcome, Never>) in
            lock.lock()
            if let v = value { lock.unlock(); c.resume(returning: v); return }
            waiter = c
            lock.unlock()
        }
    }
}
