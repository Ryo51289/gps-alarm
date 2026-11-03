package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.BatteryState
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.Estimate
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.StepWork
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import app.napstop.core.trip.estimate
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.StepRecord
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.nextFallbackAt
import app.napstop.core.trip.planFallback
import app.napstop.core.trip.predictedAlarmAt
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.wakeAt
import app.napstop.core.trip.wakeBasisAt
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * T10.5 (T10 mục cuối "T10.5" §6): wakeBasisAt / wakeBatteryAt (U106 c–g), the urgent later shift of the fallback in the quiet
 * window (U108, U109) and the harness I4 wording + counter (U110). U106 a/b, U107 and U111 are in [TesterT121Test].
 */
class T105Test {
    private val p = EngineParams()
    private val n = S + 3_600_000L

    // ================================================================ U106 c–g

    /** TRACKING, GPS OK, last fix at [n], now = [n], policyIntervalAtLastFixS 600 (c2 = n + 1 800 000), no fallback. */
    private fun okState(): EngineState =
        trackingState(cfg(), now = n, lastFixAt = n, tier = SamplingTier.SPARSE, policyAtFix = 600, d = 200_000.0)

    @Test
    fun `U106 c d e f wakeAt takes c3 from min(wakeBasisAt, wakeBatteryAt), near-zone and c4 from wakeBasisAt only`() {
        val s = okState()
        assertEquals(1_800, lostAfterS(s.params, s.policyIntervalAtLastFixS, s.policy)) // c2 = n + 1 800 000
        // (c) sliding: basis = deadline far away; T10.4 with the sliding predicted n + 900 500 gave n + 1 500.
        assertEquals(n + 1_800_000, wakeAt(s, n + 20_000_000, null))
        // (d) not sliding, no battery: as T10.4.
        assertEquals(n + 1_500, wakeAt(s, n + 900_500, null))
        // (e) c4 from deadlineAt.
        assertEquals(n + 101_000, wakeAt(s, n + 1_000_000, null))
        // (f) c3 from the battery forecast; c4 / near-zone from wakeBasisAt (n + 2 101 000, n + 2 401 000), not from the battery.
        assertEquals(n + 951_000, wakeAt(s, n + 3_000_000, n + 950_000))
        assertEquals(n + 51_000, wakeAt(s, n + 950_000, null)) // T10.4 with predicted = battery n + 950 000
    }

    private fun work(s: EngineState): Pair<StepWork, Estimate?> {
        val w = StepWork(s)
        return w to estimate(w)
    }

    @Test
    fun `U106 g wakeBasisAt is deadlineAt when sliding or without estimate, predictedNoBattery otherwise, null when alarmed`() {
        val deadline = { s: EngineState -> s.startedAtMs + s.maxTripDurationS * 1000L }
        val battery = BatteryState.EMPTY.copy(levelPct = 40, armed = true)
        // (i) TRACKING, GPS OK, stop in progress: modeAt slides with now, so the basis is the deadline (the view keeps predicted).
        val i = trackingState(cfg(), now = n, lastFixAt = n - 20_000, d = 20_000.0, inStop = true, battery = battery)
        val (wi, ei) = work(i)
        val pi = predictedAlarmAt(wi, ei)
        assertEquals(deadline(i), wakeBasisAt(wi, ei))
        assertEquals(deadline(i), pi.wakeBasis)
        assertNotNull(pi.wakeBattery)
        assertTrue(pi.withBattery!! < deadline(i)) // the view's predictedAlarmAt is unchanged (not the deadline)
        // (ii) GPS OK, moving.
        val ii = i.copy(stopStartMs = null, stopAnchor = null)
        val (wii, eii) = work(ii)
        assertEquals(predictedAlarmAt(wii, eii).noBattery, wakeBasisAt(wii, eii))
        assertTrue(wakeBasisAt(wii, eii)!! < deadline(ii))
        // (iii) GPS LOST with stopStartMs != null: dead reckoning, fixed between inputs.
        val iii = trackingState(cfg(), now = n, lastFixAt = n - 70_000, d = 20_000.0, inStop = true, gps = GpsStatus.LOST)
        val (wiii, eiii) = work(iii)
        assertEquals(predictedAlarmAt(wiii, eiii).noBattery, wakeBasisAt(wiii, eiii))
        assertTrue(wakeBasisAt(wiii, eiii)!! < deadline(iii))
        // (iv) ACQUIRING without a fix: no estimate.
        val iv = TripEngine.start(cfg(), p, S).state
        val (wiv, eiv) = work(iv)
        assertNull(eiv)
        assertEquals(deadline(iv), wakeBasisAt(wiv, eiv))
        assertNull(predictedAlarmAt(wiv, eiv).wakeBattery)
        // (v) ALARMING.
        val v = i.copy(phase = TripPhase.ALARMING, alarm = AlarmState.EMPTY.copy(atMs = n - 1_000, lastRingAtMs = n - 1_000))
        val (wv, ev) = work(v)
        assertNull(wakeBasisAt(wv, ev))
        assertNull(predictedAlarmAt(wv, ev).wakeBattery)
    }

