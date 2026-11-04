package app.napstop.core.bridge

import app.napstop.core.alarm.RingSettings
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Arrived
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LowBatteryRisk
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.runtime.FinishedRecord
import app.napstop.core.trip.runtime.TripMeta

/** Engine / runtime types ↔ Pigeon messages (T14 §3.3, spec T15 L34). Pure. */
object MsgMapper {
    /** One Step: TripStateUpdateMsg first, then the events in engine order, minus the native-only ones (T14 §2 rule 1). */
    fun updates(tripId: String, view: TripView, choice: UserActionKind?, events: List<TripEvent>): List<TripUpdateMsg> {
        val out = ArrayList<TripUpdateMsg>(events.size + 1)
        out += TripStateUpdateMsg(state(view, choice))
        for (e in events) event(tripId, e)?.let { out += it }
        return out
    }

    fun state(v: TripView, choice: UserActionKind?): TripStateMsg =
        TripStateMsg(
            tripId = v.tripId,
            atMs = v.atMs,
            phase = phase(v.phase),
            gps =
                when (v.gps) {
                    GpsStatus.NO_FIX_YET -> GpsStatusMsg.NO_FIX_YET
                    GpsStatus.OK -> GpsStatusMsg.OK
                    GpsStatus.LOST -> GpsStatusMsg.LOST
                },
            locationCause =
                when (v.locationCause) {
                    AvailabilityCause.AVAILABLE -> AvailabilityCauseMsg.AVAILABLE
                    AvailabilityCause.PERMISSION_REVOKED -> AvailabilityCauseMsg.PERMISSION_REVOKED
                    AvailabilityCause.SERVICES_OFF -> AvailabilityCauseMsg.SERVICES_OFF
                },
            distanceM = v.distanceM?.toLong(),
            routeDistanceEstM = v.routeDistanceEstM?.toLong(),
            distanceErrorM = v.distanceErrorM?.toLong(),
            isEstimated = v.isEstimated,
            etaS = v.etaS?.toLong(),
            etaMinS = v.etaMinS?.toLong(),
            etaMaxS = v.etaMaxS?.toLong(),
            speedKmh = v.speedKmh,
            progress = v.progress,
            alarmMarkerProgress = v.alarmMarkerProgress,
            predictedAlarmAtMs = v.predictedAlarmAtMs,
            samplingTier =
                v.samplingPolicy?.tier?.let {
                    when (it) {
                        SamplingTier.SPARSE -> SamplingTierMsg.SPARSE
                        SamplingTier.MEDIUM -> SamplingTierMsg.MEDIUM
                        SamplingTier.DENSE -> SamplingTierMsg.DENSE
                    }
                },
            fallbackAtMs = v.fallbackAtMs,
            fallbackStatus =
                when (v.fallbackStatus) {
                    FallbackStatus.NONE -> FallbackStatusMsg.NOT_SET
                    FallbackStatus.REQUESTED -> FallbackStatusMsg.REQUESTED
                    FallbackStatus.CONFIRMED -> FallbackStatusMsg.CONFIRMED
                    FallbackStatus.FAILED -> FallbackStatusMsg.FAILED
                },
            batteryPct = v.batteryPct?.toLong(),
            batteryRisk = v.batteryRisk,
            batteryChoice = choice?.let(::batteryChoice),
            preAlertFired = v.preAlertFired,
            alarmAtMs = v.alarmAtMs,
            alarmReason = v.alarmReason?.let(::reason),
            alarmRinging = v.alarmRinging,
            snoozeCount = v.snoozeCount.toLong(),
            snoozeUntilMs = v.snoozeUntilMs,
            overshootPastM = v.overshootPastM?.toLong(),
            outcome = v.outcome?.let(::outcome),
            vehicleGuess = vehicle(v.vehicleGuess),
            travelledM = v.travelledM.toLong(),
        )

