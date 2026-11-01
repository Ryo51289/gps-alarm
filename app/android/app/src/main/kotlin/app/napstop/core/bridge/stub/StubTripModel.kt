package app.napstop.core.bridge.stub

import app.napstop.core.bridge.AlarmMsg
import app.napstop.core.bridge.AlarmModeMsg
import app.napstop.core.bridge.AlarmReasonMsg
import app.napstop.core.bridge.ArrivedMsg
import app.napstop.core.bridge.AvailabilityCauseMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.EndReasonMsg
import app.napstop.core.bridge.FallbackStatusMsg
import app.napstop.core.bridge.FinishedTripMsg
import app.napstop.core.bridge.GpsLostCauseMsg
import app.napstop.core.bridge.GpsLostMsg
import app.napstop.core.bridge.GpsRecoveredMsg
import app.napstop.core.bridge.GpsStatusMsg
import app.napstop.core.bridge.LowBatteryRiskMsg
import app.napstop.core.bridge.OvershootMsg
import app.napstop.core.bridge.PreAlertMsg
import app.napstop.core.bridge.SamplingTierMsg
import app.napstop.core.bridge.SnoozedMsg
import app.napstop.core.bridge.TripConfigMsg
import app.napstop.core.bridge.TripEndedMsg
import app.napstop.core.bridge.TripOutcomeMsg
import app.napstop.core.bridge.TripPhaseMsg
import app.napstop.core.bridge.TripStateMsg
import app.napstop.core.bridge.TripStateUpdateMsg
import app.napstop.core.bridge.TripUpdateMsg
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Scripted stub trips (spec T14 §5.4), selected by `SimulationMsg.traceAsset`. */
enum class StubScenario(val asset: String) {
    NORMAL("stub/normal"),
    GPS_LOST("stub/gps_lost"),
    LOW_BATTERY("stub/low_battery"),
    OVERSHOOT("stub/overshoot"),
    NO_FIX("stub/no_fix"),
    ;

    companion object {
        fun fromAsset(asset: String): StubScenario? = entries.firstOrNull { it.asset == asset }
    }
}

enum class StubAction { DISMISS, SNOOZE, STOP, BATTERY_MAX_SAVING, BATTERY_ALARM_AT_5, BATTERY_ALARM_EARLIER }

/** Whole state of a stub trip; persisted by StubStore. Holds no coordinates. */
data class StubTripState(
    val config: TripConfigMsg,
    val scenario: StubScenario,
    val speedFactor: Double,
    /** startTrip had a SimulationMsg (currentTrip() returns it); false = NORMAL at 1x, a "real" trip. */
    val simulated: Boolean,
    val startedAtMs: Long,
    val nowMs: Long,
    val phase: TripPhaseMsg,
    val gps: GpsStatusMsg,
    val preAlertFired: Boolean,
    val arrivedFired: Boolean,
    val lowBatteryEmitted: Boolean,
    val gpsLostAtMs: Long?,
    val neverAcquiredEmitted: Boolean,
    val alarmAtMs: Long?,
    val firstAlarmReason: AlarmReasonMsg?,
    val lastAlarmReason: AlarmReasonMsg?,
    val ringing: Boolean,
    val lastRingAtMs: Long?,
    val snoozeCount: Int,
    val snoozeUntilMs: Long?,
    val overshot: Boolean,
    val batteryChoice: BatteryChoiceMsg?,
    val outcome: TripOutcomeMsg?,
    val endReason: EndReasonMsg?,
    val endedAtMs: Long?,
    val dismissedAtMs: Long?,
) {
    override fun toString(): String = "StubTripState(tripId=${config.tripId}, scenario=$scenario, phase=$phase)"
}

/** One step: new state, updates to send (state first, then events in T10 §2.3 order), ended record. */
data class StubStep(val state: StubTripState, val updates: List<TripUpdateMsg>, val finished: FinishedTripMsg?)