    // ================================================================ U108

    private fun fb(f: Long, status: FallbackStatus = FallbackStatus.CONFIRMED, emittedAt: Long = n - 5_000, near: Boolean = true) =
        FallbackState(f, emittedAt, status, if (status == FallbackStatus.CONFIRMED) emittedAt + 500 else null, false, near)

    @Test
    fun `U108 nextFallbackAt urgent later shift inside the quiet window (K1, K2 bounds, min shift, far zone, FAILED, emit)`() {
        // (a)
        assertEquals(n + 430_000, nextFallbackAt(fb(n + 29_000), n + 430_000, n + 400_000, n, p))
        // (b) K1: now >= predicted − Q blocks; one ms later it does not.
        assertNull(nextFallbackAt(fb(n + 29_000), n + 60_000, n + 30_000, n, p))
        assertEquals(n + 60_001, nextFallbackAt(fb(n + 29_000), n + 60_001, n + 30_001, n, p))
        // (c) K2: F − now >= fallbackMinLeadS.
        assertNull(nextFallbackAt(fb(n + 9_999), n + 430_000, n + 400_000, n, p))
        assertEquals(n + 430_000, nextFallbackAt(fb(n + 10_000), n + 430_000, n + 400_000, n, p))
        // (d) shift below fallbackMinShiftS (override 60 s).
        assertNull(nextFallbackAt(fb(n + 29_000), n + 61_000, n + 31_000, n, params("{\"fallbackMinShiftS\": 60}")))
        // (e) far zone, last emission 5 s ago: fallbackMinIntervalS is skipped.
        assertEquals(n + 1_512_500, nextFallbackAt(fb(n + 29_000), n + 1_512_500, n + 2_000_000, n, p))
        // (f) FAILED: the retry branch as before (60 s since the emission).
        assertEquals(n + 430_000, nextFallbackAt(fb(n + 29_000, FallbackStatus.FAILED, n - 60_000), n + 430_000, n + 400_000, n, p))
        assertNull(nextFallbackAt(fb(n + 29_000, FallbackStatus.FAILED, n - 59_999), n + 430_000, n + 400_000, n, p))
        // (g) emit, then a Step 5 s later with the same predicted: nothing.
        val w = StepWork(trackingState(cfg(), now = n, lastFixAt = n, fallback = fb(n + 29_000)))
        planFallback(w, null, n + 400_000)
        assertEquals(listOf<TripEvent>(FallbackAlarmChanged(n, n + 430_000, FallbackCause.ETA)), w.events.toList())
        assertEquals(FallbackState(n + 430_000, n, FallbackStatus.REQUESTED, null, false, true), w.fallback)
        assertNull(nextFallbackAt(w.fallback, n + 430_000, n + 400_000, n + 5_000, p))
        w.now = n + 5_000
        planFallback(w, null, n + 400_000)
        assertEquals(1, w.events.size)
    }

    // ================================================================ U109

    /**
     * Feeds fixes from [first] s: stationary (d 8 000, speed 0) every 5 s to 700 s, then moving at 12.5 m/s every 5 s. Before every
     * input, the OS fallback fires if view.fallbackAtMs has come (simple osSim). Returns the Step with the first Alarm.
     */
    private fun run109(e: EngineDriver, first: Int): Step {
        var t = first
        var guard = 0
        var s = e.fix(t, 8_000.0, spd = 0.8)
        while (s.events.none { it is Alarm }) {
            t += 5
            val f = s.view.fallbackAtMs
            if (f != null && f <= S + t * 1000L) {
                s = e.feed(FallbackFired(f, f))
                break
            }
            s = if (t <= 700) e.fix(t, 8_000.0, spd = 0.0) else e.fix(t, 8_000.0 - 12.5 * (t - 700), spd = 12.5)
            check(++guard < 1_000)
        }
        return s
    }

