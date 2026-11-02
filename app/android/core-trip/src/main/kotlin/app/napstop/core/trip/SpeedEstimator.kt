package app.napstop.core.trip

// T10 §4.4: speed sample, stop with hysteresis, EMA, lost-GPS speed guard (T10.1).

internal enum class Motion { STATIONARY, MOVING, UNKNOWN }

internal class SpeedSample(val raw: Motion, val groundSample: Double?, val closingSample: Double?, val dt: Double)

/** Speed sample of [f] against [last] (`f.fixAtMs > last.fixAtMs`). [speedMps] is already normalised. */
internal fun speedSample(last: FixRec, f: FixRec, speedMps: Double?, p: EngineParams): SpeedSample {
    val dt = TMath.toS(f.fixAtMs - last.fixAtMs)
    if (dt > p.maxSpeedSampleGapS.toDouble()) return SpeedSample(Motion.UNKNOWN, null, null, dt)
    val disp = distanceM(f, last)
    val goodPair = f.accM <= p.speedSampleMaxAccM && last.accM <= p.speedSampleMaxAccM
    val coarseOk = (f.accM + last.accM) <= 0.2 * disp
    val raw: Motion
    val gs: Double?
    if (speedMps != null && f.accM <= p.speedSampleMaxAccM) {
        gs = speedMps
        raw = if (gs < p.stationarySpeedMps) Motion.STATIONARY else Motion.MOVING
    } else if (goodPair && disp <= p.motionAccFactor * (f.accM + last.accM)) {
        gs = null
        raw = Motion.STATIONARY
    } else if (goodPair || coarseOk) {
        gs = disp / dt
        raw = if (gs < p.stationarySpeedMps) Motion.STATIONARY else Motion.MOVING
    } else {
        gs = null
        raw = Motion.UNKNOWN
    }
    val cs = if (goodPair || coarseOk) (last.d - f.d) / dt else null
    return SpeedSample(raw, gs, cs, dt)
}

/** `closingV` for EMA values g (ground) and c (closing): the k / closingV expressions of §4.4. */
internal fun closingVOf(g: Double, c: Double?, p: EngineParams): Double {
    val k = if (c == null) {
        p.routeFactorPrior
    } else if (c > 0.0) {
        TMath.clamp(g / c, p.routeFactorMin, p.routeFactorMax)
    } else {
        p.routeFactorMax
    }
    return g / k
}

internal fun isEstablished(movingTimeS: Double, movingSamples: Int, p: EngineParams): Boolean =
    movingTimeS >= p.speedEstablishedMovingS.toDouble() && movingSamples >= p.speedEstablishedSamples

/** Applies the motion state machine for an ACCEPTed fix [f] (with its groundSample) after [last]. */
internal fun applyMotion(w: StepWork, f: FixRec, last: FixRec, s: SpeedSample) {
    val p = w.p
    when (s.raw) {
        Motion.STATIONARY -> {
            if (w.stopStartMs == null) {
                w.stopStartMs = f.fixAtMs
                w.stopAnchor = f
            }
        }
        Motion.MOVING -> {
            val gs = s.groundSample ?: return
            val stopStart = w.stopStartMs
            val anchor = w.stopAnchor
            if (stopStart != null && anchor != null) {
                if (distanceM(f, anchor) <= TMath.max(p.stopExitMinM.toDouble(), f.accM + anchor.accM)) return
            }
            // T10.1 speed guard: closingV in force right before any blend of this fix.
            val g0 = w.ground
            if (p.lostSpeedGuardUpdates > 0 && g0 != null && isEstablished(w.movingTimeS, w.movingSamples, p)) {
                w.cvGuard = (w.cvGuard + closingVOf(g0, w.closing, p)).takeLast(p.lostSpeedGuardUpdates)
            }
            if (stopStart != null) {
                val stopS = TMath.toS(last.fixAtMs - stopStart)
                if (stopS <= p.shortStopIncludeS.toDouble()) {
                    val g = w.ground
                    if (g != null) w.ground = TMath.blend(g, 0.0, stopS, p.speedEmaTauS)
                    val c = w.closing
                    if (c != null) w.closing = TMath.blend(c, 0.0, stopS, p.speedEmaTauS)
                }
                w.stopStartMs = null
                w.stopAnchor = null
            }
            w.ground = TMath.blend(w.ground, gs, s.dt, p.speedEmaTauS)
            val cs = s.closingSample
            if (cs != null) w.closing = TMath.blend(w.closing, cs, s.dt, p.speedEmaTauS)
            w.movingTimeS += s.dt
            w.movingSamples += 1
            w.movingDistM += gs * s.dt
        }
        Motion.UNKNOWN -> Unit
    }
}