/**
 * Pure model of a scripted trip (spec T14 §5.4): no Android API, deterministic in
 * (state, nowMs). Virtual time v = (now - startedAt) * speedFactor / 1000 s; every
 * `atMs` in a message is the real clock. Values are illustrative only; the types and
 * the ordering follow the stream contract (§2) that the real engine (T15) also obeys.
 */
object StubTripModel {
    const val D0_M = 20_000.0
    const val SPEED_MPS = 15.0
    const val ACQUIRE_S = 5.0
    const val GPS_LOST_FROM_S = 60.0
    const val GPS_LOST_TO_S = 240.0
    const val NEVER_ACQUIRED_AT_S = 120.0
    const val LOW_BATT_RISK_AT_S = 30.0
    const val BATTERY_NORMAL_PCT = 80L
    const val SNOOZE_S = 60.0
    const val MAX_SNOOZES = 1
    const val ALARM_MAX_ACTIVE_S = 3_600.0
    const val TIMEOUT_S = 14_400.0
    const val OVERSHOOT_PAST_M = 1_000.0
    const val ARRIVED_M = 50.0
    const val FALLBACK_LAG_S = 30.0

    private const val SPEED_KMH = 54.0
    private const val GPS_LOST_LAST_FIX_AGE_S = 15L
    private const val LOW_BATT_START_PCT = 30L
    private const val LOW_BATT_MIN_PCT = 5L
    private const val LOW_BATT_AVAILABLE_MIN = 40L
    private const val LOW_BATT_NEEDED_MIN = 55L
    private const val PRE_ALERT_ETA_S = 1_800L
    private const val PRE_ALERT_MIN_M = 3_000.0

    fun start(
        config: TripConfigMsg,
        scenario: StubScenario,
        speedFactor: Double,
        simulated: Boolean,
        nowMs: Long,
    ): StubStep {
        val s =
            StubTripState(
                config = config,
                scenario = scenario,
                speedFactor = speedFactor,
                simulated = simulated,
                startedAtMs = nowMs,
                nowMs = nowMs,
                phase = TripPhaseMsg.ACQUIRING,
                gps = GpsStatusMsg.NO_FIX_YET,
                preAlertFired = false,
                arrivedFired = false,
                lowBatteryEmitted = false,
                gpsLostAtMs = null,
                neverAcquiredEmitted = false,
                alarmAtMs = null,
                firstAlarmReason = null,
                lastAlarmReason = null,
                ringing = false,
                lastRingAtMs = null,
                snoozeCount = 0,
                snoozeUntilMs = null,
                overshot = false,
                batteryChoice = null,
                outcome = null,
                endReason = null,
                endedAtMs = null,
                dismissedAtMs = null,
            )
        return StubStep(s, listOf(TripStateUpdateMsg(view(s))), null)
    }

    fun advance(s: StubTripState, nowMs: Long): StubStep {
        if (s.phase == TripPhaseMsg.ENDED) return StubStep(s, emptyList(), null)
        val step = Builder(s.copy(nowMs = max(s.nowMs, nowMs)))
        step.advance()
        return step.build()
    }

    /** advance(now), then the action; one merged step. */
    fun act(s: StubTripState, action: StubAction, nowMs: Long): StubStep {
        if (s.phase == TripPhaseMsg.ENDED) return StubStep(s, emptyList(), null)
        val step = Builder(s.copy(nowMs = max(s.nowMs, nowMs)))
        step.advance()
        step.act(action)
        return step.build()
    }