    private fun state109(): EngineState = trackingState(
        cfg(), d = 8_500.0, tier = SamplingTier.DENSE,
        fallback = FallbackState(S + 630_000, S, FallbackStatus.CONFIRMED, S + 500, false, true),
    )

    @Test
    fun `U109 a a fix in the quiet window showing a stop moves the fallback later and the engine rings first`() {
        val st = state109()
        val before = TripEngine.reduce(st, Tick(S)).view // I14: same state, the previous Step's view
        assertEquals(S + 600_000, before.predictedAlarmAtMs)
        val e = driverFrom(st)
        val s0 = e.fix(601, 8_000.0, spd = 0.8)
        assertTrue(s0.events.none { it is Alarm })
        assertNotNull(s0.state.stopStartMs, "inStop")
        assertEquals(S + 1_161_000, s0.view.predictedAlarmAtMs)
        val fac = s0.events.filterIsInstance<FallbackAlarmChanged>().single()
        assertEquals(FallbackAlarmChanged(S + 601_000, S + 1_191_000, FallbackCause.ETA), fac)
        assertEquals(true, Checks.quietEmission(before, s0.view, fac, st.params), "I4 (T10.5): urgent later shift")
        // Then: the engine rings DISTANCE first, the fallback never comes before it.
        val e2 = driverFrom(st)
        val last = run109(e2, 601)
        val a = last.events.filterIsInstance<Alarm>().single()
        assertTrue(a.reason == AlarmReason.DISTANCE && a.ringNow, "first alarm $a at ${(a.atMs - S) / 1000.0} s")
    }

