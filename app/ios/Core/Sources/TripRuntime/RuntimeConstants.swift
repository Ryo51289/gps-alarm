// Platform-layer constants (docs/specs/T17.md §6, T17.2 §6). Native, not Remote Config (D17).

/// T17.2 §5 (T16.2, waiting for the PO): what iOS does when the trip overshoots while the first ring is still live.
/// `.none` = P0 (engine T10 #18 unchanged). P1 needs no iOS code (the engine would emit `Alarm(OVERSHOOT)`, which goes the
/// normal `ring` path with the route-back button); P2 would be a separate task.
public enum OvershootWhileRingingPolicy: String, Sendable, Equatable { case none, ringAgainOnSilence }

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
    /// T17.2 §5: P0 until the PO decides T16.2.
    public var overshootWhileRingingPolicy: OvershootWhileRingingPolicy = .none
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