    fun view(s: StubTripState): TripStateMsg {
        val v = virtualS(s)
        val d = distance(s, v)
        val passed = passed(s, v)
        val noFix = s.gps == GpsStatusMsg.NO_FIX_YET
        val etaS = if (noFix || passed) null else round(d / SPEED_MPS)
        val predicted = predictedAlarmAtMs(s)
        val (fallbackAtMs, fallbackStatus) =
            when {
                predicted != null -> predicted + realMs(s, FALLBACK_LAG_S) to FallbackStatusMsg.CONFIRMED
                s.phase == TripPhaseMsg.SNOOZED && s.snoozeUntilMs != null ->
                    s.snoozeUntilMs + realMs(s, FALLBACK_LAG_S) to FallbackStatusMsg.CONFIRMED
                else -> null to FallbackStatusMsg.NOT_SET
            }
        val lowBattery = s.scenario == StubScenario.LOW_BATTERY
        return TripStateMsg(
            tripId = s.config.tripId,
            atMs = s.nowMs,
            phase = s.phase,
            gps = s.gps,
            locationCause = AvailabilityCauseMsg.AVAILABLE,
            distanceM = if (noFix) null else round(d),
            routeDistanceEstM = if (noFix) null else round(d * 1.2),
            distanceErrorM = if (s.gps == GpsStatusMsg.LOST) round(30 + 2 * (v - GPS_LOST_FROM_S)) else null,
            isEstimated = s.gps == GpsStatusMsg.LOST,
            etaS = etaS,
            etaMinS = etaS?.let { round(it * 0.9) },
            etaMaxS = etaS?.let { round(it * 1.2) },
            speedKmh =
                when {
                    !noFix && s.scenario != StubScenario.OVERSHOOT && d == 0.0 -> 0.0
                    s.gps == GpsStatusMsg.OK -> SPEED_KMH
                    else -> null
                },
            progress = if (noFix) null else if (passed) 1.0 else clamp01(1 - d / D0_M),
            alarmMarkerProgress = if (noFix) null else clamp01(1 - dTrig(s.config) / D0_M),
            predictedAlarmAtMs = predicted,
            samplingTier = samplingTier(s, v),
            fallbackAtMs = fallbackAtMs,
            fallbackStatus = fallbackStatus,
            batteryPct = if (lowBattery) lowBatteryPct(v) else BATTERY_NORMAL_PCT,
            batteryRisk = lowBattery && v >= LOW_BATT_RISK_AT_S && s.phase.isAcquiringOrTracking(),
            batteryChoice = s.batteryChoice,
            preAlertFired = s.preAlertFired,
            alarmAtMs = s.alarmAtMs,
            alarmReason = s.lastAlarmReason,
            alarmRinging = s.ringing,
            snoozeCount = s.snoozeCount.toLong(),
            snoozeUntilMs = s.snoozeUntilMs,
            overshootPastM = if (passed) round(d) else null,
            outcome = s.outcome,
            vehicleGuess = s.config.vehicleHint,
            travelledM = round(if (s.scenario == StubScenario.OVERSHOOT) travelled(v) else min(travelled(v), D0_M)),
        )
    }

    // ------------------------------------------------------------------ model

    /** Virtual seconds since start. */
    fun virtualS(s: StubTripState): Double = (s.nowMs - s.startedAtMs) * s.speedFactor / 1000.0

    /** Virtual [seconds] as real milliseconds. */
    fun realMs(s: StubTripState, seconds: Double): Long = round(seconds * 1000.0 / s.speedFactor)

    fun travelled(v: Double): Double = SPEED_MPS * max(0.0, v - ACQUIRE_S)

    fun distance(s: StubTripState, v: Double): Double =
        if (s.scenario == StubScenario.OVERSHOOT) abs(D0_M - travelled(v)) else max(0.0, D0_M - travelled(v))

    fun passed(s: StubTripState, v: Double): Boolean = s.scenario == StubScenario.OVERSHOOT && travelled(v) > D0_M

    /** Distance to the destination at which the main alarm rings. */
    fun dTrig(config: TripConfigMsg): Double =
        when (config.mode) {
            AlarmModeMsg.DISTANCE -> (config.distanceThresholdM ?: 0L).toDouble()
            AlarmModeMsg.TIME -> (config.timeThresholdMin ?: 0L) * 60.0 * SPEED_MPS
            AlarmModeMsg.SMART -> max(600 * SPEED_MPS, 1000.0)
        }

    /** Virtual second of the main alarm (first fix if dTrig >= D0, like T10 Q3). */
    fun vAlarm(config: TripConfigMsg): Double = ACQUIRE_S + max(0.0, D0_M - dTrig(config)) / SPEED_MPS

