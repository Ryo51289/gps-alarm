package app.napstop.core.trip

// Trip Engine reducer: T10 §2.5, §3 (state machine), §4.12 (processing order), §7.2 (restore), T12 §5 (C1–C14).

/** Private mutable copy of [EngineState] used inside one Step only; turned back into an immutable state. */
internal class StepWork(s: EngineState) {
    val p: EngineParams = s.params
    val cfg: TripConfig = s.config
    val startedAtMs: Long = s.startedAtMs
    var now: Long = s.nowMs
    var phase: TripPhase = s.phase
    var gps: GpsStatus = s.gps
    var locationCause: AvailabilityCause = s.locationCause
    var last: FixRec? = s.last
    var stopAnchor: FixRec? = s.stopAnchor
    var recent: List<FixRec> = s.recent
    var rejects: List<FixRec> = s.rejects
    var dSmooth: Double? = s.dSmooth
    var dStartM: Double? = s.dStartM
    var minD: Double? = s.minD
    var minDChord: Boolean = s.minDChord
    var passAnchorD: Double? = s.passAnchorD
    var alarmedChordD: Double? = s.alarmedChordD
    var last3: List<Double> = s.last3
    var ground: Double? = s.ground
    var closing: Double? = s.closing
    var movingTimeS: Double = s.movingTimeS
    var movingSamples: Int = s.movingSamples
    var movingDistM: Double = s.movingDistM
    var stopStartMs: Long? = s.stopStartMs
    var slow: Boolean = s.slow
    var cvGuard: List<Double> = s.cvGuard
    var policy: SamplingPolicy? = s.policy
    var policyIntervalAtLastFixS: Int = s.policyIntervalAtLastFixS

    /** Policy at the start of the Step (T10.4 §4.8: step 9 folds its interval into policyIntervalAtLastFixS). */
    val policyAtStart: SamplingPolicy? = s.policy
    var gpsLostAtMs: Long? = s.gpsLostAtMs
    var lostEmittedBeforeFirstFix: Boolean = s.lostEmittedBeforeFirstFix
    var preAlertArmed: Boolean = s.preAlertArmed
    var preAlertFired: Boolean = s.preAlertFired
    var arrivedFired: Boolean = s.arrivedFired
    var alarm: AlarmState = s.alarm
    var overshootAtMs: Long? = s.overshootAtMs
    var overshootPastM: Int? = s.overshootPastM
    var fallback: FallbackState = s.fallback
    var battery: BatteryState = s.battery
    var maxTripDurationS: Int = s.maxTripDurationS
    var droppedFixes: Int = s.droppedFixes
    var ended: EndedState? = s.ended

    // Per-Step scratch.
    val events = ArrayList<TripEvent>()
    var fixAccepted = false
    var firstFix = false
    var estimateDone = false
    var e: Estimate? = null
    var predicted: Predicted = Predicted.NONE
    var risk = false

    fun toState(): EngineState = EngineState(
        snapshotVersion = 1, params = p, config = cfg, nowMs = now, startedAtMs = startedAtMs, phase = phase, gps = gps,
        locationCause = locationCause, last = last, stopAnchor = stopAnchor, recent = recent, rejects = rejects,
        dSmooth = dSmooth, dStartM = dStartM, minD = minD, minDChord = minDChord, passAnchorD = passAnchorD,
        alarmedChordD = alarmedChordD, last3 = last3, ground = ground, closing = closing,
        movingTimeS = movingTimeS, movingSamples = movingSamples, movingDistM = movingDistM, stopStartMs = stopStartMs,
        slow = slow, cvGuard = cvGuard, policy = policy, policyIntervalAtLastFixS = policyIntervalAtLastFixS,
        gpsLostAtMs = gpsLostAtMs, lostEmittedBeforeFirstFix = lostEmittedBeforeFirstFix, preAlertArmed = preAlertArmed,
        preAlertFired = preAlertFired, arrivedFired = arrivedFired, alarm = alarm, overshootAtMs = overshootAtMs,
        overshootPastM = overshootPastM, fallback = fallback, battery = battery, maxTripDurationS = maxTripDurationS,
        droppedFixes = droppedFixes, ended = ended,
    )
}

