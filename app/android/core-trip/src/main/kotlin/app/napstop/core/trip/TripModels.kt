package app.napstop.core.trip

// Contract types of T10 §2 (field names and order are shared with Swift T13 and Pigeon T14).
// Types holding coordinates override toString() so lat/lng are never printed (T10 §10, U80).

enum class AlarmMode { DISTANCE, TIME, SMART }

enum class VehicleKind { TRAIN, COACH, BUS, UNKNOWN }

data class TripConfig(
    val tripId: String,
    val destLat: Double,
    val destLng: Double,
    val mode: AlarmMode,
    val distanceThresholdM: Int?,
    val timeThresholdMin: Int?,
    val preAlertEnabled: Boolean,
    val vehicleHint: VehicleKind,
) {
    override fun toString(): String =
        "TripConfig(tripId=$tripId, mode=$mode, distanceThresholdM=$distanceThresholdM, " +
            "timeThresholdMin=$timeThresholdMin, preAlertEnabled=$preAlertEnabled, vehicleHint=$vehicleHint, dest=<redacted>)"
}

// ---- Inputs (§2.2) ----

sealed interface EngineInput {
    val atMs: Long
}

data class LocationFix(
    override val atMs: Long,
    val fixAtMs: Long,
    val lat: Double,
    val lng: Double,
    val accuracyM: Double,
    val speedMps: Double?,
) : EngineInput {
    override fun toString(): String =
        "LocationFix(atMs=$atMs, fixAtMs=$fixAtMs, accuracyM=$accuracyM, speedMps=$speedMps, position=<redacted>)"
}

data class Tick(override val atMs: Long) : EngineInput

data class BatterySample(override val atMs: Long, val levelPct: Int, val charging: Boolean) : EngineInput

enum class AvailabilityCause { AVAILABLE, PERMISSION_REVOKED, SERVICES_OFF }

data class LocationAvailability(override val atMs: Long, val cause: AvailabilityCause) : EngineInput

data class FallbackScheduled(override val atMs: Long, val fallbackAtMs: Long, val ok: Boolean) : EngineInput

data class FallbackFired(override val atMs: Long, val firedAtMs: Long) : EngineInput

data class AlarmSilenced(override val atMs: Long, val silencedAtMs: Long) : EngineInput

enum class UserActionKind { DISMISS, SNOOZE, STOP_TRIP, BATTERY_MAX_SAVING, BATTERY_ALARM_AT_5, BATTERY_ALARM_EARLIER }

data class UserAction(override val atMs: Long, val action: UserActionKind) : EngineInput

// ---- Events (§2.3) ----

sealed interface TripEvent {
    val atMs: Long
}

data class PreAlert(override val atMs: Long, val distanceM: Int, val etaS: Int?) : TripEvent

enum class AlarmReason {
    DISTANCE, TIME, SMART_TIME, SMART_DISTANCE, SMART_SLOW_DISTANCE, GPS_LOST, LOW_BATTERY,
    PASSED_CLOSEST, OVERSHOOT, SNOOZE_END, TIMEOUT, FALLBACK, FALLBACK_MISSED,
}

data class Alarm(
    override val atMs: Long,
    val reason: AlarmReason,
    val ringNow: Boolean,
    val snoozeAllowed: Boolean,
    val distanceM: Int?,
    val etaS: Int?,
    val batteryPct: Int?,
) : TripEvent

data class Snoozed(override val atMs: Long, val untilMs: Long) : TripEvent

enum class GpsLostCause { NO_FIX_TIMEOUT, NEVER_ACQUIRED, PERMISSION_REVOKED, SERVICES_OFF }

data class GpsLost(override val atMs: Long, val cause: GpsLostCause, val lastFixAgeS: Int?) : TripEvent

data class GpsRecovered(override val atMs: Long, val lostForS: Int) : TripEvent

data class LowBatteryRisk(override val atMs: Long, val levelPct: Int, val availableMin: Int, val neededMin: Int) : TripEvent

data class Overshoot(override val atMs: Long, val pastM: Int) : TripEvent

data class Arrived(override val atMs: Long, val distanceM: Int) : TripEvent

enum class FallbackCause { ETA, SNOOZE, SUPERSEDED, TRIP_ENDED, RESYNC }

data class FallbackAlarmChanged(override val atMs: Long, val fallbackAtMs: Long?, val cause: FallbackCause) : TripEvent

data class SamplingPolicyChanged(override val atMs: Long, val policy: SamplingPolicy) : TripEvent

enum class TripOutcome { ON_TIME, SNOOZED, MISSED, CANCELLED }

enum class EndReason { DISMISSED, USER_STOP, ALARM_UNANSWERED }

data class TripEnded(override val atMs: Long, val outcome: TripOutcome, val endReason: EndReason, val summary: TripSummary) :
    TripEvent

data class TripSummary(
    val startedAtMs: Long,
    val alarmAtMs: Long?,
    val alarmReason: AlarmReason?,
    val dismissedAtMs: Long?,
    val snoozeCount: Int,
    val travelledM: Int,
    val vehicleGuess: VehicleKind,
)

// ---- Sampling policy, view (§2.4) ----

/** Ordinal order is the comparison order SPARSE < MEDIUM < DENSE. */
enum class SamplingTier { SPARSE, MEDIUM, DENSE }

enum class AccuracyLevel { BALANCED, HIGH }

data class SamplingPolicy(val tier: SamplingTier, val intervalS: Int, val minIntervalS: Int, val accuracy: AccuracyLevel)

enum class TripPhase { ACQUIRING, TRACKING, ALARMING, SNOOZED, OVERSHOT, ENDED }

enum class GpsStatus { NO_FIX_YET, OK, LOST }

enum class FallbackStatus { NONE, REQUESTED, CONFIRMED, FAILED }

data class TripView(
    val tripId: String,
    val atMs: Long,
    val phase: TripPhase,
    val gps: GpsStatus,
    val locationCause: AvailabilityCause,
    val distanceM: Int?,
    val routeDistanceEstM: Int?,
    val distanceErrorM: Int?,
    val isEstimated: Boolean,
    val etaS: Int?,
    val etaMinS: Int?,
    val etaMaxS: Int?,
    val speedKmh: Double?,
    val progress: Double?,
    val alarmMarkerProgress: Double?,
    val predictedAlarmAtMs: Long?,
    val samplingPolicy: SamplingPolicy?,
    val fallbackAtMs: Long?,
    val fallbackStatus: FallbackStatus,
    val batteryPct: Int?,
    val batteryRisk: Boolean,
    val preAlertFired: Boolean,
    val alarmAtMs: Long?,
    val alarmReason: AlarmReason?,
    val alarmRinging: Boolean,
    val snoozeCount: Int,
    val snoozeUntilMs: Long?,
    val overshootPastM: Int?,
    val outcome: TripOutcome?,
    val vehicleGuess: VehicleKind,
    val travelledM: Int,
    val droppedFixes: Int,
    val wakeAtMs: Long?,
)

data class Step(val state: EngineState, val events: List<TripEvent>, val view: TripView) {
    override fun toString(): String = "Step(state=<redacted>, events=$events, view=$view)"
}

// ---- Restore (§2.5, §7.2) ----

enum class FallbackRestoreStatus { RANG, DISMISSED, PENDING, MISSING, UNKNOWN }

data class RestoreInfo(val status: FallbackRestoreStatus, val firedAtMs: Long? = null, val dismissedAtMs: Long? = null)

/** Thrown by [TripEngine.decodeSnapshot]; message is "snapshot: <rule>" and never contains snapshot content. */
class SnapshotFormatException(message: String) : RuntimeException(message)
