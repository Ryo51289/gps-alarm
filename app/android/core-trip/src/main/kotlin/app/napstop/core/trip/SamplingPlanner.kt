package app.napstop.core.trip

// T10 §4.12 SamplingPlanner.

internal fun tierOf(t: Double?, cur: SamplingTier, p: EngineParams): SamplingTier {
    if (t == null) return cur
    val h = p.tierHysteresisFactor
    return when {
        t <= p.denseEnterS.toDouble() || (cur == SamplingTier.DENSE && t <= p.denseEnterS * h) -> SamplingTier.DENSE
        t <= p.mediumEnterS.toDouble() || (cur != SamplingTier.SPARSE && t <= p.mediumEnterS * h) -> SamplingTier.MEDIUM
        else -> SamplingTier.SPARSE
    }
}

/** Target tier, or null in ENDED (policy unchanged). */
internal fun targetTier(
    phase: TripPhase,
    t: Double?,
    cur: SamplingTier?,
    established: Boolean,
    gps: GpsStatus,
    p: EngineParams,
): SamplingTier? = when (phase) {
    TripPhase.ACQUIRING, TripPhase.ALARMING, TripPhase.SNOOZED, TripPhase.OVERSHOT -> SamplingTier.DENSE
    TripPhase.TRACKING -> {
        val c = cur ?: SamplingTier.DENSE
        var tier = tierOf(t, c, p)
        if (!established) tier = TMath.maxTier(tier, SamplingTier.MEDIUM)
        if (gps == GpsStatus.LOST) tier = TMath.maxTier(tier, c)
        tier
    }
    TripPhase.ENDED -> null
}

internal fun policyFor(tier: SamplingTier, p: EngineParams, maxSaving: Boolean): SamplingPolicy {
    val f = if (maxSaving) p.maxSavingIntervalFactor else 1
    return when (tier) {
        SamplingTier.SPARSE ->
            SamplingPolicy(tier, p.samplingSparseIntervalS * f, p.samplingSparseMinIntervalS * f, AccuracyLevel.BALANCED)
        SamplingTier.MEDIUM ->
            SamplingPolicy(tier, p.samplingMediumIntervalS * f, p.samplingMediumMinIntervalS * f, AccuracyLevel.HIGH)
        SamplingTier.DENSE -> SamplingPolicy(tier, p.samplingDenseIntervalS, p.samplingDenseMinIntervalS, AccuracyLevel.HIGH)
    }
}

/** Step 9 SamplingPlanner: emits SamplingPolicyChanged when the policy differs. */
internal fun planSampling(w: StepWork, e: Estimate?, predicted: Long?) {
    val t = predicted?.let { TMath.toS(it - w.now) }
    val tier = targetTier(w.phase, t, w.policy?.tier, e?.established ?: false, w.gps, w.p) ?: return
    val pol = policyFor(tier, w.p, w.battery.choice == UserActionKind.BATTERY_MAX_SAVING)
    if (pol != w.policy) {
        w.policy = pol
        w.events += SamplingPolicyChanged(w.now, pol)
    }
}
