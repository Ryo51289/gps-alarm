package app.napstop.core.trip

// T10 §4.2 (FixFilter) and §4.3 (DistanceSmoother).

internal enum class DropReason { STALE, OUT_OF_ORDER, INVALID, INACCURATE, IMPLAUSIBLE }

internal sealed interface FixVerdict {
    data class Drop(val reason: DropReason) : FixVerdict

    data class Reanchor(val rec: FixRec) : FixVerdict

    data class Accept(val rec: FixRec) : FixVerdict
}

/** Jump test against the last accepted fix (§4.2). */
internal fun plausible(a: FixRec, b: FixRec, p: EngineParams): Boolean =
    (distanceM(a, b) - (a.accM + b.accM)) <= p.maxPlausibleSpeedMps * TMath.toS(b.fixAtMs - a.fixAtMs)

/** Speed normalisation of §2.2: negative or non-finite speed means "no speed". */
internal fun normalisedSpeed(speedMps: Double?): Double? =
    if (speedMps != null && speedMps.isFinite() && speedMps >= 0.0) speedMps else null

/**
 * Classifies a fix. Updates `w.rejects` as §4.2 requires (sliding window of consecutive IMPLAUSIBLE fixes,
 * cleared on ACCEPT); every other field is left to the caller.
 */
internal fun classifyFix(w: StepWork, f: LocationFix): FixVerdict {
    val p = w.p
    if (f.atMs - f.fixAtMs > p.fixMaxAgeS * 1000L) return FixVerdict.Drop(DropReason.STALE)
    val last = w.last
    if (last != null && f.fixAtMs <= last.fixAtMs) return FixVerdict.Drop(DropReason.OUT_OF_ORDER)
    val validAcc = f.accuracyM.isFinite() && f.accuracyM > 0.0
    val validPos = f.lat.isFinite() && f.lng.isFinite() && f.lat >= -90.0 && f.lat <= 90.0 && f.lng >= -180.0 && f.lng < 180.0
    if (!validAcc || !validPos) return FixVerdict.Drop(DropReason.INVALID)
    val d = distanceM(f.lat, f.lng, w.cfg.destLat, w.cfg.destLng)
    if (f.accuracyM > TMath.min(p.accHardMaxM, TMath.max(p.accAbsMaxM, p.accRelMax * d))) {
        return FixVerdict.Drop(DropReason.INACCURATE)
    }
    val rec = FixRec(f.fixAtMs, f.lat, f.lng, f.accuracyM, d, null)
    if (last != null && !plausible(last, rec, p)) {
        val r = (w.rejects + rec).takeLast(3)
        w.rejects = r
        val reanchor = r.size == 3 &&
            r[2].fixAtMs - r[0].fixAtMs >= p.outlierResetSpanS * 1000L &&
            plausible(r[0], r[1], p) && plausible(r[1], r[2], p)
        return if (reanchor) FixVerdict.Reanchor(rec) else FixVerdict.Drop(DropReason.IMPLAUSIBLE)
    }
    w.rejects = emptyList()
    return FixVerdict.Accept(rec)
}

/** §4.3: keep fixes within smoothWindowS of the new one, append it, keep the 3 newest. */
internal fun updateRecent(recent: List<FixRec>, f: FixRec, p: EngineParams): List<FixRec> {
    val minAt = f.fixAtMs - p.smoothWindowS * 1000L
    val kept = ArrayList<FixRec>(4)
    for (r in recent) if (r.fixAtMs >= minAt) kept.add(r)
    kept.add(f)
    return kept.takeLast(3)
}
