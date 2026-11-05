package app.napstop.core.trip.harness

import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.chordProjection
import app.napstop.core.trip.distanceM
import app.napstop.core.trip.isGapFix

/**
 * U116 / U117 (T10.5 round 3, 3b): the GPS-gap chord seen from outside the engine. For a Step on a [LocationFix] that moved
 * `last`: whether it is a gap fix, the chord parameter u and distance, `dChord` (only for 0 < u < 1, as in `chordClosest`), and
 * whether the round-3c `notCloser` term of the overshoot rule holds on the state after the Step (before any alarm, minD <
 * nearRadius, dSmooth − minD ≥ overshootOpenM, stop in progress or last3[2] ≥ last3[0]). [dFixM]: raw distance of the new fix
 * to the destination (U116 a2, T11.3: `d_f − dChord ≥ overshootOpenM`).
 */
internal class GapProbe(
    val atMs: Long,
    val recovered: Boolean,
    val gapFix: Boolean,
    val u: Double?,
    val chordM: Double?,
    val dChord: Double?,
    val standingTerm: Boolean,
    val dFixM: Double,
    /** T10.7 (U116 a1/a1b): phase before the Step. */
    val phase: TripPhase,
) {
    companion object {
        fun of(s0: EngineState, input: LocationFix, s1: Step): GapProbe? {
            val l = s0.last ?: return null
            val f = s1.state.last ?: return null
            if (f == l || f.fixAtMs != input.fixAtMs) return null
            val recovered = s1.events.any { it is GpsRecovered }
            val gap = s0.rejects.isEmpty() && isGapFix(s0.phase, s0.overshootAtMs, s0.gps, l, f, s0.params, s0.policyIntervalAtLastFixS, s0.policy)
            val ch = chordProjection(l.lat, l.lng, f.lat, f.lng, s0.config)
            val dChord = if (gap && ch != null && ch.u > 0.0 && ch.u < 1.0) ch.distM else null
            val dFix = distanceM(f.lat, f.lng, s0.config.destLat, s0.config.destLng)
            return GapProbe(input.atMs, recovered, gap, ch?.u, ch?.distM, dChord, standingTerm(s0, s1), dFix, s0.phase)
        }

        /** Round-3c `notCloser` term of the overshoot rule, evaluated with the phase/alarm before the Step and minD/dSmooth after. */
        fun standingTerm(s0: EngineState, s1: Step): Boolean {
            val st = s1.state
            val p = st.params
            val minD = st.minD ?: return false
            val ds = st.dSmooth ?: return false
            val l3 = st.last3
            val notCloser = st.stopStartMs != null || (l3.size == 3 && l3[2] >= l3[0] && l3.min() - minD >= p.overshootOpenM)
            val nearRadius = maxOf(p.overshootNearMinM, if (st.config.mode == AlarmMode.DISTANCE) st.config.distanceThresholdM ?: 0 else 0)
            return s0.overshootAtMs == null && (s0.phase == TripPhase.ACQUIRING || s0.phase == TripPhase.TRACKING) &&
                s0.alarm.atMs == null && st.minDChord && notCloser && minD < nearRadius && ds - minD >= p.overshootOpenM
        }
    }
}
