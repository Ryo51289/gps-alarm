package app.napstop.core.trip.runtime

import app.napstop.core.alarm.PreAlertRequest
import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripView

/** What the runtime does after a Step (spec T15 §4.5). Executed in list order, each in its own try/catch. */
sealed interface Effect {
    /** Bounded pre-ring write (D4). */
    data class PersistNow(val budgetMs: Long) : Effect

    /** AlarmPort.ringNow. */
    data class Ring(val request: RingRequest) : Effect

    /** Re-enters the engine right after this Step, before any outside command. */
    data class Feed(val input: EngineInput) : Effect

    data class StopRinging(val cause: StopCause) : Effect

    data class PreAlertFx(val request: PreAlertRequest) : Effect

    data class OvershootFx(val pastM: Int) : Effect

    data class ApplySampling(val spec: FlpRequestSpec) : Effect

    /** §5.6; the result comes back as Feed(FallbackScheduled). */
    data class ScheduleFallback(val targetAtMs: Long) : Effect

    /** TRIP_ENDED: every slot of the trip. SUPERSEDED no longer cancels (the slot left is the ring guard, G1). */
    data object CancelFallback : Effect

    /**
     * G1 (designer "sau test"): before every Alarm(ringNow=true), make sure a fallback slot rings no later than
     * [guardAtWallMs] (= now + fallbackLagS): keep the current slot if it is that close, else set a GUARD slot (A/B).
     */
    data class ArmRingGuard(val guardAtWallMs: Long) : Effect

    data class ScheduleWake(val wakeAtMs: Long, val mechanism: WakeMechanism) : Effect

    data object CancelWake : Effect

    data class Notice(val show: TripNotice?, val clear: TripNotice?) : Effect

    /** Every high-priority notice of the trip (TripEnded). */
    data object ClearNotices : Effect

    /** Throttled by the executor (§5.2). */
    data class Tracking(val content: TrackingNotice) : Effect

    /** ring_config.properties follows snoozeCount (§5.6: snoozeAllowed of an OS fallback ring). */
    data class UpdateRingConfig(val snoozeCount: Int) : Effect

    /** Enqueue to the writer when the Step has events or the last write is ≥ SNAPSHOT_MIN_INTERVAL_MS old. */
    data object Persist : Effect

    data object Publish : Effect

    /** Finished record first, then delete the snapshot (§5.7). */
    data class Finish(val record: FinishedRecord) : Effect
}

data class PlanInput(
    val prevView: TripView?,
    val step: Step,
    val meta: TripMeta,
    val mode: TrackingMode,
    val facts: RingFacts,
    val scheduledWakeAtMs: Long?,
    val params: EngineParams,
    val nowWallMs: Long,
    val nowTripMs: Long,
    val canScheduleExact: Boolean,
    val nearWakeUsesAlarmClock: Boolean = RuntimeConstants.NEAR_WAKE_USES_ALARM_CLOCK,
    val preRingPersistBudgetMs: Long = 300,
    /** Trip clock speed at this Step (T18 §3); 1.0 for a real trip. */
    val speed: Double = 1.0,
)
