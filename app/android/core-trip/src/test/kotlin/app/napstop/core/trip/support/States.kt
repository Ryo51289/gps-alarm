package app.napstop.core.trip.support

import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.BatteryState
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.Estimate
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.StepWork
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.estimate
import app.napstop.core.trip.initialState
import app.napstop.core.trip.policyFor

/**
 * Precondition builder for unit tests whose T10 row gives a state rather than an input sequence (T12 §8.1):
 * a TRACKING state with one fix at distance [d] taken at [lastFixAt]; EMA [ground]/[closing]; "established" uses
 * movingTimeS = 600, movingSamples = 10.
 */
internal fun trackingState(
    config: TripConfig = cfg(),
    p: EngineParams = EngineParams(),
    now: Long = S,
    startedAt: Long = S,
    d: Double = 50_000.0,
    ground: Double? = 15.0,
    closing: Double? = 12.5,
    established: Boolean = true,
    gps: GpsStatus = GpsStatus.OK,
    lastFixAt: Long = now,
    acc: Double = 8.0,
    inStop: Boolean = false,
    slow: Boolean = false,
    cvGuard: List<Double> = emptyList(),
    tier: SamplingTier = SamplingTier.DENSE,
    policyAtFix: Int? = null,
    phase: TripPhase = TripPhase.TRACKING,
    maxTripS: Int = p.maxTripCapS,
    dStart: Double = d + 20_000.0,
    minD: Double = d,
    battery: BatteryState = BatteryState.EMPTY,
    alarm: AlarmState = AlarmState.EMPTY,
    fallback: FallbackState = FallbackState.CLEARED,
    preAlertArmed: Boolean = true,
): EngineState {
    val pt = TestGeo.pointOnMeridian(DEST, d)
    val fix = FixRec(lastFixAt, pt.lat, pt.lng, acc, d, null)
    val pol = policyFor(tier, p, false)
    return initialState(config, p, startedAt).copy(
        nowMs = now, phase = phase, gps = gps, last = fix, recent = listOf(fix), dSmooth = d, dStartM = dStart, minD = minD,
        last3 = listOf(d), ground = ground, closing = closing, movingTimeS = if (established) 600.0 else 0.0,
        movingSamples = if (established) 10 else 0, movingDistM = if (established) 6000.0 else 0.0,
        stopStartMs = if (inStop) lastFixAt else null, stopAnchor = if (inStop) fix else null, slow = slow, cvGuard = cvGuard,
        policy = pol, policyIntervalAtLastFixS = policyAtFix ?: pol.intervalS, maxTripDurationS = maxTripS,
        battery = battery, alarm = alarm, fallback = fallback, preAlertArmed = preAlertArmed,
        gpsLostAtMs = if (gps == GpsStatus.LOST) lastFixAt else null,
    )
}

internal fun work(s: EngineState): StepWork = StepWork(s)

internal fun estimateOf(s: EngineState): Estimate = estimate(StepWork(s))!!

/** Synthetic estimate for rule-level tests. */
internal fun est(
    dNow: Double,
    cvDr: Double,
    etaS: Double?,
    k: Double = 1.2,
    established: Boolean = true,
    closingV: Double = cvDr,
    errM: Double = 8.0,
): Estimate = Estimate(
    established = established, v = closingV * k, k = k, closingV = closingV, guardV = null, lift = false, vDr = cvDr * k, cvDr = cvDr,
    elapsedS = 0.0, dNow = dNow, etaS = etaS, errM = errM, etaMinS = etaS, etaMaxS = etaS,
)

/** Driver continuing from an arbitrary state. */
internal fun driverFrom(s: EngineState): EngineDriver {
    val d = EngineDriver(s.config, s.params, s.startedAtMs)
    d.steps.clear()
    d.state = s
    return d
}

internal fun policy(tier: SamplingTier, p: EngineParams = EngineParams(), maxSaving: Boolean = false): SamplingPolicy = policyFor(tier, p, maxSaving)

internal fun roundTrip(s: EngineState): EngineState = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s))
