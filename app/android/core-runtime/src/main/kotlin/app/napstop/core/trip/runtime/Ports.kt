package app.napstop.core.trip.runtime

import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserActionKind

// Ports of the runtime to the platform (spec T15 §4.1). :app binds them to Android services; JVM tests use fakes.

/** Trip clock (T10 §2.6): monotonic, ≈ wall clock. All engine times use it. */
interface TimeSource {
    /** System.currentTimeMillis() */
    fun wallMs(): Long

    /** SystemClock.elapsedRealtime() */
    fun elapsedMs(): Long

    /** SystemClock.elapsedRealtimeNanos() */
    fun elapsedNanos(): Long

    /** Settings.Global.BOOT_COUNT, null if unreadable. */
    fun bootCount(): Int?
}

/** One raw fix as the platform gives it; no Android types. toString() redacts lat/lng. */
data class RawFix(
    val lat: Double,
    val lng: Double,
    /** null = !hasAccuracy() */
    val accuracyM: Float?,
    /** null = !hasSpeed() */
    val speedMps: Float?,
    /** Location.getElapsedRealtimeNanos() */
    val elapsedRealtimeNanos: Long,
) {
    override fun toString(): String =
        "RawFix(accuracyM=$accuracyM, speedMps=$speedMps, elapsedRealtimeNanos=$elapsedRealtimeNanos, position=<redacted>)"
}

enum class FlpPriority { HIGH_ACCURACY, BALANCED_POWER_ACCURACY }

data class FlpRequestSpec(
    val priority: FlpPriority,
    val intervalMs: Long,
    val minUpdateIntervalMs: Long,
    val maxUpdateDelayMs: Long,
    val maxUpdateAgeMs: Long,
)

/**
 * Receives platform fixes. [processed] must be called once the runtime is done with the fix (the source holds a wake
 * lock until then, capped at STEP_WAKELOCK_MS; review T15 #4). Idempotent.
 */
fun interface FixSink {
    fun onFix(raw: RawFix, processed: () -> Unit)
}

interface LocationSource {
    /** Starts or replaces the request. Fixes go to [sink] on any thread. Throws SecurityException if no permission. */
    fun request(spec: FlpRequestSpec, sink: FixSink)

    fun stop()

    /** FusedLocationProviderClient.getLastLocation(); null if none or error. */
    suspend fun lastKnown(): RawFix?
}

enum class StartReason { USER_START, APP_VISIBLE, NOTIFICATION_TAP }

sealed interface ForegroundResult {
    data object Started : ForegroundResult

    data class Failed(val errorClass: String) : ForegroundResult
}

/**
 * The foreground service shell (spec T15 D2). The runtime requests location itself through [LocationSource], and only
 * while the service is in the foreground (mode TRACKING_FGS), so this port has no `applySampling` (implementation notes).
 */
interface TrackingController {
    /** startForegroundService(LocationService). Throws (class name is reported) if the system refuses. */
    fun start(tripId: String, reason: StartReason)

    fun updateTrackingNotification(content: TrackingNotice)

    /** stopForeground(REMOVE), stopSelf. */
    fun stop()

    val isForeground: Boolean
}

enum class WakeMechanism { EXACT_IDLE, ALARM_CLOCK, INEXACT_IDLE }

interface OsAlarmScheduler {
    /** API < 31: true. */
    fun canScheduleExact(): Boolean

    /** Extras wakeAtMs (trip clock) and wakeAtWallMs = [triggerWallMs], so the receiver can log what it was set for (F5). */
    fun setWake(triggerElapsedMs: Long, mechanism: WakeMechanism, triggerWallMs: Long, wakeAtMs: Long = -1L)

    fun cancelWake()

    /**
     * setAlarmClock at [triggerWallMs] in slot [slot] (setAndAllowWhileIdle when ![exact]); extras: tripId, slot,
     * generation, targetAtMs (trip clock), kind. Throws on failure.
     */
    fun setFallback(slot: Int, tripId: String, generation: Long, targetAtMs: Long, triggerWallMs: Long, exact: Boolean, kind: SlotKind = SlotKind.ENGINE)

