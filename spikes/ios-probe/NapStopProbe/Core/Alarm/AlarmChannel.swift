import Foundation

/// Outcome of one scheduling call, logged by the caller as prearm_set / prearm_reschedule.
struct ScheduleResult {
    var ok: Bool
    var err: String?
    /// Time spent in the API call(s).
    var ms: Int
}

/// One way of ringing (S3 §6.4). Every API error is caught and returned/logged; it never stops the run (§6.9).
protocol AlarmChannel: AnyObject {
    /// Fallback alarm set when the run starts (deadline + PREARM_DELAY_S).
    @discardableResult
    func prearm(at date: Date, runId: String) async -> ScheduleResult

    /// Replace the fallback alarm (called from the background every PREARM_RESCHEDULE_S).
    @discardableResult
    func reschedulePrearm(at date: Date, runId: String) async -> ScheduleResult

    /// Ring now: drop the fallback alarm and schedule the "now" alarm(s).
    func fireNow(runId: String) async

    /// Remove everything this run scheduled (pending and, where possible, ringing).
    func cancelAll(runId: String) async
}

enum Elapsed {
    static func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
}