    private fun predictedAlarmAtMs(s: StubTripState): Long? {
        if (!s.phase.isAcquiringOrTracking() || s.alarmAtMs != null) return null
        val vAt = if (s.scenario == StubScenario.NO_FIX) TIMEOUT_S else vAlarm(s.config)
        return s.startedAtMs + realMs(s, vAt)
    }

    private fun samplingTier(s: StubTripState, v: Double): SamplingTierMsg? =
        when (s.phase) {
            TripPhaseMsg.TRACKING -> {
                val t = vAlarm(s.config) - v
                when {
                    t > 3_600 -> SamplingTierMsg.SPARSE
                    t >= 900 -> SamplingTierMsg.MEDIUM
                    else -> SamplingTierMsg.DENSE
                }
            }
            TripPhaseMsg.ENDED -> null
            else -> SamplingTierMsg.DENSE
        }

    private fun lowBatteryPct(v: Double): Long = max(LOW_BATT_MIN_PCT, LOW_BATT_START_PCT - floor(v / 60).toLong())

    private fun alarmReasonFor(mode: AlarmModeMsg): AlarmReasonMsg =
        when (mode) {
            AlarmModeMsg.DISTANCE -> AlarmReasonMsg.DISTANCE
            AlarmModeMsg.TIME -> AlarmReasonMsg.TIME
            AlarmModeMsg.SMART -> AlarmReasonMsg.SMART_TIME
        }

    private fun TripPhaseMsg.isAcquiringOrTracking() = this == TripPhaseMsg.ACQUIRING || this == TripPhaseMsg.TRACKING

    /** roundHalfUp (T10 §4.0). */
    private fun round(x: Double): Long = floor(x + 0.5).toLong()

    private fun clamp01(x: Double): Double = x.coerceIn(0.0, 1.0)

    /** T10 §2.3 order of events within one Step. */
    private fun order(e: TripUpdateMsg): Int =
        when (e) {
            is GpsRecoveredMsg -> 0
            is GpsLostMsg -> 1
            is ArrivedMsg -> 2
            is AlarmMsg -> 3
            is OvershootMsg -> 4
            is PreAlertMsg -> 5
            is SnoozedMsg -> 6
            is LowBatteryRiskMsg -> 7
            is TripEndedMsg -> 8
            is TripStateUpdateMsg -> -1
        }

    /** Mutable working copy of one Step. */
    private class Builder(var s: StubTripState) {
        val events = mutableListOf<TripUpdateMsg>()
        var finished: FinishedTripMsg? = null
        var alarmInStep = false

        val now get() = s.nowMs
        val tripId get() = s.config.tripId

