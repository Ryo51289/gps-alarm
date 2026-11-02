package app.napstop.core.trip

// T10 §4.8 GPS monitor (+ C5 for event fields).

internal fun lostAfterS(p: EngineParams, policyIntervalAtLastFixS: Int, policy: SamplingPolicy?): Int =
    TMath.max(p.gpsLostMinS, p.gpsLostIntervalFactor * TMath.max(policyIntervalAtLastFixS, policy?.intervalS ?: 0))

private fun lastFixAgeS(w: StepWork): Int? = w.last?.let { TMath.roundHalfUp(TMath.toS(w.now - it.fixAtMs)) }

private fun emitLost(w: StepWork, cause: GpsLostCause) {
    w.events += GpsLost(w.now, cause, lastFixAgeS(w))
    w.gpsLostAtMs = w.now
}

/** A fix was ACCEPTed or REANCHORed. */
internal fun onFixReceived(w: StepWork) {
    val lostAt = w.gpsLostAtMs
    val recovering = w.gps == GpsStatus.LOST || (w.gps == GpsStatus.NO_FIX_YET && w.lostEmittedBeforeFirstFix)
    if (recovering && lostAt != null) {
        w.events += GpsRecovered(w.now, TMath.roundHalfUp(TMath.toS(w.now - lostAt)))
        w.gpsLostAtMs = null
    }
    w.gps = GpsStatus.OK
    w.locationCause = AvailabilityCause.AVAILABLE
}

internal fun onAvailability(w: StepWork, cause: AvailabilityCause) {
    w.locationCause = cause
    if (cause == AvailabilityCause.AVAILABLE) return
    val lostCause = if (cause == AvailabilityCause.PERMISSION_REVOKED) GpsLostCause.PERMISSION_REVOKED else GpsLostCause.SERVICES_OFF
    when (w.gps) {
        GpsStatus.OK -> {
            w.gps = GpsStatus.LOST
            emitLost(w, lostCause)
        }
        GpsStatus.NO_FIX_YET -> if (!w.lostEmittedBeforeFirstFix) {
            w.lostEmittedBeforeFirstFix = true
            emitLost(w, lostCause)
        }
        GpsStatus.LOST -> Unit
    }
}

/** Step 4 of §4.12: acquire timeout and lost timeout. */
internal fun onTime(w: StepWork) {
    val p = w.p
    when (w.gps) {
        GpsStatus.NO_FIX_YET ->
            if (!w.lostEmittedBeforeFirstFix && w.now - w.startedAtMs >= p.acquireTimeoutS * 1000L) {
                w.lostEmittedBeforeFirstFix = true
                emitLost(w, GpsLostCause.NEVER_ACQUIRED)
            }
        GpsStatus.OK -> {
            val last = w.last ?: return
            if (w.now - last.fixAtMs >= lostAfterS(p, w.policyIntervalAtLastFixS, w.policy) * 1000L) {
                w.gps = GpsStatus.LOST
                emitLost(w, GpsLostCause.NO_FIX_TIMEOUT)
            }
        }
        GpsStatus.LOST -> Unit
    }
}