    @Test
    fun `U109 b with only 9 s left the fallback stays and rings early (pinned remainder)`() {
        val e = driverFrom(state109())
        val s0 = e.fix(621, 8_000.0, spd = 0.8)
        assertTrue(s0.events.none { it is FallbackAlarmChanged })
        val last = run109(driverFrom(state109()), 621)
        val a = last.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.FALLBACK, a.reason)
        assertEquals(false, a.ringNow)
        assertEquals(S + 630_000, a.atMs)
    }

    @Test
    fun `U109 c a charging battery sample removing batteryAt inside the quiet window moves the fallback to the far zone`() {
        val st = trackingState(
            cfg(), d = 50_000.0, now = n, lastFixAt = n,
            battery = BatteryState.EMPTY.copy(levelPct = 6, armed = true, charging = false),
            fallback = FallbackState(n + 25_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, false),
        )
        val s = TripEngine.reduce(st, BatterySample(n, 6, true))
        assertTrue(s.events.none { it is Alarm })
        val fac = s.events.filterIsInstance<FallbackAlarmChanged>().single()
        assertEquals(FallbackCause.ETA, fac.cause)
        val at = fac.fallbackAtMs!!
        assertTrue(at >= n + 600_000, "at ${at - n}")
    }

    // ================================================================ U110

    private fun baseView(): TripView = TripEngine.reduce(trackingState(cfg(), now = n, lastFixAt = n), Tick(n)).view

    private fun run110(prevTarget: Long, predicted: Long, newTarget: Long): RunResult {
        val v = baseView()
        val prev = v.copy(atMs = n - 5_000, fallbackAtMs = prevTarget, fallbackStatus = FallbackStatus.CONFIRMED, wakeAtMs = n + 60_000)
        val cur = v.copy(
            atMs = n, fallbackAtMs = newTarget, fallbackStatus = FallbackStatus.REQUESTED, predictedAlarmAtMs = predicted,
            wakeAtMs = n + 60_000,
        )
        val recs = listOf(
            StepRecord(0, null, "[]", emptyList(), prev),
            StepRecord(5, Tick(n), "[]", listOf(FallbackAlarmChanged(n, newTarget, FallbackCause.ETA)), cur),
        )
        return RunResult(
            RunKey("u110", "c", "all", false, 0), n - 5_000, p, recs, arrayOfNulls(2), arrayOfNulls(2), null, emptyMap(), null, null,
            null, emptyList(), emptyMap(),
        )
    }

    @Test
    fun `U110 harness I4 accepts the urgent later shift and counts it, rejects the K2, K1 and min-shift cases`() {
        val a = run110(n + 29_000, n + 400_000, n + 430_000)
        assertEquals(emptyList<String>(), Checks.invariants(a, "a"))
        assertEquals(1, Checks.urgentShifts(a).size)
        val u = Checks.urgentShifts(a).single()
        assertEquals(listOf(n + 29_000, n + 430_000, n + 400_000), listOf(u.prevTarget, u.newTarget, u.predicted))
        val b = Checks.invariants(run110(n + 9_000, n + 400_000, n + 430_000), "b")
        assertTrue(b.size == 1 && b.single().startsWith("I4"), "$b")
        val c = Checks.invariants(run110(n + 29_000, n + 20_000, n + 430_000), "c")
        assertTrue(c.size == 1 && c.single().startsWith("I4"), "$c")
        // (d) T10.5 round 2 (review nit #5): a later shift below fallbackMinShiftS inside the quiet window is an I4 violation;
        // exactly fallbackMinShiftS is the exception.
        val d = Checks.invariants(run110(n + 29_000, n + 400_000, n + 58_000), "d")
        assertTrue(d.size == 1 && d.single().startsWith("I4"), "$d")
        assertEquals(emptyList<String>(), Checks.invariants(run110(n + 29_000, n + 400_000, n + 59_000), "d30"))
    }

    // ================================================================ U112 (T10.5 round 2)

    @Test
    fun `U112 a b far-zone later shift is immediate when the alarm already set is within Q + minInterval`() {
        fun f(at: Long) = fb(at, emittedAt = n - 1)
        // (a) emitted 1 ms ago: the once-a-minute limit is lifted when F − now <= 90 s (before round 2: null all three).
        assertEquals(n + 1_500_000, nextFallbackAt(f(n + 63_000), n + 1_500_000, n + 2_000_000, n, p))
        assertEquals(n + 1_500_000, nextFallbackAt(f(n + 90_000), n + 1_500_000, n + 2_000_000, n, p))
        assertNull(nextFallbackAt(f(n + 90_001), n + 1_500_000, n + 2_000_000, n, p))
        // (b) earlier shift, the old branch (spec row: target n + 40 000; |40 000 − 63 000| < fallbackMinShiftS, so null, see the
        // T12.2 round 2 notes; an earlier shift by >= 30 s is set at once).
        assertNull(nextFallbackAt(f(n + 63_000), n + 40_000, n + 2_000_000, n, p))
        assertEquals(n + 33_000, nextFallbackAt(f(n + 63_000), n + 33_000, n + 2_000_000, n, p))
    }

    private fun state112(): EngineState = trackingState(
        cfg(), d = 9_000.0, gps = GpsStatus.LOST, now = n, lastFixAt = n - 600_000, tier = SamplingTier.DENSE,
        fallback = FallbackState(n + 63_000, n - 1, FallbackStatus.CONFIRMED, n, false, true),
    )

    private fun check112(atS: Int) {
        val e = driverFrom(state112())
        val s = e.feed(LocationFix(n + atS * 1000L, n + atS * 1000L, pt9000.lat, pt9000.lng, 8.0, 0.0))
        assertTrue(s.events.any { it is GpsRecovered }, "GpsRecovered")
        assertTrue(s.events.none { it is Alarm })
        assertEquals(n + atS * 1000L + 640_000, s.view.predictedAlarmAtMs)
        val fac = s.events.filterIsInstance<FallbackAlarmChanged>().single()
        assertEquals(FallbackCause.ETA, fac.cause)
        val at = fac.fallbackAtMs!!
        assertTrue(at >= n + atS * 1000L + 600_000, "at ${at - n}")
    }

    private val pt9000 = TestGeo.pointOnMeridian(DEST, 9_000.0)

    @Test
    fun `U112 c d seed 746 pattern a fix after a GPS loss showing the vehicle far moves a near fallback 63 s or 33 s away`() {
        check112(0) // (c)
        check112(30) // (d)
    }
}