        fun advance() {
            val v = virtualS(s)
            val d = distance(s, v)
            // 1. First fix.
            if (s.phase == TripPhaseMsg.ACQUIRING && v >= ACQUIRE_S && s.scenario != StubScenario.NO_FIX) {
                s = s.copy(phase = TripPhaseMsg.TRACKING, gps = GpsStatusMsg.OK)
            }
            // 2. GPS loss scripts.
            gps(v)
            // 3. Arrived.
            if (d <= ARRIVED_M && !s.arrivedFired && s.phase != TripPhaseMsg.ACQUIRING) {
                s = s.copy(arrivedFired = true)
                events += ArrivedMsg(tripId, now, round(d))
            }
            // 4. Main alarm, snooze end, timeout (at most one Alarm per Step).
            when {
                s.phase == TripPhaseMsg.SNOOZED && now >= (s.snoozeUntilMs ?: Long.MAX_VALUE) ->
                    alarm(AlarmReasonMsg.SNOOZE_END, snoozeAllowed = false)
                s.phase == TripPhaseMsg.TRACKING && v >= vAlarm(s.config) ->
                    alarm(alarmReasonFor(s.config.mode), snoozeAllowed = s.snoozeCount < MAX_SNOOZES)
                s.scenario == StubScenario.NO_FIX && s.phase == TripPhaseMsg.ACQUIRING && v >= TIMEOUT_S ->
                    alarm(AlarmReasonMsg.TIMEOUT, snoozeAllowed = s.snoozeCount < MAX_SNOOZES)
            }
            // 5. Overshoot.
            if (s.scenario == StubScenario.OVERSHOOT &&
                passed(s, v) &&
                d >= OVERSHOOT_PAST_M &&
                !s.overshot &&
                (s.phase == TripPhaseMsg.TRACKING || s.phase == TripPhaseMsg.ALARMING || s.phase == TripPhaseMsg.SNOOZED)
            ) {
                val needsAlarm = !alarmInStep && (s.phase != TripPhaseMsg.ALARMING || !s.ringing)
                if (needsAlarm) alarm(AlarmReasonMsg.OVERSHOOT, snoozeAllowed = false)
                s = s.copy(phase = TripPhaseMsg.OVERSHOT, overshot = true, snoozeUntilMs = null)
                events += OvershootMsg(tripId, now, round(d))
            }
            // 6. Pre-alert.
            if (s.config.preAlertEnabled && !s.preAlertFired && s.phase == TripPhaseMsg.TRACKING && !alarmInStep) {
                val due =
                    if (s.config.mode == AlarmModeMsg.DISTANCE) {
                        d <= max(5.0 * (s.config.distanceThresholdM ?: 0L), PRE_ALERT_MIN_M)
                    } else {
                        !passed(s, v) && round(d / SPEED_MPS) <= PRE_ALERT_ETA_S
                    }
                if (due) {
                    s = s.copy(preAlertFired = true)
                    val etaS = if (passed(s, v)) null else round(d / SPEED_MPS)
                    events += PreAlertMsg(tripId, now, round(d), etaS)
                }
            }
            // 7. Low battery.
            if (s.scenario == StubScenario.LOW_BATTERY &&
                v >= LOW_BATT_RISK_AT_S &&
                !s.lowBatteryEmitted &&
                s.batteryChoice == null &&
                s.phase.isAcquiringOrTracking()
            ) {
                s = s.copy(lowBatteryEmitted = true)
                events += LowBatteryRiskMsg(tripId, now, lowBatteryPct(v), LOW_BATT_AVAILABLE_MIN, LOW_BATT_NEEDED_MIN)
            }
            // 8. Alarm nobody answered.
            val lastRing = s.lastRingAtMs
            if ((s.phase == TripPhaseMsg.ALARMING || s.phase == TripPhaseMsg.OVERSHOT) &&
                lastRing != null &&
                (now - lastRing) * s.speedFactor / 1000.0 >= ALARM_MAX_ACTIVE_S
            ) {
                end(EndReasonMsg.ALARM_UNANSWERED)
            }
        }

        fun act(action: StubAction) {
            if (s.phase == TripPhaseMsg.ENDED) return
            when (action) {
                StubAction.SNOOZE ->
                    if (s.phase == TripPhaseMsg.ALARMING && s.snoozeCount < MAX_SNOOZES) {
                        val until = now + realMs(s, SNOOZE_S)
                        s =
                            s.copy(
                                phase = TripPhaseMsg.SNOOZED,
                                snoozeCount = s.snoozeCount + 1,
                                snoozeUntilMs = until,
                                ringing = false,
                            )
                        events += SnoozedMsg(tripId, now, until)
                    }
                StubAction.DISMISS ->
                    if (s.phase == TripPhaseMsg.ALARMING ||
                        s.phase == TripPhaseMsg.SNOOZED ||
                        s.phase == TripPhaseMsg.OVERSHOT
                    ) {
                        s = s.copy(dismissedAtMs = now)
                        end(EndReasonMsg.DISMISSED)
                    }
                StubAction.STOP -> end(EndReasonMsg.USER_STOP)
                StubAction.BATTERY_MAX_SAVING -> s = s.copy(batteryChoice = BatteryChoiceMsg.MAX_SAVING)
                StubAction.BATTERY_ALARM_AT_5 -> s = s.copy(batteryChoice = BatteryChoiceMsg.ALARM_AT5)
                StubAction.BATTERY_ALARM_EARLIER -> s = s.copy(batteryChoice = BatteryChoiceMsg.ALARM_EARLIER)
            }
        }

