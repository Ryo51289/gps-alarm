package app.napstop.core.trip

// T10 §4.9 battery (+ C8 for the screen-7 choice).

internal fun onBattery(w: StepWork, b: BatterySample) {
    var s = w.battery.copy(levelPct = b.levelPct, charging = b.charging)
    s = if (b.charging) {
        s.copy(segT0 = null, segL0 = null)
    } else if (s.segT0 == null) {
        s.copy(segT0 = b.atMs, segL0 = b.levelPct)
    } else {
        s
    }
    if (!b.charging && b.levelPct > alarmPctEff(s, w.p)) s = s.copy(armed = true)
    w.battery = s
}

internal fun alarmPctEff(b: BatteryState, p: EngineParams): Int =
    if (b.choice == UserActionKind.BATTERY_ALARM_EARLIER) b.choicePct ?: p.lowBatteryEarlierPct else p.lowBatteryAlarmPct

/** Screen 7 choice (C8: the latest choice is the one in force). */
internal fun onBatteryChoice(w: StepWork, action: UserActionKind) {
    val p = w.p
    var s = w.battery.copy(choice = action)
    if (action == UserActionKind.BATTERY_ALARM_EARLIER) {
        val level = s.levelPct
        val pct = if (level == null) {
            p.lowBatteryEarlierPct
        } else {
            TMath.max(p.lowBatteryAlarmPct, TMath.min(p.lowBatteryEarlierPct, level - 1))
        }
        s = s.copy(choicePct = pct)
    }
    w.battery = s
}

internal fun observedRate(b: BatteryState, now: Long, p: EngineParams): Double? {
    val t0 = b.segT0 ?: return null
    val l0 = b.segL0 ?: return null
    val level = b.levelPct ?: return null
    if (now - t0 < p.batteryMinRateWindowS * 1000L || l0 - level < 1) return null
    return (l0 - level).toDouble() / ((now - t0) / 3600000.0)
}

internal fun rate(b: BatteryState, now: Long, p: EngineParams): Double =
    TMath.max(p.batteryMinRatePctPerH, observedRate(b, now, p) ?: p.batteryPriorDrainPctPerH)

/** batteryAt of §4.5, or null. */
internal fun batteryAt(w: StepWork): Long? {
    val b = w.battery
    val level = b.levelPct ?: return null
    if (b.charging || !b.armed) return null
    val r = rate(b, w.now, w.p)
    if (!(r > 0.0)) return null
    return w.now + TMath.floorMs(TMath.max(0, level - alarmPctEff(b, w.p)).toDouble() / r * 3600.0)
}

internal fun lowBatteryCond(w: StepWork): Boolean {
    val b = w.battery
    val level = b.levelPct ?: return false
    return (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null &&
        !b.charging && b.armed && level <= alarmPctEff(b, w.p)
}

/** Risk (step 9) and the LowBatteryRisk event (rising edge, once per trip, not after a screen-7 choice). */
internal fun evaluateBatteryRisk(w: StepWork, predictedNoBattery: Long?): Boolean {
    val b = w.battery
    val level = b.levelPct
    if (b.charging || level == null || predictedNoBattery == null) return false
    val p = w.p
    val availableS = (level - alarmPctEff(b, p)).toDouble() / rate(b, w.now, p) * 3600.0
    val neededS = TMath.max(0.0, TMath.toS(predictedNoBattery - w.now)) + p.batteryReserveAfterAlarmS.toDouble()
    val risk = availableS < neededS
    if (risk && !b.riskEmitted && b.choice == null) {
        w.events += LowBatteryRisk(
            w.now,
            level,
            TMath.roundHalfUp(TMath.max(0.0, availableS) / 60.0),
            TMath.roundHalfUp(neededS / 60.0),
        )
        w.battery = b.copy(riskEmitted = true)
    }
    return risk
}