/** Stable event order of T10 §2.3. */
private fun eventRank(e: TripEvent): Int = when (e) {
    is GpsRecovered -> 0
    is GpsLost -> 1
    is Arrived -> 2
    is Alarm -> 3
    is Overshoot -> 4
    is PreAlert -> 5
    is Snoozed -> 6
    is LowBatteryRisk -> 7
    is SamplingPolicyChanged -> 8
    is FallbackAlarmChanged -> 9
    is TripEnded -> 10
}

object TripEngine {
    /** C11 validation, then steps 3–10 of §4.12 as an input-less Tick (C3). */
    fun start(config: TripConfig, params: EngineParams, nowMs: Long): Step {
        validateConfig(config)
        val w = StepWork(initialState(config, params, nowMs))
        runSteps3to9(w)
        return finish(w)
    }

    fun reduce(state: EngineState, input: EngineInput): Step {
        if (state.phase == TripPhase.ENDED) return unchanged(state)
        val w = StepWork(state)
        w.now = TMath.max(state.nowMs, input.atMs)
        val endedNow = applyInput(w, input)
        if (!endedNow) runSteps3to9(w)
        return finish(w)
    }

    /** §7.2 + C1, C6: restore branch, then (except DISMISSED) the same as reduce(s, Tick(now)), events merged. */
    fun restore(state: EngineState, nowMs: Long, info: RestoreInfo): Step {
        if (state.phase == TripPhase.ENDED) return unchanged(state)
        val w = StepWork(state)
        w.now = TMath.max(state.nowMs, nowMs)
        val endedNow = applyRestore(w, info)
        if (!endedNow) runSteps3to9(w)
        return finish(w)
    }

    fun encodeSnapshot(state: EngineState): String = SnapshotCodec.encode(state)

    fun decodeSnapshot(json: String): EngineState = SnapshotCodec.decode(json)
}

// ---- C11 ----

internal fun validateConfig(c: TripConfig) {
    require(c.tripId.isNotEmpty()) { "tripId: empty" }
    // C15 consequence: the snapshot JSON must stay decodable, so a tripId with an unpaired UTF-16 surrogate is refused here
    // (MiniJson's writer refuses it too). Swift strings cannot hold one, so T13 behaves the same.
    require(isWellFormedUtf16(c.tripId)) { "tripId: invalid" }
    require(c.destLat.isFinite() && c.destLat >= -90.0 && c.destLat <= 90.0) { "destLat: out of range" }
    require(c.destLng.isFinite() && c.destLng >= -180.0 && c.destLng < 180.0) { "destLng: out of range" }
    require(!(c.mode == AlarmMode.DISTANCE && c.distanceThresholdM == null)) { "distanceThresholdM: required" }
    require(!(c.mode == AlarmMode.TIME && c.timeThresholdMin == null)) { "timeThresholdMin: required" }
    val d = c.distanceThresholdM
    require(d == null || (d >= 200 && d <= 10000)) { "distanceThresholdM: out of range" }
    val t = c.timeThresholdMin
    require(t == null || (t >= 5 && t <= 60)) { "timeThresholdMin: out of range" }
}