        fun build(): StubStep {
            val sorted = events.sortedBy { order(it) } // stable
            return StubStep(s, listOf(TripStateUpdateMsg(view(s))) + sorted, finished)
        }

        private fun gps(v: Double) {
            when (s.scenario) {
                StubScenario.NO_FIX ->
                    if (v >= NEVER_ACQUIRED_AT_S && !s.neverAcquiredEmitted) {
                        s = s.copy(neverAcquiredEmitted = true)
                        events += GpsLostMsg(tripId, now, GpsLostCauseMsg.NEVER_ACQUIRED, null)
                    }
                StubScenario.GPS_LOST ->
                    if (v >= GPS_LOST_FROM_S && v < GPS_LOST_TO_S && s.gps == GpsStatusMsg.OK) {
                        s = s.copy(gps = GpsStatusMsg.LOST, gpsLostAtMs = now)
                        events += GpsLostMsg(tripId, now, GpsLostCauseMsg.NO_FIX_TIMEOUT, GPS_LOST_LAST_FIX_AGE_S)
                    } else if (v >= GPS_LOST_TO_S && s.gps == GpsStatusMsg.LOST) {
                        val lostAt = s.gpsLostAtMs ?: now
                        s = s.copy(gps = GpsStatusMsg.OK, gpsLostAtMs = null)
                        events += GpsRecoveredMsg(tripId, now, round((now - lostAt) * s.speedFactor / 1000.0))
                    }
                else -> Unit
            }
        }

        private fun alarm(reason: AlarmReasonMsg, snoozeAllowed: Boolean) {
            alarmInStep = true
            s =
                s.copy(
                    phase = TripPhaseMsg.ALARMING,
                    ringing = true,
                    lastRingAtMs = now,
                    lastAlarmReason = reason,
                    alarmAtMs = s.alarmAtMs ?: now,
                    firstAlarmReason = s.firstAlarmReason ?: reason,
                    snoozeUntilMs = null,
                )
            val view = view(s)
            events +=
                AlarmMsg(
                    tripId = tripId,
                    atMs = now,
                    reason = reason,
                    ringNow = true,
                    snoozeAllowed = snoozeAllowed,
                    distanceM = view.distanceM,
                    etaS = view.etaS,
                    batteryPct = if (s.scenario == StubScenario.LOW_BATTERY) view.batteryPct else null,
                )
        }

        private fun end(reason: EndReasonMsg) {
            val outcome =
                when {
                    s.overshot -> TripOutcomeMsg.MISSED
                    reason == EndReasonMsg.ALARM_UNANSWERED -> TripOutcomeMsg.MISSED
                    s.alarmAtMs != null && s.snoozeCount >= 1 -> TripOutcomeMsg.SNOOZED
                    s.alarmAtMs != null -> TripOutcomeMsg.ON_TIME
                    else -> TripOutcomeMsg.CANCELLED
                }
            s =
                s.copy(
                    phase = TripPhaseMsg.ENDED,
                    ringing = false,
                    endedAtMs = now,
                    endReason = reason,
                    outcome = outcome,
                    snoozeUntilMs = null,
                )
            val record =
                FinishedTripMsg(
                    tripId = tripId,
                    outcome = outcome,
                    endReason = reason,
                    endedAtMs = now,
                    startedAtMs = s.startedAtMs,
                    alarmAtMs = s.alarmAtMs,
                    alarmReason = s.firstAlarmReason,
                    dismissedAtMs = s.dismissedAtMs,
                    snoozeCount = s.snoozeCount.toLong(),
                    travelledM = view(s).travelledM,
                    vehicleGuess = s.config.vehicleHint,
                )
            finished = record
            events += TripEndedMsg(now, record)
        }
    }
}
