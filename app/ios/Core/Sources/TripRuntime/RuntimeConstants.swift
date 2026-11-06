// Platform-layer constants (docs/specs/T17.md §6, T17.2 §6). Native, not Remote Config (D17).

public struct RuntimeConstants: Sendable, Equatable {
    public var akNowLeadMs: Int64 = 5_000
    public var nowAlertGraceMs: Int64 = 20_000
    public var nowObserveHoldMs: Int64 = 15_000
    public var preRingPersistBudgetMs: Int64 = 300
    public var startPersistBudgetMs: Int64 = 1_000
    public var snapshotMinIntervalMs: Int64 = 60_000
    public var snapshotRetryMs: Int64 = 5_000
    public var awakeTickMaxMs: Int64 = 60_000
    public var fixThrottleSlackMs: Int64 = 500
    public var stopIntentGraceMs: Int64 = 3_000
    public var restoreSettleMs: Int64 = 2_000
    public var ringRetryMs: Int64 = 30_000
    public var clockDriftMaxMs: Int64 = 300_000
    public var endedTripIdsMax: Int = 8
    public var ringEventsMax: Int = 16
    public var journalMaxBytes: Int = 5_242_880
    /// T17.2 D3: "Báo lại" on the AlarmKit alert (Q3 = A). false = C (no snooze button; the app has one).
    public var snoozeButtonEnabled = true
    /// T17.2 D8 (T27 D5): a launch action older than this is dropped.
    public var launchActionTtlMs: Int64 = 600_000
    /// T17.2 D8: how long `consumeLaunchAction` waits for a route-back intent in flight.
    public var launchActionWaitMs: Int64 = 1_500
    /// T17.2 D11 (T16 AE11): "Nghe thử" stops after this.
    public var previewMaxMs: Int64 = 10_000
    /// T17.2 §5.3 item 3 (T17.2.2, RK-T17-12): D of AM05, how long AlarmKit lets an unanswered alarm ring before it stops
    /// it by itself. Set → an overshoot while the first ring is live schedules a trailing alarm (guard slot, OVERSHOOT
    /// title, route back) at ring start + D + AK_NOW_LEAD_MS, for when the app is dead when that ring stops. nil = AlarmKit
    /// rings until answered (AM05 branch 1): no trailing alarm. nil until AM05 is measured on a device: with a guessed D
    /// and an alarm that never stops, the trailing alarm would ring next to the first one.
    public var akSelfStopMs: Int64?
    /// T17.2.2 (tester finding #1): `list()` read period while a ring is swallowed (`ring_live`), until the live ring is gone.
    public var swallowPollMs: Int64 = 10_000
    /// T18.1 §7: reading + parsing a bundled trace at start (T18 §10).
    public var simTraceLoadBudgetMs: Int64 = 3_000
    /// T18.1 §5: virtual events handled by one timer command; the rest goes to a next command.
    public var simCatchUpMaxEvents: Int = 2_000
    /// T17.2.1 §4: the rescue alarm of a snooze intent is taken as the engine's snooze slot only when its time is within
    /// this of the slot target (wall); otherwise the runtime schedules a new slot first, then cancels the rescue.
    public var rescueMatchMs: Int64 = 2_000
    /// T17.2.1 §4: how long `NapStopSnoozeIntent` waits for the runtime before deciding whether to stop the ring.
    public var snoozeHandoverBudgetMs: Int64 = 3_000
    /// T17.3 D7: pending notification requests the notification channel allows itself (system limit 64 per app [UN-64]).
    public var notifPendingBudget: Int = 20

    /// T17.2.1 §4: system generation of a rescue alarm (runtime slots start at 1).
    public static let rescueGeneration: Int64 = 0

    public init() {}
    public static let `default` = RuntimeConstants()
}
