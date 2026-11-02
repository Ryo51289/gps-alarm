package app.napstop.core.trip

// T10 §4.6 pre-alert.

internal fun inZone(e: Estimate, cfg: TripConfig, p: EngineParams): Boolean {
    val eta = e.etaS
    return when (cfg.mode) {
        AlarmMode.DISTANCE ->
            e.dNow <= TMath.max(p.preAlertDistanceFactor * thrM(cfg), p.preAlertMinDistanceM).toDouble()
        AlarmMode.TIME ->
            eta != null && eta <= p.preAlertLeadS.toDouble() && p.preAlertLeadS - thrS(cfg) >= p.preAlertMinGapS
        AlarmMode.SMART -> eta != null && eta <= p.preAlertLeadS.toDouble()
    }
}

/** Caller guarantees this Step has no Alarm. */
internal fun shouldPreAlert(w: StepWork, e: Estimate): Boolean =
    w.cfg.preAlertEnabled && w.preAlertArmed && !w.preAlertFired && w.phase == TripPhase.TRACKING && inZone(e, w.cfg, w.p)
