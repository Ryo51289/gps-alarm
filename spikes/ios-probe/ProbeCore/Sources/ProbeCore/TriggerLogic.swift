import Foundation

public enum Phase: String, Sendable {
    case sparse
    case dense
}

/// When to fire and when to re-arm the fallback alarm (S3 §6.7, §6.8). Pure functions; the clock is a parameter.
public enum TriggerLogic {
    /// PREARM_DELAY_S: the fallback alarm is set at deadline + this.
    public static let prearmDelayS: TimeInterval = 60
    /// PREARM_RESCHEDULE_S: re-arm the fallback alarm from the background at most this often.
    public static let prearmRescheduleS: TimeInterval = 300
    /// AK_LEAD_S: the AlarmKit alarm set on trigger is `.fixed(now + this)`.
    public static let akLeadS: TimeInterval = 5
    /// TS_REPEAT / TS_REPEAT_INTERVAL_S: notifications posted on trigger.
    public static let tsRepeat = 3
    public static let tsRepeatIntervalS: TimeInterval = 30
    /// The run ends by itself this long after the deadline.
    public static let runTimeoutAfterDeadlineS: TimeInterval = 600
    public static let selfExitDelayS: TimeInterval = 30
    public static let toneSeconds = 29
    public static let walkRadiusM: Double = 200

    public static func shouldFire(now: Date, deadline: Date, alreadyFired: Bool) -> Bool {
        !alreadyFired && now >= deadline
    }

    public static func prearmDate(deadline: Date) -> Date {
        deadline.addingTimeInterval(prearmDelayS)
    }

    public static func isRescheduleDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= prearmRescheduleS
    }

    /// No fallback re-arm starts this close to (or after) the deadline, so a re-arm can never run concurrently with
    /// the trigger's fireNow (review S3 #2).
    public static let rescheduleQuietBeforeDeadlineS: TimeInterval = 30

    /// Re-arm the fallback alarm now? Not fired, due, and strictly before deadline − rescheduleQuietBeforeDeadlineS.
    public static func shouldReschedule(last: Date?, now: Date, deadline: Date, fired: Bool) -> Bool {
        !fired && now < deadline.addingTimeInterval(-rescheduleQuietBeforeDeadlineS) && isRescheduleDue(last: last, now: now)
    }

    /// Dense when now >= runStart + max(0, durationS - densePhaseS).
    public static func phase(now: Date, runStart: Date, durationS: TimeInterval, densePhaseS: TimeInterval) -> Phase {
        now >= denseStart(runStart: runStart, durationS: durationS, densePhaseS: densePhaseS) ? .dense : .sparse
    }

    public static func denseStart(runStart: Date, durationS: TimeInterval, densePhaseS: TimeInterval) -> Date {
        runStart.addingTimeInterval(max(0, durationS - densePhaseS))
    }

    /// The run is over by timeout (S3 §6.5: 10 minutes after the deadline).
    public static func isTimedOut(now: Date, deadline: Date) -> Bool {
        now >= deadline.addingTimeInterval(runTimeoutAfterDeadlineS)
    }
}
