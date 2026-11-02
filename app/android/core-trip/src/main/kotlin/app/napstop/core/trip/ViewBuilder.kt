package app.napstop.core.trip

// T10 §4.16 view formulas; §4.14 history fields.

internal fun vehicleGuess(movingTimeS: Double, movingDistM: Double, hint: VehicleKind, p: EngineParams): VehicleKind =
    if (movingTimeS > 0.0 && movingDistM / movingTimeS * 3.6 < p.vehicleBusMaxAvgKmh.toDouble()) {
        VehicleKind.BUS
    } else if (hint == VehicleKind.TRAIN || hint == VehicleKind.COACH) {
        hint
    } else {
        VehicleKind.UNKNOWN
    }

internal fun buildView(s: EngineState, e: Estimate?, predicted: Long?, risk: Boolean, wakeAtMs: Long?): TripView {
    val p = s.params
    val cfg = s.config
    val dStart = s.dStartM
    var progress: Double? = null
    var marker: Double? = null
    if (e != null && dStart != null) {
        progress = if (dStart <= 0.0) 1.0 else TMath.clamp(1.0 - e.dNow / dStart, 0.0, 1.0)
        val pen = p.etaStopPenaltyS
        val markerD = when (cfg.mode) {
            AlarmMode.DISTANCE -> thrM(cfg) * p.distanceModeFactor
            AlarmMode.TIME -> TMath.max(p.arrivedRadiusM.toDouble(), e.cvDr * TMath.max(0, thrS(cfg) - pen).toDouble())
            AlarmMode.SMART ->
                if (s.slow) {
                    slowDistM(p)
                } else {
                    TMath.max(p.smartFloorM.toDouble(), e.cvDr * TMath.max(0, p.smartTargetS - pen).toDouble())
                }
        }
        marker = if (dStart <= 0.0) 1.0 else TMath.clamp(1.0 - markerD / dStart, 0.0, 1.0)
    }
    return TripView(
        tripId = cfg.tripId,
        atMs = s.nowMs,
        phase = s.phase,
        gps = s.gps,
        locationCause = s.locationCause,
        distanceM = e?.let { TMath.roundHalfUp(it.dNow) },
        routeDistanceEstM = e?.let { TMath.roundHalfUp(it.dNow * it.k) },
        distanceErrorM = e?.let { TMath.roundHalfUp(it.errM) },
        isEstimated = s.gps == GpsStatus.LOST && s.last != null,
        etaS = e?.etaS?.let { TMath.roundHalfUp(it) },
        etaMinS = e?.etaMinS?.let { TMath.roundHalfUp(it) },
        etaMaxS = e?.etaMaxS?.let { TMath.roundHalfUp(it) },
        speedKmh = s.ground?.let { it * 3.6 },
        progress = progress,
        alarmMarkerProgress = marker,
        predictedAlarmAtMs = predicted,
        samplingPolicy = s.policy,
        fallbackAtMs = s.fallback.targetAtMs,
        fallbackStatus = s.fallback.status,
        batteryPct = s.battery.levelPct,
        batteryRisk = risk,
        preAlertFired = s.preAlertFired,
        alarmAtMs = s.alarm.atMs,
        alarmReason = s.alarm.lastReason,
        alarmRinging = s.alarm.ringing,
        snoozeCount = s.alarm.snoozeCount,
        snoozeUntilMs = s.alarm.snoozeUntilMs,
        overshootPastM = s.overshootPastM,
        outcome = s.ended?.outcome,
        vehicleGuess = vehicleGuess(s.movingTimeS, s.movingDistM, cfg.vehicleHint, p),
        travelledM = TMath.roundHalfUp(s.movingDistM),
        droppedFixes = s.droppedFixes,
        wakeAtMs = wakeAtMs,
    )
}