internal fun initialState(config: TripConfig, params: EngineParams, nowMs: Long): EngineState = EngineState(
    snapshotVersion = 1, params = params, config = config, nowMs = nowMs, startedAtMs = nowMs,
    phase = TripPhase.ACQUIRING, gps = GpsStatus.NO_FIX_YET, locationCause = AvailabilityCause.AVAILABLE,
    last = null, stopAnchor = null, recent = emptyList(), rejects = emptyList(), dSmooth = null, dStartM = null, minD = null,
    passAnchorD = null, alarmedChordD = null,
    last3 = emptyList(), ground = null, closing = null, movingTimeS = 0.0, movingSamples = 0, movingDistM = 0.0,
    stopStartMs = null, slow = false, cvGuard = emptyList(), policy = null, policyIntervalAtLastFixS = 0, gpsLostAtMs = null,
    lostEmittedBeforeFirstFix = false, preAlertArmed = false, preAlertFired = false, arrivedFired = false,
    alarm = AlarmState.EMPTY, overshootAtMs = null, overshootPastM = null, fallback = FallbackState.CLEARED,
    battery = BatteryState.EMPTY, maxTripDurationS = params.maxTripMinS, droppedFixes = 0, ended = null,
)

// ---- transitions ----

private fun clampNow(w: StepWork, x: Long?): Long? = x?.let { TMath.min(it, w.now) }

/** markRing of §3; C9 sets `source` on the first alarm of the trip. */
private fun markRing(w: StepWork, reason: AlarmReason, ringAt: Long, ringNow: Boolean) {
    var a = w.alarm
    a = a.copy(ringing = true, lastReason = reason, lastRingAtMs = TMath.max(a.lastRingAtMs ?: ringAt, ringAt))
    if (a.atMs == null) a = a.copy(atMs = ringAt, reason = reason, source = if (ringNow) AlarmSource.ENGINE else AlarmSource.FALLBACK)
    w.alarm = a
}

/**
 * Emits an Alarm (numeric fields filled in [finish], C4) and moves to [newPhase]. fb per C1: entering with
 * ringNow=true supersedes a pending fallback (event only when one was set, unless [supersede] is false); a
 * fallback that already rang clears fb without SUPERSEDED.
 */
private fun fireAlarm(w: StepWork, reason: AlarmReason, ringNow: Boolean, ringAt: Long, newPhase: TripPhase, supersede: Boolean = ringNow) {
    markRing(w, reason, ringAt, ringNow)
    w.phase = newPhase
    if (supersede && w.fallback.targetAtMs != null) w.events += FallbackAlarmChanged(w.now, null, FallbackCause.SUPERSEDED)
    w.fallback = FallbackState.CLEARED
    w.events += Alarm(w.now, reason, ringNow, false, null, null, null)
}

/** Into ENDED (DISMISS, STOP_TRIP, ALARM_UNANSWERED, restore DISMISSED); C1, C10. */
private fun endTrip(w: StepWork, reason: EndReason, dismissedAtMs: Long? = null) {
    if (w.fallback.targetAtMs != null) w.events += FallbackAlarmChanged(w.now, null, FallbackCause.TRIP_ENDED)
    w.fallback = FallbackState.CLEARED
    w.alarm = w.alarm.copy(
        ringing = false,
        dismissedAtMs = if (reason == EndReason.DISMISSED) dismissedAtMs else w.alarm.dismissedAtMs,
    )
    w.phase = TripPhase.ENDED
    val outcome = when {
        w.overshootAtMs != null -> TripOutcome.MISSED
        reason == EndReason.ALARM_UNANSWERED -> TripOutcome.MISSED
        w.alarm.atMs != null -> if (w.alarm.snoozeCount >= 1) TripOutcome.SNOOZED else TripOutcome.ON_TIME
        else -> TripOutcome.CANCELLED
    }
    w.ended = EndedState(outcome, reason, w.now)
    val summary = TripSummary(
        startedAtMs = w.startedAtMs,
        alarmAtMs = w.alarm.atMs,
        alarmReason = w.alarm.reason,
        dismissedAtMs = if (reason == EndReason.DISMISSED) w.alarm.dismissedAtMs else null,
        snoozeCount = w.alarm.snoozeCount,
        travelledM = TMath.roundHalfUp(w.movingDistM),
        vehicleGuess = vehicleGuess(w.movingTimeS, w.movingDistM, w.cfg.vehicleHint, w.p),
    )
    w.events += TripEnded(w.now, outcome, reason, summary)
}