    fun cancelFallback(slot: Int)

    /**
     * Restore retry after a receiver ran out of budget with the disk too slow (designer "sau test" B3): its own
     * PendingIntent to WakeAlarmReceiver (setExactAndAllowWhileIdle, ELAPSED_REALTIME_WAKEUP; inexact without the exact
     * permission), extras attempt, cause, sinceWallMs. Replaces the previous one.
     */
    fun setRestoreRetry(triggerElapsedMs: Long, attempt: Int, cause: RestoreCause, sinceWallMs: Long, exact: Boolean)

    fun cancelRestoreRetry()
}

fun interface AppVisibility {
    fun isVisible(): Boolean
}

data class LocationAccess(
    val fineGranted: Boolean,
    val coarseGranted: Boolean,
    val servicesEnabled: Boolean,
    val playServicesAvailable: Boolean,
)

data class BatteryReading(val levelPct: Int, val charging: Boolean)

interface DeviceEnv {
    fun locationAccess(): LocationAccess

    /** Sticky ACTION_BATTERY_CHANGED [A-BAT]; null if unreadable. */
    fun battery(): BatteryReading?
}

/** Durable storage under noBackupFilesDir/napstop_trip (§5.7). Blocking; called on IO. */
interface RuntimeStore {
    /** null = none; corrupt file → deleted, warn, null. */
    fun readActive(): StoredTrip?

    /** tmp + fsync + rename; throws IOException. */
    fun writeActive(t: StoredTrip)

    fun deleteActive()

    fun readLedger(): FallbackLedger

    /** Commit synchronously. */
    fun writeLedger(l: FallbackLedger)

    fun writeRingConfig(c: RingConfig)

    fun readRingConfig(): RingConfig?

    fun deleteRingConfig()

    fun writeFinished(r: FinishedRecord)

    fun readFinished(): List<FinishedRecord>

    fun deleteFinished(ids: List<String>)
}

/** View + engine events, for the bridge adapter (maps to Pigeon on Main). */
fun interface RuntimeListener {
    fun onStep(tripId: String, view: TripView, batteryChoice: UserActionKind?, events: List<TripEvent>)
}

/** High-priority alerts (channel napstop_trip_alerts). */
sealed interface TripNotice {
    data object NoGpsYet : TripNotice

    data object PermissionRevoked : TripNotice

    data object ServicesOff : TripNotice

    data object FallbackFailed : TripNotice

    data object Interrupted : TripNotice
}

interface TripNotifier {
    /** [alert] false: post silently (no sound, no heads-up), e.g. "Interrupted" again in a later process. */
    fun show(tripId: String, notice: TripNotice, destinationName: String?, alert: Boolean = true)

    fun clear(tripId: String, notice: TripNotice)

    fun clearAll(tripId: String)
}

/**
 * Content of the ongoing notification. [distanceM] is already rounded to what is shown (10 m below 1 km, 100 m above)
 * and [etaS] to whole minutes, so two notices are equal exactly when the formatted text is (§5.2 `Tracking`).
 */
data class TrackingNotice(
    val tripId: String,
    val destinationName: String,
    val phase: TripPhase,
    val distanceM: Int?,
    val etaS: Int?,
    val isEstimated: Boolean,
    val snoozeUntilMs: Long?,
) {
    override fun toString(): String =
        "TrackingNotice(tripId=$tripId, phase=$phase, etaS=$etaS, isEstimated=$isEstimated, snoozeUntilMs=$snoozeUntilMs, " +
            "distance=<redacted>, destination=<redacted>)"
}

enum class RingEventKind { DISMISSED, SNOOZED, SILENCED, FALLBACK_RINGING }

/** T16 → T15 (broadcast `app.napstop.action.RING_EVENT`, §4.4). */
data class RingEvent(val tripId: String, val kind: RingEventKind, val atWallMs: Long)