    /** null for the native-only events (SamplingPolicyChanged, FallbackAlarmChanged). */
    fun event(tripId: String, e: TripEvent): TripUpdateMsg? =
        when (e) {
            is PreAlert -> PreAlertMsg(tripId, e.atMs, e.distanceM.toLong(), e.etaS?.toLong())
            is Alarm -> AlarmMsg(tripId, e.atMs, reason(e.reason), e.ringNow, e.snoozeAllowed, e.distanceM?.toLong(), e.etaS?.toLong(), e.batteryPct?.toLong())
            is Snoozed -> SnoozedMsg(tripId, e.atMs, e.untilMs)
            is GpsLost ->
                GpsLostMsg(
                    tripId,
                    e.atMs,
                    when (e.cause) {
                        GpsLostCause.NO_FIX_TIMEOUT -> GpsLostCauseMsg.NO_FIX_TIMEOUT
                        GpsLostCause.NEVER_ACQUIRED -> GpsLostCauseMsg.NEVER_ACQUIRED
                        GpsLostCause.PERMISSION_REVOKED -> GpsLostCauseMsg.PERMISSION_REVOKED
                        GpsLostCause.SERVICES_OFF -> GpsLostCauseMsg.SERVICES_OFF
                    },
                    e.lastFixAgeS?.toLong(),
                )
            is GpsRecovered -> GpsRecoveredMsg(tripId, e.atMs, e.lostForS.toLong())
            is LowBatteryRisk -> LowBatteryRiskMsg(tripId, e.atMs, e.levelPct.toLong(), e.availableMin.toLong(), e.neededMin.toLong())
            is Overshoot -> OvershootMsg(tripId, e.atMs, e.pastM.toLong())
            is Arrived -> ArrivedMsg(tripId, e.atMs, e.distanceM.toLong())
            is TripEnded ->
                TripEndedMsg(
                    e.atMs,
                    FinishedTripMsg(
                        tripId = tripId,
                        outcome = outcome(e.outcome),
                        endReason = endReason(e.endReason),
                        endedAtMs = e.atMs,
                        startedAtMs = e.summary.startedAtMs,
                        alarmAtMs = e.summary.alarmAtMs,
                        alarmReason = e.summary.alarmReason?.let(::reason),
                        dismissedAtMs = e.summary.dismissedAtMs,
                        snoozeCount = e.summary.snoozeCount.toLong(),
                        travelledM = e.summary.travelledM.toLong(),
                        vehicleGuess = vehicle(e.summary.vehicleGuess),
                    ),
                )
            is SamplingPolicyChanged, is FallbackAlarmChanged -> null
        }

    fun finished(r: FinishedRecord): FinishedTripMsg =
        FinishedTripMsg(
            tripId = r.tripId,
            outcome = outcome(r.outcome),
            endReason = endReason(r.endReason),
            endedAtMs = r.endedAtMs,
            startedAtMs = r.startedAtMs,
            alarmAtMs = r.alarmAtMs,
            alarmReason = r.alarmReason?.let(::reason),
            dismissedAtMs = r.dismissedAtMs,
            snoozeCount = r.snoozeCount.toLong(),
            travelledM = r.travelledM.toLong(),
            vehicleGuess = vehicle(r.vehicleGuess),
        )

    /** TripConfigMsg → coordinate-free runtime meta (validated by TripConfigValidator before). */
    fun meta(c: TripConfigMsg): TripMeta =
        TripMeta(
            tripId = c.tripId,
            destinationName = c.destinationName,
            mode =
                when (c.mode) {
                    AlarmModeMsg.DISTANCE -> AlarmMode.DISTANCE
                    AlarmModeMsg.TIME -> AlarmMode.TIME
                    AlarmModeMsg.SMART -> AlarmMode.SMART
                },
            distanceThresholdM = c.distanceThresholdM?.toInt(),
            timeThresholdMin = c.timeThresholdMin?.toInt(),
            preAlertEnabled = c.preAlertEnabled,
            vehicleHint =
                when (c.vehicleHint) {
                    VehicleKindMsg.TRAIN -> VehicleKind.TRAIN
                    VehicleKindMsg.COACH -> VehicleKind.COACH
                    VehicleKindMsg.BUS -> VehicleKind.BUS
                    VehicleKindMsg.UNKNOWN -> VehicleKind.UNKNOWN
                },
            alarm =
                RingSettings(
                    soundId = c.alarm.soundId,
                    volume = c.alarm.volume,
                    rampUp = c.alarm.rampUp,
                    vibration = c.alarm.vibration.name.lowercase(),
                    flash = c.alarm.flash,
                    preferHeadphones = c.alarm.preferHeadphones,
                    dismissMethod = c.alarm.dismissMethod.name.lowercase(),
                ),
            engineParamsJson = c.engineParamsJson,
        )