// ---- step 2 ----

/** Step 2 of §4.12. Returns true when the trip ended (go straight to step 10). */
private fun applyInput(w: StepWork, input: EngineInput): Boolean {
    when (input) {
        is LocationFix -> applyFix(w, input)
        is BatterySample -> onBattery(w, input)
        is LocationAvailability -> onAvailability(w, input.cause)
        is FallbackScheduled -> {
            val fb = w.fallback
            if (fb.targetAtMs != null && input.fallbackAtMs == fb.targetAtMs) {
                w.fallback = if (input.ok) {
                    fb.copy(status = FallbackStatus.CONFIRMED, confirmedAtMs = w.now)
                } else {
                    fb.copy(status = FallbackStatus.FAILED, confirmedAtMs = null)
                }
            }
        }
        is FallbackFired -> {
            val ringAt = TMath.min(input.firedAtMs, w.now)
            when (w.phase) {
                TripPhase.ACQUIRING, TripPhase.TRACKING ->
                    fireAlarm(w, AlarmReason.FALLBACK, false, ringAt, TripPhase.ALARMING)
                TripPhase.SNOOZED -> fireAlarm(w, AlarmReason.SNOOZE_END, false, ringAt, TripPhase.ALARMING)
                TripPhase.ALARMING, TripPhase.OVERSHOT -> {
                    val a = w.alarm
                    w.alarm = a.copy(ringing = true, lastRingAtMs = TMath.max(a.lastRingAtMs ?: ringAt, ringAt))
                }
                TripPhase.ENDED -> Unit
            }
        }
        is AlarmSilenced -> onSilenced(w)
        is UserAction -> return applyUserAction(w, input.action)
        is Tick -> Unit
    }
    return false
}

/**
 * AlarmSilenced (§3). T10.8 (C32): in OVERSHOT, when the alarm that was ringing at the overshoot (ALARMING, `ringing == true`
 * → OVERSHOT, only `Overshoot`) stops, ring once more for OVERSHOOT. `lastReason ≠ OVERSHOOT` means "no overshoot ring yet":
 * every other way into OVERSHOT marks OVERSHOOT. Not when step 3 is about to end the trip (alarmMaxActiveS since the last ring
 * is over): the expiry is judged as before the input, so the trip ends ALARM_UNANSWERED without a ring.
 */
private fun onSilenced(w: StepWork) {
    if (w.phase != TripPhase.ALARMING && w.phase != TripPhase.OVERSHOT) return
    val a = w.alarm
    val expired = w.now - (a.lastRingAtMs ?: w.now) >= w.p.alarmMaxActiveS * 1000L
    if (w.phase == TripPhase.OVERSHOT && a.ringing && a.lastReason != AlarmReason.OVERSHOOT && !expired) {
        markRing(w, AlarmReason.OVERSHOOT, w.now, true)
        w.events += Alarm(w.now, AlarmReason.OVERSHOOT, true, false, null, null, null)
    } else {
        w.alarm = a.copy(ringing = false)
    }
}

private fun applyUserAction(w: StepWork, action: UserActionKind): Boolean {
    val p = w.p
    when (action) {
        UserActionKind.DISMISS ->
            if (w.phase == TripPhase.ALARMING || w.phase == TripPhase.SNOOZED || w.phase == TripPhase.OVERSHOT) {
                endTrip(w, EndReason.DISMISSED, w.now)
                return true
            }
        UserActionKind.SNOOZE ->
            if (w.phase == TripPhase.ALARMING && w.alarm.snoozeCount < p.maxSnoozes) {
                val until = w.now + p.snoozeS * 1000L
                w.alarm = w.alarm.copy(ringing = false, snoozeCount = w.alarm.snoozeCount + 1, snoozeUntilMs = until)
                w.phase = TripPhase.SNOOZED
                w.events += Snoozed(w.now, until)
                val fbAt = until + p.fallbackLagS * 1000L
                w.fallback = FallbackState(fbAt, w.now, FallbackStatus.REQUESTED, null, false, false) // C1 (R3-1)
                w.events += FallbackAlarmChanged(w.now, fbAt, FallbackCause.SNOOZE)
            }
        UserActionKind.STOP_TRIP -> {
            endTrip(w, EndReason.USER_STOP)
            return true
        }
        UserActionKind.BATTERY_MAX_SAVING, UserActionKind.BATTERY_ALARM_AT_5, UserActionKind.BATTERY_ALARM_EARLIER ->
            onBatteryChoice(w, action)
    }
    return false
}

