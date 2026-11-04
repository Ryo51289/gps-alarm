package app.napstop.core.trip.runtime

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.VehicleKind
import kotlin.math.floor

/** Fields of FinishedTripMsg (T14 §3.1) in plain Kotlin; :app maps it to the Pigeon class. */
data class FinishedRecord(
    val tripId: String,
    val outcome: TripOutcome,
    val endReason: EndReason,
    val endedAtMs: Long,
    val startedAtMs: Long,
    val alarmAtMs: Long?,
    val alarmReason: AlarmReason?,
    val dismissedAtMs: Long?,
    val snoozeCount: Int,
    val travelledM: Int,
    val vehicleGuess: VehicleKind,
)

/** FinishedRecord from the TripEnded event, or from an ENDED snapshot when the record could not be written (§5.7). */
object FinishedRecordBuilder {
    fun fromEvent(tripId: String, e: TripEnded): FinishedRecord =
        FinishedRecord(
            tripId = tripId,
            outcome = e.outcome,
            endReason = e.endReason,
            endedAtMs = e.atMs,
            startedAtMs = e.summary.startedAtMs,
            alarmAtMs = e.summary.alarmAtMs,
            alarmReason = e.summary.alarmReason,
            dismissedAtMs = e.summary.dismissedAtMs,
            snoozeCount = e.summary.snoozeCount,
            travelledM = e.summary.travelledM,
            vehicleGuess = e.summary.vehicleGuess,
        )

    /** Same values as the engine's TripEnded.summary (T10 §4.14); null unless [s] is ENDED. */
    fun fromEnded(s: EngineState): FinishedRecord? {
        val ended = s.ended ?: return null
        if (s.phase != TripPhase.ENDED) return null
        return FinishedRecord(
            tripId = s.config.tripId,
            outcome = ended.outcome,
            endReason = ended.endReason,
            endedAtMs = ended.atMs,
            startedAtMs = s.startedAtMs,
            alarmAtMs = s.alarm.atMs,
            alarmReason = s.alarm.reason,
            dismissedAtMs = if (ended.endReason == EndReason.DISMISSED) s.alarm.dismissedAtMs else null,
            snoozeCount = s.alarm.snoozeCount,
            travelledM = roundHalfUp(s.movingDistM),
            vehicleGuess = vehicleGuess(s.movingTimeS, s.movingDistM, s.config.vehicleHint, s.params),
        )
    }

    /** Copy of the engine's internal TMath.roundHalfUp (core-trip TMath.kt). */
    private fun roundHalfUp(x: Double): Int = floor(x + 0.5).toInt()

    /** Copy of the engine's internal vehicleGuess (core-trip ViewBuilder.kt, T10 §4.14); test L19 compares both. */
    private fun vehicleGuess(movingTimeS: Double, movingDistM: Double, hint: VehicleKind, p: EngineParams): VehicleKind =
        if (movingTimeS > 0.0 && movingDistM / movingTimeS * 3.6 < p.vehicleBusMaxAvgKmh.toDouble()) {
            VehicleKind.BUS
        } else if (hint == VehicleKind.TRAIN || hint == VehicleKind.COACH) {
            hint
        } else {
            VehicleKind.UNKNOWN
        }
}