    /** Inverse of [meta]: what currentTrip() echoes (T14 review M4: exactly what startTrip received). */
    fun config(m: TripMeta): TripConfigMsg =
        TripConfigMsg(
            tripId = m.tripId,
            destinationName = m.destinationName,
            mode =
                when (m.mode) {
                    AlarmMode.DISTANCE -> AlarmModeMsg.DISTANCE
                    AlarmMode.TIME -> AlarmModeMsg.TIME
                    AlarmMode.SMART -> AlarmModeMsg.SMART
                },
            distanceThresholdM = m.distanceThresholdM?.toLong(),
            timeThresholdMin = m.timeThresholdMin?.toLong(),
            preAlertEnabled = m.preAlertEnabled,
            vehicleHint = vehicle(m.vehicleHint),
            alarm =
                AlarmSettingsMsg(
                    soundId = m.alarm.soundId,
                    volume = m.alarm.volume,
                    rampUp = m.alarm.rampUp,
                    vibration = VibrationMsg.valueOf(m.alarm.vibration.uppercase()),
                    flash = m.alarm.flash,
                    preferHeadphones = m.alarm.preferHeadphones,
                    dismissMethod = DismissMethodMsg.valueOf(m.alarm.dismissMethod.uppercase()),
                ),
            engineParamsJson = m.engineParamsJson,
        )

    fun batteryChoice(k: UserActionKind): BatteryChoiceMsg? =
        when (k) {
            UserActionKind.BATTERY_MAX_SAVING -> BatteryChoiceMsg.MAX_SAVING
            UserActionKind.BATTERY_ALARM_AT_5 -> BatteryChoiceMsg.ALARM_AT5
            UserActionKind.BATTERY_ALARM_EARLIER -> BatteryChoiceMsg.ALARM_EARLIER
            else -> null
        }

    fun batteryAction(c: BatteryChoiceMsg): UserActionKind =
        when (c) {
            BatteryChoiceMsg.MAX_SAVING -> UserActionKind.BATTERY_MAX_SAVING
            BatteryChoiceMsg.ALARM_AT5 -> UserActionKind.BATTERY_ALARM_AT_5
            BatteryChoiceMsg.ALARM_EARLIER -> UserActionKind.BATTERY_ALARM_EARLIER
        }

    fun phase(p: TripPhase): TripPhaseMsg =
        when (p) {
            TripPhase.ACQUIRING -> TripPhaseMsg.ACQUIRING
            TripPhase.TRACKING -> TripPhaseMsg.TRACKING
            TripPhase.ALARMING -> TripPhaseMsg.ALARMING
            TripPhase.SNOOZED -> TripPhaseMsg.SNOOZED
            TripPhase.OVERSHOT -> TripPhaseMsg.OVERSHOT
            TripPhase.ENDED -> TripPhaseMsg.ENDED
        }

    fun reason(r: AlarmReason): AlarmReasonMsg = AlarmReasonMsg.valueOf(r.name)

    fun outcome(o: TripOutcome): TripOutcomeMsg = TripOutcomeMsg.valueOf(o.name)

    fun endReason(r: EndReason): EndReasonMsg = EndReasonMsg.valueOf(r.name)

    fun vehicle(v: VehicleKind): VehicleKindMsg = VehicleKindMsg.valueOf(v.name)
}