private fun applyFix(w: StepWork, f: LocationFix) {
    val p = w.p
    val prev = w.last
    val noRejectsSincePrev = w.rejects.isEmpty() // T10.5 round 3f: classifyFix clears `rejects` on ACCEPT
    when (val v = classifyFix(w, f)) {
        is FixVerdict.Drop -> w.droppedFixes += 1
        is FixVerdict.Reanchor -> {
            val rec = v.rec
            w.recent = listOf(rec)
            w.rejects = emptyList()
            w.last = rec
            w.dSmooth = rec.d
            w.minD = rec.d
            w.minDChord = false
            w.alarmedChordD = null // T10.7 round 2 (C31)
            w.last3 = listOf(rec.d)
            w.stopStartMs = null
            w.stopAnchor = null
            fixReceived(w, prev)
        }
        is FixVerdict.Accept -> {
            var rec = v.rec
            // T10.5 round 3/3b (§4.11): first in ACCEPT, from the state before this fix (gps, lostAfterS, last). A chord through
            // the destination lowers minD and ends the stop from before the gap (the vehicle went along the chord).
            // T10.5 round 3f: not after a fix rejected as IMPLAUSIBLE since L (`rejects` read before ACCEPT cleared it).
            // T10.7 (C30): also in ALARMING/SNOOZED (overshootAtMs == null). T10.7 round 2 (C31): after the first alarm the chord
            // only proves "came near" (alarmedChordD); minD, minDChord and the stop are left alone, so "moved away > 1 km" is
            // measured from observed fixes.
            val gap = noRejectsSincePrev &&
                isGapFix(w.phase, w.overshootAtMs, w.gps, prev, rec, p, w.policyIntervalAtLastFixS, w.policy)
            val notYet = (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null
            val dChord = if (gap) chordClosest(prev!!, rec, w.cfg) else null
            if (dChord != null) {
                if (notYet) {
                    w.stopStartMs = null
                    w.stopAnchor = null
                    val m = w.minD
                    if (m == null || dChord < m) {
                        w.minD = dChord
                        w.minDChord = true // T10.5 round 3e
                    }
                } else {
                    val a = w.alarmedChordD
                    w.alarmedChordD = if (a == null) dChord else TMath.min(a, dChord)
                }
            }
            if (prev != null) {
                val s = speedSample(prev, rec, normalisedSpeed(f.speedMps), p)
                rec = rec.copy(groundSample = s.groundSample)
                applyMotion(w, rec, prev, s)
            }
            w.recent = updateRecent(w.recent, rec, p)
            w.dSmooth = TMath.medianHi(w.recent.map { it.d })
            w.last = rec
            updateMinDLast3(w)
            fixReceived(w, prev)
        }
    }
}

private fun fixReceived(w: StepWork, prev: FixRec?) {
    w.fixAccepted = true
    w.firstFix = prev == null
    onFixReceived(w)
    w.policyIntervalAtLastFixS = w.policy?.intervalS ?: 0 // C2: interval the fix was requested with
    if (w.phase == TripPhase.ACQUIRING) w.phase = TripPhase.TRACKING
    if (w.firstFix) w.dStartM = w.dSmooth
}

// ---- restore branch (§7.2, C1) ----

private fun applyRestore(w: StepWork, info: RestoreInfo): Boolean {
    val alarmed = w.alarm.atMs != null
    val target = w.fallback.targetAtMs
    val due = target != null && target <= w.now
    when (info.status) {
        FallbackRestoreStatus.DISMISSED -> {
            val firedAt = clampNow(w, info.firedAtMs) ?: clampNow(w, target) ?: w.now
            if (!alarmed) {
                markRing(w, AlarmReason.FALLBACK, firedAt, false)
                w.events += Alarm(w.now, AlarmReason.FALLBACK, false, false, null, null, null)
            } else if (w.phase == TripPhase.SNOOZED) {
                markRing(w, AlarmReason.SNOOZE_END, firedAt, false)
                w.events += Alarm(w.now, AlarmReason.SNOOZE_END, false, false, null, null, null)
            }
            val dismissedAt = TMath.max(w.alarm.atMs ?: w.now, clampNow(w, info.dismissedAtMs) ?: w.now)
            endTrip(w, EndReason.DISMISSED, dismissedAt)
            return true
        }
        FallbackRestoreStatus.RANG -> rang(w, alarmed, clampNow(w, info.firedAtMs) ?: w.now)
        FallbackRestoreStatus.UNKNOWN -> if (due) rang(w, alarmed, clampNow(w, info.firedAtMs) ?: target!!)
        FallbackRestoreStatus.MISSING ->
            if (due && !alarmed) {
                fireAlarm(w, AlarmReason.FALLBACK_MISSED, true, w.now, TripPhase.ALARMING, supersede = false)
            } else if (!alarmed) {
                w.fallback = FallbackState(null, null, FallbackStatus.NONE, null, true, false)
            } else if (w.phase == TripPhase.SNOOZED) {
                val until = w.alarm.snoozeUntilMs
                if (until != null && w.now < until) {
                    val at = until + w.p.fallbackLagS * 1000L
                    w.fallback = FallbackState(at, w.now, FallbackStatus.REQUESTED, null, false, false)
                    w.events += FallbackAlarmChanged(w.now, at, FallbackCause.RESYNC)
                } else {
                    w.fallback = FallbackState.CLEARED
                }
            }
        FallbackRestoreStatus.PENDING -> Unit
    }
    return false
}

private fun rang(w: StepWork, alarmed: Boolean, firedAt: Long) {
    if (!alarmed) {
        fireAlarm(w, AlarmReason.FALLBACK, false, firedAt, TripPhase.ALARMING)
    } else if (w.phase == TripPhase.SNOOZED) {
        fireAlarm(w, AlarmReason.SNOOZE_END, false, firedAt, TripPhase.ALARMING)
    }
}

// ---- steps 3–9 ----

private fun runSteps3to9(w: StepWork) {
    val p = w.p
    // 3. Alarm nobody answered.
    if (w.phase == TripPhase.ALARMING || w.phase == TripPhase.OVERSHOT) {
        val lastRing = w.alarm.lastRingAtMs ?: w.now
        if (w.now - lastRing >= p.alarmMaxActiveS * 1000L) {
            endTrip(w, EndReason.ALARM_UNANSWERED)
            return
        }
    }
    // 4. GPS monitor by time.
    onTime(w)
    // 5. Estimator (once per Step, C7).
    val e = estimate(w)
    w.e = e
    w.estimateDone = true
    if (w.fixAccepted && e != null) updateSlow(w, e)
    if (w.firstFix && e != null) w.maxTripDurationS = maxTripDurationFromFirstFix(e.etaS, p)
    // 6. Snooze over.
    if (w.phase == TripPhase.SNOOZED) {
        val until = w.alarm.snoozeUntilMs
        if (until != null && w.now >= until) fireAlarm(w, AlarmReason.SNOOZE_END, true, w.now, TripPhase.ALARMING)
    }
    // 7. Overshoot.
    if (w.fixAccepted && isOvershoot(w)) {
        val past = TMath.roundHalfUp(w.dSmooth!! - nearD(w)!!) // T10.7 round 2 (C31): from the estimated closest point
        when (w.phase) {
            TripPhase.ALARMING ->
                if (w.alarm.ringing) w.phase = TripPhase.OVERSHOT
                else fireAlarm(w, AlarmReason.OVERSHOOT, true, w.now, TripPhase.OVERSHOT)
            else -> fireAlarm(w, AlarmReason.OVERSHOOT, true, w.now, TripPhase.OVERSHOT)
        }
        w.overshootAtMs = w.now
        w.overshootPastM = past
        w.events += Overshoot(w.now, past)
    }
    // 8. T10.6 (3), C27: slow-vehicle passed-closest mark, on every Step with an accepted fix (ACCEPT/REANCHOR), in every phase.
    if (w.fixAccepted) updatePassAnchor(w, e)
    // 8. Alarm reason / pre-alert.
    if ((w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null) {
        if (w.firstFix && e != null) w.preAlertArmed = !inZone(e, w.cfg, p)
        val reason = alarmReason(w, e)
        if (reason != null) {
            fireAlarm(w, reason, true, w.now, TripPhase.ALARMING)
        } else if (e != null && shouldPreAlert(w, e)) {
            w.preAlertFired = true
            w.events += PreAlert(w.now, 0, null)
        }
    }
    // Predicted alarm time, once, after step 8 (C7).
    w.predicted = predictedAlarmAt(w, e)
    // 9. Arrived, battery risk, sampling, fallback.
    if (w.fixAccepted && isArrived(w)) {
        w.arrivedFired = true
        w.events += Arrived(w.now, TMath.roundHalfUp(w.dSmooth!!))
    }
    w.risk = evaluateBatteryRisk(w, w.predicted.noBattery)
    planSampling(w, e, w.predicted.withBattery)
    // T10.4 (GAP-2, §4.8, §4.12): lostAfterS never shrinks between two fixes, so c2 stays > now and Tick(now) stays silent (I14).
    w.policyIntervalAtLastFixS = TMath.max(
        w.policyIntervalAtLastFixS,
        TMath.max(w.policyAtStart?.intervalS ?: 0, w.policy?.intervalS ?: 0),
    )
    planFallback(w, e, w.predicted.withBattery)
}

// ---- step 10 ----

private fun finish(w: StepWork): Step {
    if (!w.estimateDone) w.e = estimate(w) // ENDED Steps: view computed from the ENDED state at now (C6, C22)
    // C16 (T10.3): snoozeUntilMs is non-null only while SNOOZED; every reader ran earlier in the Step.
    if (w.phase != TripPhase.SNOOZED && w.alarm.snoozeUntilMs != null) w.alarm = w.alarm.copy(snoozeUntilMs = null)
    val st = w.toState()
    val predicted = w.predicted.withBattery
    val view = buildView(st, w.e, predicted, w.risk, wakeAt(st, w.predicted.wakeBasis, w.predicted.wakeBattery))
    val snoozeAllowed = st.phase == TripPhase.ALARMING && st.alarm.snoozeCount < st.params.maxSnoozes
    val events = ArrayList<TripEvent>(w.events.size)
    for (ev in w.events) {
        events += when (ev) {
            is Alarm -> ev.copy(snoozeAllowed = snoozeAllowed, distanceM = view.distanceM, etaS = view.etaS, batteryPct = view.batteryPct)
            is PreAlert -> ev.copy(distanceM = view.distanceM ?: 0, etaS = view.etaS)
            else -> ev
        }
    }
    return Step(st, events.sortedBy { eventRank(it) }, view)
}

private fun unchanged(s: EngineState): Step {
    val w = StepWork(s)
    w.e = estimate(w)
    return Step(s, emptyList(), buildView(s, w.e, null, false, null))
}
