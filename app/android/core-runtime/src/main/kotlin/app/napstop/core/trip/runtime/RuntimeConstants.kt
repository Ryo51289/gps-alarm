package app.napstop.core.trip.runtime

/**
 * Platform constants of spec T15 §6 (native, not Remote Config: D16). One instance per runtime so JVM tests can switch
 * single behaviours (for example [awakeTickMaxMs] = null in the Doze model, where the CPU sleeps between alarms).
 */
data class RuntimeConstants(
    /** Wait for LocationService.startForeground; well inside the 15 s of T25. */
    val fgsStartTimeoutMs: Long = 5_000,
    /** First snapshot of a trip; a failure still starts the trip (it lives in memory). */
    val startPersistBudgetMs: Long = 1_000,
    /** D4: write before ringing, but never make the user wait. */
    val preRingPersistBudgetMs: Long = 300,
    /** T10 §7.1 (c). */
    val snapshotMinIntervalMs: Long = 60_000,
    /** Retry after a failed write. */
    val snapshotRetryMs: Long = 5_000,
    /** T10 §2.6: never sparser than 60 s while the CPU is awake and the FGS runs. null = off. */
    val awakeTickMaxMs: Long? = 60_000,
    /** Battery: content changes every 5 s in the dense tier. */
    val notifMinIntervalMs: Long = 15_000,
    /** goAsync must finish within ~10 s [S2 A14]. */
    val receiverBudgetMs: Long = 8_000,
    /**
     * Longest the actor waits for one disk call (review T15 #5): a hung disk never delays a queued fallback ring by
     * more than this. The call goes on in the background.
     */
    val ioBudgetMs: Long = 1_000,
    /** CPU held for one Step after a fix (cap; released as soon as the Step is done). */
    val stepWakelockMs: Long = 5_000,
    /** D6; switch on if protocol M3 fails. */
    val nearWakeUsesAlarmClock: Boolean = NEAR_WAKE_USES_ALARM_CLOCK,
    /** B2: safety slot after a reboot while only the ledger is readable: max(old fallback, now + this). */
    val safetyLagMs: Long = 30_000,
    /** B3: restore retries after the receiver budget: 30 s, 60 s, 120 s, 240 s, then 300 s each. */
    val restoreRetryDelaysMs: List<Long> = listOf(30_000, 60_000, 120_000, 240_000),
    val restoreRetryEveryMs: Long = 300_000,
    /** B3: give up after this long (then "Interrupted" once if the ledger names a trip). */
    val restoreRetryMaxMs: Long = 86_400_000,
    /** T18 §10: read + parse the largest bundled GPX on a slow phone; inside the 15 s of T25 with the FGS wait. */
    val simTraceLoadBudgetMs: Long = 3_000,
    /** T18 §10: a simulation timer re-reads the trip clock at least this often (a rebase takes effect soon). */
    val simPollMaxMs: Long = 250,
    /** T18 D8: wake lock cap of a simulated trip, under the 2 h / 24 h of Android vitals [A-VIT]. */
    val simWakelockCapMs: Long = 6_600_000,
    /** T18 §3: ongoing notification of a simulated trip at most once per second. */
    val simNotifMinIntervalFloorMs: Long = 1_000,
) {
    companion object {
        /** D6 (PO 03/11/2026): RK17 accepts the fallback alarm; the setAlarmClock branch for c3 stays behind this flag. */
        const val NEAR_WAKE_USES_ALARM_CLOCK = false

        /** B1: back-off between load attempts inside a receiver: 250 ms doubling, at most 1 s. */
        const val RESTORE_BACKOFF_MS = 250L
        const val RESTORE_BACKOFF_MAX_MS = 1_000L

        /** B1: the receiver loop stops this long before RECEIVER_BUDGET_MS. */
        const val RESTORE_DEADLINE_MARGIN_MS = 500L

        /** Same value as the engine's internal `WAKE_GUARD_MS` (core-trip WakePlanner.kt, T10.4). Keep in sync. */
        const val WAKE_GUARD_MS = 1_000L

        /** T18 D3: speed of a simulated trip once the engine left ACQUIRING / TRACKING (PRD §4 user-perceived times). */
        const val SIM_SPEED_AFTER_ALARM = 1.0
    }
}
