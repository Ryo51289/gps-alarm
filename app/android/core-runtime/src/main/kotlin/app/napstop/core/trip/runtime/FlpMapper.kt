package app.napstop.core.trip.runtime

import app.napstop.core.trip.AccuracyLevel
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.SamplingPolicy

/** SamplingPolicy of the engine → Fused Location request (spec T15 §5.4, ARCHITECTURE §5). Pure. */
object FlpMapper {
    fun spec(policy: SamplingPolicy, params: EngineParams): FlpRequestSpec =
        FlpRequestSpec(
            priority = if (policy.accuracy == AccuracyLevel.HIGH) FlpPriority.HIGH_ACCURACY else FlpPriority.BALANCED_POWER_ACCURACY,
            intervalMs = policy.intervalS * 1000L,
            minUpdateIntervalMs = policy.minIntervalS * 1000L,
            // No batching (S1 §4.3); also the Builder default [G-LRB].
            maxUpdateDelayMs = 0L,
            // The first historical fix is never older than what the engine would drop anyway.
            maxUpdateAgeMs = minOf(policy.intervalS, params.fixMaxAgeS) * 1000L,
        )
}
