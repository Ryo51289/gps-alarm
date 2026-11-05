// Platform-layer constants (docs/specs/T17.md §6). Native, not Remote Config (D17).

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

    public init() {}
    public static let `default` = RuntimeConstants()
}
