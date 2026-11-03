package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSource
import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.K_METRES_PER_DEG_LAT
import app.napstop.core.trip.chordClosest
import app.napstop.core.trip.chordProjection
import app.napstop.core.trip.distanceM
import app.napstop.core.trip.harness.Suite
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.LatLng
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * T10.5 round 3 / 3b (T10 "T10.5 vòng 3", "T10.5 vòng 3b"): the destination passed inside a GPS gap. The chord between the fix
 * before the gap and the first fix after it lowers minD (no immediate alarm, 3b); the usual overshoot rule, or the 3b "standing"
 * term, rings. U113 `chordClosest`, U114 the engine on the tester's / reviewer's builders, U116 (a) and U117 on the fixtures.
 * U115 is in [TesterT122Test], U116 (b) in [TesterT121Test] (U111).
 */
class T105GapTest {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val n = S + 3_600_000L

    /** Point [south] m south (negative = north) and [east] m east of the destination. */
    private fun pt(south: Double, east: Double = 0.0): LatLng {
        val p0 = TestGeo.pointOnMeridian(DEST, south)
        return if (east == 0.0) p0 else TestGeo.jitter(p0, east, 0.0)
    }

    private fun rec(p: LatLng, at: Long = n): FixRec = FixRec(at, p.lat, p.lng, 8.0, distanceM(p.lat, p.lng, DEST.lat, DEST.lng), null)

    // ================================================================ U113

    @Test
    fun `U113 chordClosest distance from the destination to the GPS-gap chord, only inside the segment`() {
        val c = cfg()
        // (g), (h) round 4 (review nit #4): a vertical chord 1 500 m east ending at the foot of the perpendicular gives u == 1.0
        // exactly (ex = 0, ey = −ay) → excluded; ending 0.1 mm past it gives u just below 1 → included.
        val east = 1_500.0 / K_METRES_PER_DEG_LAT // cosDeg(0) == 1
        val lV = FixRec(n, -0.045, DEST.lng + east, 8.0, 1.0, null)
        val fFoot = FixRec(n, 0.0, DEST.lng + east, 8.0, 1.0, null)
        val fPast = FixRec(n, 1e-9, DEST.lng + east, 8.0, 1.0, null)
        val cases = listOf(
            "a" to (rec(pt(29_410.0)) to rec(pt(-3_100.0))),
            "b" to (rec(pt(5_000.0)) to rec(pt(1_000.0))),
            "c" to (rec(pt(3_000.0)) to rec(pt(3_000.0))),
            "d" to (rec(pt(5_000.0, 1_500.0)) to rec(pt(-5_000.0, 1_500.0))),
            "e" to (rec(pt(5_000.0, 200.0)) to rec(pt(-5_000.0))),
            "f" to (rec(pt(5_000.0)) to FixRec(n, 0.01, DEST.lng + 181.0, 8.0, 1.0, null)),
            "g" to (lV to fFoot),
            "h" to (lV to fPast),
        )
        val got = cases.associate { (k, lf) -> k to chordClosest(lf.first, lf.second, c) }
        val u = cases.associate { (k, lf) -> k to chordProjection(lf.first.lat, lf.first.lng, lf.second.lat, lf.second.lng, c)?.u }
        assertTrue(got.getValue("a")!! <= 1.0, "a ${got["a"]}")
        assertNull(got["b"], "b (u >= 1)")
        assertTrue(u.getValue("b")!! >= 1.0)
        assertNull(got["c"], "c (len2 = 0)")
        assertTrue(kotlin.math.abs(got.getValue("d")!! - 1_500.0) <= 1.0, "d ${got["d"]}")
        assertTrue(kotlin.math.abs(got.getValue("e")!! - 100.0) <= 1.0, "e ${got["e"]}")
        assertNull(got["f"], "f (|Δlng| > 180)")
        assertEquals(1.0, u.getValue("g"), "g u")
        assertNull(got["g"], "g (u == 1 excluded)")
        assertTrue(u.getValue("h")!! < 1.0 && u.getValue("h")!! > 0.999999, "h u ${u["h"]}")
        assertTrue(kotlin.math.abs(got.getValue("h")!! - 1_500.0) <= 1.0, "h ${got["h"]}")
        // Exact values for the Swift cross-check (T13): same arithmetic and order, no FMA; u and the distance in hex.
        fun hex(x: Double?) = x?.let { java.lang.Double.toHexString(it) + " " + it } ?: "null"
        File(outDir, "u113-chord.txt").writeText(
            cases.joinToString("\n") { (k, _) -> "$k u=${hex(u[k])} dChord=${hex(got[k])}" } + "\n",
        )
    }

    // ================================================================ U114 (T10.5 round 3b)

    /** The tester's repro builder (TesterT122Test `T122 b repro`): GPS lost since n − [gapS] s, DR still 11.8 km out at 10 m/s. */
    private fun reproState(config: TripConfig = cfg(AlarmMode.DISTANCE, thr = 1000), east: Double = 0.0, gapS: Int = 1_761): EngineState {
        val dr = 11_800.0 + 10.0 * gapS
        val st = trackingState(
            config, d = dr, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000, lastFixAt = n - gapS * 1000L,
            tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
            fallback = FallbackState(n + 29_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, true),
        )
        if (east == 0.0) return st
        val l = rec(pt(dr, east), n - gapS * 1000L)
        return st.copy(last = l, recent = listOf(l), dSmooth = l.d, minD = l.d, last3 = listOf(l.d), dStartM = l.d + 20_000.0)
    }

    private fun fix(st: EngineState, south: Double, east: Double = 0.0, at: Long = n, spd: Double? = 18.0): Step {
        val p = pt(south, east)
        return TripEngine.reduce(st, LocationFix(at, at, p.lat, p.lng, 8.0, spd))
    }

    /** One fix of a sequence: time, metres south (negative = north), metres east, Doppler speed. */
    private class Fx(val at: Long, val south: Double, val east: Double, val spd: Double?)

    /** Feeds [fixes] from [st] until the first Alarm (inclusive); returns every Step. */
    private fun drive(st: EngineState, fixes: List<Fx>): List<Step> {
        val out = ArrayList<Step>()
        var s = st
        for (f in fixes) {
            val step = fix(s, f.south, f.east, f.at, f.spd)
            out += step
            s = step.state
            if (step.events.any { it is Alarm }) break
        }
        return out
    }

    /** Fixes every 5 s from n, moving away north from [past] m beyond the destination at [v] m/s (0 = standing). */
    private fun away(past: Double, v: Double, count: Int = 40, east: Double = 0.0, firstSpd: Double? = v): List<Fx> =
        (0 until count).map { i -> Fx(n + 5_000L * i, -(past + v * 5.0 * i), east, if (i == 0) firstSpd else v) }

    private fun firstAlarm(steps: List<Step>): Pair<Long, Alarm>? =
        steps.firstNotNullOfOrNull { s -> s.events.filterIsInstance<Alarm>().firstOrNull()?.let { s.state.nowMs to it } }

    private fun note(tag: String, steps: List<Step>) {
        val a = firstAlarm(steps)
        val o = steps.flatMap { it.events }.filterIsInstance<Overshoot>().firstOrNull()
        LOG.append("$tag: first alarm ${a?.second?.reason} at n+${a?.let { (it.first - n) / 1000.0 }} s pastM=${o?.pastM} ")
            .append("minD after first fix=${steps.first().state.minD}\n")
        File(outDir, "u114-gap.txt").writeText(LOG.toString())
    }

    private fun assertAlarm(steps: List<Step>, reason: AlarmReason, atMs: Long, tag: String) {
        note(tag, steps)
        val (t, a) = firstAlarm(steps) ?: error("$tag: no alarm")
        assertEquals(reason, a.reason, tag)
        assertTrue(a.ringNow, tag)
        assertEquals(atMs, t, "$tag: alarm at n+${(t - n) / 1000.0} s")
    }

    @Test
    fun `U114 a a2 a3 b passed the destination in a GPS gap, OVERSHOOT once moving away is confirmed or the vehicle stands`() {
        // (a) 3 100 m beyond, moving away at 18 m/s: no alarm at the first fix (direction unknown), minD from the chord; round 3c:
        // OVERSHOOT at the 3rd fix (lag-2 `notCloser`; round 3b: 5th fix, 3 strictly increasing smoothed distances).
        val a = drive(reproState(), away(3_100.0, 18.0))
        assertTrue(a.first().events.none { it is Alarm }, "a first fix ${a.first().events}")
        assertTrue(a.first().events.any { it is GpsRecovered })
        assertTrue(a.first().state.minD!! <= 1.0, "a minD ${a.first().state.minD}")
        assertNull(a.first().state.stopStartMs)
        assertAlarm(a, AlarmReason.OVERSHOOT, n + 10_000, "a")
        val oa = a.last().events.filterIsInstance<Overshoot>().single()
        assertEquals(3_190, oa.pastM, "a pastM")
        assertEquals(TripPhase.OVERSHOT, a.last().state.phase)
        // (a2) standing after the gap: first fix UNKNOWN (Δt 1 761 s > maxSpeedSampleGapS 900), the stationary one after it stands.
        assertAlarm(drive(reproState(), away(3_100.0, 0.0, firstSpd = 0.0)), AlarmReason.OVERSHOOT, n + 5_000, "a2")
        // (a3) as (a2) with a 600 s gap: the first fix (Doppler 0) is STATIONARY already.
        assertAlarm(drive(reproState(gapS = 600), away(3_100.0, 0.0, firstSpd = 0.0)), AlarmReason.OVERSHOOT, n, "a3")
        // (b) 2 000 m beyond, moving away.
        assertAlarm(drive(reproState(), away(2_000.0, 18.0)), AlarmReason.OVERSHOOT, n + 10_000, "b")
    }

    @Test
    fun `U114 c d e 300 m beyond rings DISTANCE, TIME and SMART their mode reason, off-route PASSED_CLOSEST once moving away`() {
        assertAlarm(drive(reproState(), away(300.0, 18.0)), AlarmReason.DISTANCE, n, "c")
        assertAlarm(drive(reproState(cfg(AlarmMode.TIME, thrMin = 15)), away(3_100.0, 18.0)), AlarmReason.TIME, n, "d TIME 15")
        assertAlarm(drive(reproState(cfg(AlarmMode.SMART)), away(3_100.0, 18.0)), AlarmReason.SMART_TIME, n, "d SMART")
        // (e) the route passes 1 500 m east of the destination.
        val e = drive(reproState(east = 1_500.0), away(4_000.0, 18.0, east = 1_500.0))
        assertTrue(kotlin.math.abs(e.first().state.minD!! - 1_500.0) <= 1.0, "e minD ${e.first().state.minD}")
        assertAlarm(e, AlarmReason.PASSED_CLOSEST, n + 20_000, "e")
        assertTrue(e.flatMap { it.events }.none { it is Overshoot }, "e")
    }

    @Test
    fun `U114 f g h no gap, already alarmed, not yet passed`() {
        // (f) not a gap (GPS OK, previous fix 30 s ago at 600 m): the usual rule, no interpolation through 0.
        val f0 = trackingState(cfg(AlarmMode.DISTANCE, thr = 1000), d = 600.0, ground = 18.0, closing = 18.0, now = n - 30_000, lastFixAt = n - 30_000)
        val f = fix(f0, -300.0)
        assertTrue(f.state.minD!! >= 299.0, "f minD ${f.state.minD}")
        assertEquals(AlarmReason.DISTANCE, f.events.filterIsInstance<Alarm>().single().reason, "f")
        // (g) already alarmed (GPS_LOST while lost): no new Alarm, minD not lowered by the chord.
        val g0 = reproState().copy(
            phase = TripPhase.ALARMING,
            alarm = AlarmState.EMPTY.copy(atMs = n - 60_000, reason = AlarmReason.GPS_LOST, source = AlarmSource.ENGINE, lastRingAtMs = n - 60_000, ringing = true),
            fallback = FallbackState.CLEARED,
        )
        val g = fix(g0, -3_100.0)
        assertTrue(g.events.none { it is Alarm }, "g ${g.events}")
        assertTrue(g.state.minD!! >= 3_000.0, "g minD ${g.state.minD}")
        // (h) not yet passed: 5 000 m on the same side (seed 26 pattern): no alarm, the urgent later shift as U109.
        val h = fix(reproState(), 5_000.0, spd = 0.8)
        assertTrue(h.events.none { it is Alarm }, "h ${h.events}")
        val fac = h.events.filterIsInstance<FallbackAlarmChanged>().single()
        assertEquals(FallbackCause.ETA, fac.cause)
        assertTrue(fac.fallbackAtMs!! > n + 29_000, "h fallback ${fac.fallbackAtMs}")
    }

    /**
     * U114 (i): the reviewer's RK20 case (RvRk20Test, first row): fix before the gap 20 km south, 700 s gap, first fix 2 km north and
     * 0.5 km east (the chord passes 0.4 km from the destination), then the vehicle keeps APPROACHING at 10 m/s. Round 3 rang
     * OVERSHOOT (pastM 1 607) at the first fix; round 3b: no OVERSHOOT, DISTANCE when dSmooth <= 1 000.
     */
    @Test
    fun `U114 i bypass entering from the far side is not an overshoot, DISTANCE rings at 1 km`() {
        val lp = pt(20_000.0)
        val ld = distanceM(lp.lat, lp.lng, DEST.lat, DEST.lng)
        val base = trackingState(
            cfg(AlarmMode.DISTANCE, thr = 1000), d = ld, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000,
            lastFixAt = n - 700_000, tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
            fallback = FallbackState(n + 400_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, false),
        )
        val l = FixRec(n - 700_000, lp.lat, lp.lng, 8.0, ld, null)
        val st = base.copy(last = l, recent = listOf(l), dSmooth = ld, minD = ld, last3 = listOf(ld), dStartM = ld + 20_000.0)
        val d0 = kotlin.math.sqrt(2_000.0 * 2_000.0 + 500.0 * 500.0)
        val fixes = (0 until 200).map { i ->
            val r = maxOf(0.0, 1.0 - 10.0 * 5.0 * i / d0)
            Fx(n + 5_000L * i, -2_000.0 * r, 500.0 * r, if (i == 0) 30.0 else 10.0)
        }
        val steps = drive(st, fixes)
        note("i", steps)
        assertTrue(steps.flatMap { it.events }.none { it is Overshoot }, "i: no Overshoot")
        val (t, a) = firstAlarm(steps)!!
        assertEquals(AlarmReason.DISTANCE, a.reason, "i")
        val atAlarm = steps.last().state.dSmooth!!
        assertTrue(atAlarm <= 1_000.0 && atAlarm > 900.0, "i: DISTANCE at dSmooth $atAlarm (n+${(t - n) / 1000.0} s)")
    }

    /**
     * U114 (j) (RK20 b): passed in the gap, first fix 3 100 m beyond, then creeping away at 2 m/s (not > 10 km/h, not standing).
     * Round 3b: silent for 10 minutes until the vehicle stood. Round 3c: `notCloser` (dSmooth ≥ its value 2 fixes earlier) →
     * OVERSHOOT at the 3rd fix.
     */
    @Test
    fun `U114 j creeping away after the gap rings OVERSHOOT at the 3rd fix (round 3c)`() {
        val creep = (0 until 120).map { i -> Fx(n + 5_000L * i, -(3_100.0 + 2.0 * 5.0 * i), 0.0, 2.0) }
        val endS = 3_100.0 + 2.0 * 5.0 * 119
        val stand = (1..10).map { i -> Fx(n + 5_000L * (119 + i), -endS, 0.0, 0.0) }
        val steps = drive(reproState(), creep + stand)
        note("j", steps)
        val (t, a) = firstAlarm(steps)!!
        assertEquals(AlarmReason.OVERSHOOT, a.reason, "j")
        assertEquals(n + 10_000, t, "j: 3rd fix")
    }

    /**
     * U114 (k) (review round 3 #1, the time term of gapFix): GPS still OK — no Tick during the gap (c2 deferred by Doze), the fix
     * after the gap is the first Step; only `Δt ≥ lostAfterS` makes it a gap fix. Without it: the 2.7 h TIMEOUT path again.
     */
    @Test
    fun `U114 k gps still OK with no Tick during the gap, moving away rings OVERSHOOT (time term of gapFix)`() {
        val st = reproState().copy(gps = GpsStatus.OK, gpsLostAtMs = null, nowMs = n - 1_761_000)
        assertEquals(60, lostAfterS(st.params, st.policyIntervalAtLastFixS, st.policy))
        val steps = drive(st, away(3_100.0, 18.0))
        assertTrue(steps.first().events.none { it is GpsRecovered }, "k: no GpsRecovered (gps was OK)")
        assertTrue(steps.first().state.minD!! <= 1.0, "k minD ${steps.first().state.minD}")
        assertAlarm(steps, AlarmReason.OVERSHOOT, n + 10_000, "k")
    }

    /**
     * U114 (l) (review round 3 #1, the "gps LOST before step 2" term): LOST because location services were turned off, fixes
     * closer than lostAfterS (SPARSE 540 s, Δt 300 s, train 30 m/s).
     */
    @Test
    fun `U114 l gps LOST from location services off with fixes less than lostAfterS apart still lowers minD by the chord`() {
        val config = cfg(AlarmMode.DISTANCE, thr = 1000)
        val st = trackingState(
            config, d = 7_000.0, ground = 5.0, closing = 5.0, now = n - 300_000, lastFixAt = n - 300_000, tier = SamplingTier.SPARSE,
            maxTripS = 14_400, startedAt = n - 3_000_000,
        )
        assertEquals(540, lostAfterS(st.params, st.policyIntervalAtLastFixS, st.policy))
        val off = TripEngine.reduce(st, LocationAvailability(n - 290_000, AvailabilityCause.SERVICES_OFF))
        assertEquals(GpsStatus.LOST, off.state.gps)
        assertTrue(off.events.none { it is Alarm }, "l: no GPS_LOST alarm yet (DR etaS > 1 200) ${off.events}")
        val steps = drive(off.state, away(2_000.0, 30.0))
        assertTrue(steps.first().events.any { it is GpsRecovered }, "l GpsRecovered")
        assertTrue(steps.first().state.minD!! <= 1.0, "l minD ${steps.first().state.minD}")
        assertAlarm(steps, AlarmReason.OVERSHOOT, n + 10_000, "l")
    }

    /**
     * U114 (m) (round 3b, step 2): a stop in progress at the fix before the gap ends at the chord fix (stopStartMs/stopAnchor
     * cleared before the speed sample), so the standing term cannot fire on a vehicle that is moving after a long gap (Δt > 900 s:
     * the first fix after the gap is UNKNOWN and would otherwise keep the old stop).
     */
    @Test
    fun `U114 m a stop from before the gap does not count as standing at the first fix after it`() {
        val l = reproState().last!!
        val st = reproState().copy(stopStartMs = l.fixAtMs - 60_000, stopAnchor = l)
        val steps = drive(st, away(3_100.0, 18.0))
        assertTrue(steps.first().events.none { it is Alarm }, "m first fix ${steps.first().events}")
        assertNull(steps.first().state.stopStartMs, "m stop cleared")
        assertAlarm(steps, AlarmReason.OVERSHOOT, n + 10_000, "m")
    }

    // ================================================================ U114 (n)–(v) (T10.5 round 3c)

    /** splitmix64, deterministic (U114 t). */
    private class Mix(seed: Long) {
        private var x = seed

        fun next(): Long {
            x += -0x61c8864680b583ebL
            var z = x
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }

        fun dbl(lo: Double, hi: Double): Double = lo + (hi - lo) * ((next() ushr 11).toDouble() / (1L shl 53).toDouble())
    }

    private class ParkResult(val atMs: Long?, val reason: AlarmReason?, val fixNo: Int, val minD: Double?)

    /**
     * The reviewer's RvParkTest runner: the tester's repro builder with a [gapS] gap, then a fix every 5 s from n at
     * [pos](k) = (metres south, metres east) with accuracy [acc] and Doppler [spd]; the OS fallback fires when due. Until the
     * first Alarm or [maxS].
     */
    private fun park(gapS: Int, acc: Double, spd: Double?, maxS: Int = 4 * 3600, config: TripConfig = cfg(AlarmMode.DISTANCE, thr = 1000), pos: (Int) -> Pair<Double, Double>): ParkResult {
        var st = reproState(config, gapS = gapS)
        var s: Step? = null
        var k = 0
        var t = 0
        while (t < maxS) {
            val at = n + t * 1000L
            val f = s?.view?.fallbackAtMs
            if (s != null && f != null && f <= at) {
                s = TripEngine.reduce(st, FallbackFired(f, f))
            } else {
                val (south, east) = pos(k)
                val p = pt(south, east)
                s = TripEngine.reduce(st, LocationFix(at, at, p.lat, p.lng, acc, spd))
                k++
                t += 5
            }
            st = s.state
            s.events.filterIsInstance<Alarm>().firstOrNull()?.let { return ParkResult(it.atMs, it.reason, k, st.minD) }
            if (st.phase == TripPhase.ENDED) break
        }
        return ParkResult(null, null, k, st.minD)
    }

    private fun assertPark(r: ParkResult, fixNo: Int, tag: String) {
        LOG.append("$tag: first alarm ${r.reason} at n+${r.atMs?.let { (it - n) / 1000.0 }} s (fix #${r.fixNo}) minD=${r.minD}\n")
        File(outDir, "u114-gap.txt").writeText(LOG.toString())
        assertEquals(AlarmReason.OVERSHOOT, r.reason, tag)
        assertEquals(fixNo, r.fixNo, "$tag fix number")
        assertEquals(n + 5_000L * (fixNo - 1), r.atMs, tag)
    }

    /**
     * U114 (n): the "not yet alarmed" gate. ALARMING, the alarm already stopped ringing (AlarmSilenced), minD 300, the vehicle
     * stands 1 400 m beyond: no re-ring from the `notCloser` term (re-ring only by the usual rule, PO #18); the trip ends MISSED
     * after alarmMaxActiveS as before.
     */
    @Test
    fun `U114 n after an alarm stopped ringing a parked vehicle does not re-ring by notCloser, the trip ends after alarmMaxActiveS`() {
        val p = pt(-1_400.0)
        val f0 = FixRec(n, p.lat, p.lng, 8.0, 1_400.0, null)
        var st = trackingState(cfg(AlarmMode.DISTANCE, thr = 1000), d = 1_400.0, now = n, lastFixAt = n, minD = 300.0).copy(
            last = f0, recent = listOf(f0), dSmooth = 1_400.0, last3 = listOf(1_400.0, 1_400.0), phase = TripPhase.ALARMING,
            alarm = AlarmState.EMPTY.copy(atMs = n - 60_000, reason = AlarmReason.DISTANCE, source = AlarmSource.ENGINE, lastRingAtMs = n - 60_000, ringing = false),
            fallback = FallbackState.CLEARED,
        )
        val events = ArrayList<app.napstop.core.trip.TripEvent>()
        for (i in 1..120) {
            val s = TripEngine.reduce(st, LocationFix(n + i * 5_000L, n + i * 5_000L, p.lat, p.lng, 8.0, 0.0))
            events += s.events
            st = s.state
        }
        assertTrue(events.none { it is Alarm || it is Overshoot }, "n: ${events.filter { it is Alarm || it is Overshoot }}")
        val end = TripEngine.reduce(st, app.napstop.core.trip.Tick(n - 60_000 + st.params.alarmMaxActiveS * 1000L))
        val te = end.events.filterIsInstance<app.napstop.core.trip.TripEnded>().single()
        assertEquals(app.napstop.core.trip.EndReason.ALARM_UNANSWERED, te.endReason)
    }

    /** The reviewer's RvStandTest runner (no GPS gap): passing an off-route destination slowly, then standing 1.6 km north. */
    private fun stand(config: TripConfig, east: Double, v: Double, stopNorth: Double = 1_600.0): Pair<Int, Step>? {
        val p0 = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, 3_000.0), east, 0.0)
        val d0 = distanceM(p0.lat, p0.lng, DEST.lat, DEST.lng)
        val l = FixRec(S, p0.lat, p0.lng, 8.0, d0, null)
        var st = trackingState(config, d = d0, ground = v, closing = v * 0.95, now = S, lastFixAt = S)
        st = st.copy(last = l, recent = listOf(l), dSmooth = d0, minD = d0, last3 = listOf(d0), dStartM = d0 + 5_000.0)
        var y = 3_000.0
        var t = 0
        while (t < 7_200) {
            t += 5
            val moving = y > -stopNorth
            if (moving) y -= v * 5
            val p = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, y), east, 0.0)
            val s = TripEngine.reduce(st, LocationFix(S + t * 1000L, S + t * 1000L, p.lat, p.lng, 8.0, if (moving) v else 0.0))
            st = s.state
            if (s.events.any { it is Alarm }) return t to s
        }
        return null
    }

    @Test
    fun `U114 o p p2 a slow pass of an off-route destination without a GPS gap is the T12_1 rule (known bug, waiting for T10_6)`() {
        // Round 3e: normal tracking (no GPS-gap chord, minDChord false) is the T12.1 rule; the round-3c/3d net for a slow pass
        // (o 1 810 s, p 2 325 s) is gone. Silent for 2 h (TIMEOUT later): lỗi đã biết, chờ T10.6 (PO 03/11).
        // (o) TIME 5, 2.5 m/s, destination 600 m off the route (RvStandTest).
        assertNull(stand(cfg(AlarmMode.TIME, thrMin = 5), 600.0, 2.5), "o: lỗi đã biết, chờ T10.6 (PO 03/11)")
        // (p) DISTANCE 500, 2 m/s, destination 800 m off the route, standing 2 km north (1 354 m past the nearest point).
        assertNull(stand(cfg(AlarmMode.DISTANCE, thr = 500), 800.0, 2.0, stopNorth = 2_000.0), "p: lỗi đã biết, chờ T10.6 (PO 03/11)")
        // (p2) the RvStandTest geometry (standing 1.6 km north, 989 m past the nearest point 800 m off the route).
        assertNull(stand(cfg(AlarmMode.DISTANCE, thr = 500), 800.0, 2.0), "p2: lỗi đã biết, chờ T10.6 (PO 03/11)")
    }

    @Test
    fun `U114 q r s u parked after the gap with poor fixes, repeated or alternating coordinates, or crawling away rings OVERSHOOT at the 3rd fix`() {
        // (q) RvParkTest P9: acc 80, no Doppler, repeated coordinates (table: 1 761 s gap; P9 itself: 600 s).
        assertPark(park(1_761, 80.0, null) { -3_100.0 to 0.0 }, 3, "q gap 1761")
        assertPark(park(600, 80.0, null) { -3_100.0 to 0.0 }, 3, "q gap 600 (P9)")
        // (r) RvParkTest P11: acc 60, Doppler 0, gap 1 761.
        assertPark(park(1_761, 60.0, 0.0) { -3_100.0 to 0.0 }, 3, "r (P11)")
        // (s) coordinates alternating between two positions 30 m apart (a non-strict chain would never hold).
        assertPark(park(1_761, 80.0, null) { k -> (if (k % 2 == 0) -3_100.0 else -3_130.0) to 0.0 }, 3, "s")
        // (u) crawling away at 2 m/s, acc 8, Doppler 2 (RK20 b).
        assertPark(park(1_761, 8.0, 2.0) { k -> -(3_100.0 + 2.0 * 5.0 * k) to 0.0 }, 3, "u")
    }

    @Test
    fun `U114 t parked after the gap with random jitter of 20 m, 200 deterministic sets ring OVERSHOOT within 120 s`() {
        val lat = ArrayList<Double>()
        val bad = ArrayList<String>()
        for (seed in 1L..200L) {
            val r = Mix(seed * 1_000_003L)
            val res = park(1_761, 80.0, null, maxS = 3_600) { -(3_100.0 + r.dbl(-20.0, 20.0)) to r.dbl(-20.0, 20.0) }
            val after = res.atMs?.let { (it - n) / 1000.0 }
            if (res.reason != AlarmReason.OVERSHOOT || after == null || after > 120.0) bad += "seed $seed: ${res.reason} at $after s"
            after?.let { lat += it }
        }
        lat.sort()
        val dist = if (lat.isEmpty()) "-" else "n ${lat.size}, p50 ${lat[lat.size / 2]} s, p90 ${lat[(lat.size * 9) / 10]} s, max ${lat.last()} s"
        val hist = lat.groupingBy { it }.eachCount().toSortedMap()
        File(outDir, "u114-t-jitter.txt").writeText("$dist\nafter first fix (s → sets): $hist\nover 120 s: $bad\n")
        assertTrue(bad.isEmpty()) { "U114 t: ${bad.take(10)}" }
    }

    /**
     * U114 (x) (T10.5 round 3d, review round 5 #1, the reviewer's RvOutlierTest first row): normal tracking, DISTANCE 500, 2 m/s
     * straight to the destination, a fix every 30 s; the 2nd fix is an outlier at 800 m (acc 10, accepted: sparse fixes) while the
     * vehicle is at 1 940 m, so minD = 800. Round 3c rang a wrong-wording OVERSHOOT at 120 s; round 3d: DISTANCE at 780 s.
     */
    @Test
    fun `U114 x one outlier fix lowering minD during a normal approach does not ring OVERSHOOT (round 3d)`() {
        val start = 2_060.0
        val p0 = TestGeo.pointOnMeridian(DEST, start)
        val l = FixRec(S, p0.lat, p0.lng, 8.0, start, null)
        var st = trackingState(cfg(AlarmMode.DISTANCE, thr = 500), d = start, ground = 2.0, closing = 2.0, now = S, lastFixAt = S)
        st = st.copy(last = l, recent = listOf(l), dSmooth = start, minD = start, last3 = listOf(start), dStartM = start + 5_000.0)
        var y = start
        var t = 0
        var k = 0
        var first: Pair<Int, Step>? = null
        val events = ArrayList<app.napstop.core.trip.TripEvent>()
        while (y > 0 && t < 7_200 && first == null) {
            t += 30
            k++
            y -= 2.0 * 30
            val rep = if (k == 2) 800.0 else y
            val p = TestGeo.pointOnMeridian(DEST, rep)
            val s = TripEngine.reduce(st, LocationFix(S + t * 1000L, S + t * 1000L, p.lat, p.lng, if (k == 2) 10.0 else 8.0, if (k == 2) null else 2.0))
            st = s.state
            events += s.events
            if (k == 2) assertTrue(kotlin.math.abs(st.minD!! - 800.0) <= 1.0, "x: the outlier was accepted (minD ${st.minD})")
            if (s.events.any { it is Alarm }) first = t to s
        }
        val (ta, sa) = first!!
        LOG.append("x: first alarm ${sa.events.filterIsInstance<Alarm>().single().reason} at t=$ta s\n")
        File(outDir, "u114-gap.txt").writeText(LOG.toString())
        assertTrue(events.none { it is Overshoot }, "x: no Overshoot")
        assertEquals(AlarmReason.DISTANCE, sa.events.filterIsInstance<Alarm>().single().reason, "x")
        assertEquals(780, ta, "x: DISTANCE at 780 s")
    }

    /** U114 (w) (round 3c table row "turns back"): passed in the gap, then drives back to the destination: no OVERSHOOT, DISTANCE at 1 km. */
    @Test
    fun `U114 w passed in the gap then turning back towards the destination rings DISTANCE at 1 km, no overshoot`() {
        val fixes = (0 until 100).map { i -> Fx(n + 5_000L * i, -maxOf(0.0, 3_100.0 - 18.0 * 5.0 * i), 0.0, 18.0) }
        val steps = drive(reproState(), fixes)
        note("w", steps)
        assertTrue(steps.flatMap { it.events }.none { it is Overshoot }, "w: no Overshoot")
        val (_, a) = firstAlarm(steps)!!
        assertEquals(AlarmReason.DISTANCE, a.reason, "w")
        assertTrue(steps.last().state.dSmooth!! <= 1_000.0, "w dSmooth ${steps.last().state.dSmooth}")
    }

    /**
     * U114 (v) (RK20 a, pinned accepted risk): the reviewer's bypass case of (i), but after the first fix the vehicle stands for
     * 2 minutes before driving on to the destination: OVERSHOOT with the wrong wording (it is still approaching).
     */
    @Test
    fun `U114 v bypass entering from the far side then standing rings a wrong-wording OVERSHOOT (RK20 a, accepted)`() {
        val lp = pt(20_000.0)
        val ld = distanceM(lp.lat, lp.lng, DEST.lat, DEST.lng)
        val base = trackingState(
            cfg(AlarmMode.DISTANCE, thr = 1000), d = ld, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000,
            lastFixAt = n - 700_000, tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
            fallback = FallbackState(n + 400_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, false),
        )
        val l = FixRec(n - 700_000, lp.lat, lp.lng, 8.0, ld, null)
        val st = base.copy(last = l, recent = listOf(l), dSmooth = ld, minD = ld, last3 = listOf(ld), dStartM = ld + 20_000.0)
        val d0 = kotlin.math.sqrt(2_000.0 * 2_000.0 + 500.0 * 500.0)
        val standFixes = (0 until 24).map { i -> Fx(n + 5_000L * i, -2_000.0, 500.0, if (i == 0) 30.0 else 0.0) }
        val drive = (0 until 100).map { i ->
            val r = maxOf(0.0, 1.0 - 10.0 * 5.0 * (i + 1) / d0)
            Fx(n + 120_000L + 5_000L * i, -2_000.0 * r, 500.0 * r, 10.0)
        }
        val steps = drive(st, standFixes + drive)
        note("v", steps)
        val (t, a) = firstAlarm(steps)!!
        assertEquals(AlarmReason.OVERSHOOT, a.reason, "v: accepted wrong-wording OVERSHOOT")
        assertTrue(t == n + 5_000 || t == n + 10_000, "v: at n+${(t - n) / 1000.0} s (fix 2–3)")
    }

    // ================================================================ U114 (y), (z), (aa) (T10.5 round 3e, minDChord)

    /**
     * Normal tracking (no GPS gap), the tester's O1 shape: approach at 12 m/s from 20 km, at [jamD] m before the destination the
     * vehicle stops (or crawls [crawl] m/s) for 20 min, then drives on at 12 m/s; fixes every 30 s, noise ±8 m, Ticks at wakeAtMs
     * in between; 300 s into the jam one outlier fix [delta] m closer (acc 15). Until the first Alarm. Returns (Step, truth d).
     */
    private var jamRejected = 0
    private val jamMinDs = ArrayList<Double>()

    private fun jam(config: TripConfig, jamD: Double, crawl: Double, delta: Double, outliers: Int = 1): Pair<Step, Double> {
        jamRejected = 0
        jamMinDs.clear()
        val r = Mix(jamD.toLong() * 31 + delta.toLong())
        val tJam = S + ((20_000.0 - jamD) / 12.0 * 1000).toLong()
        fun yAt(t: Long): Double = when {
            t <= tJam -> -20_000.0 + 12.0 * (t - S) / 1000.0
            t <= tJam + 1_200_000L -> -jamD + crawl * (t - tJam) / 1000.0
            else -> -jamD + crawl * 1_200.0 + 12.0 * (t - tJam - 1_200_000L) / 1000.0
        }
        fun vAt(t: Long): Double = if (t <= tJam) 12.0 else if (t <= tJam + 1_200_000L) crawl else 12.0
        var step = TripEngine.start(config, EngineParams(), S)
        var nextFix = S + 1_000L
        var outLeft = outliers
        var guard = 0
        while (step.events.none { it is Alarm } && ++guard < 100_000) {
            assertTrue(!step.state.minDChord, "minDChord must stay false without a GPS gap (t=${(step.state.nowMs - S) / 1000.0})")
            val wake = step.view.wakeAtMs
            step = if (wake != null && wake < nextFix) {
                TripEngine.reduce(step.state, app.napstop.core.trip.Tick(wake))
            } else {
                val t = nextFix
                nextFix = t + 30_000L
                val y = yAt(t)
                val outlier = outLeft > 0 && t >= tJam + 300_000L
                if (outlier) outLeft--
                val south = if (outlier) -(y + delta) else -(y + r.dbl(-8.0, 8.0))
                val p = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, south), r.dbl(-8.0, 8.0), 0.0)
                val s1 = TripEngine.reduce(step.state, LocationFix(t, t, p.lat, p.lng, if (outlier) 15.0 else 10.0, vAt(t)))
                if (s1.state.droppedFixes > step.state.droppedFixes) jamRejected++
                s1.state.minD?.let { jamMinDs += it }
                s1
            }
        }
        assertTrue(!step.state.minDChord)
        return step to kotlin.math.abs(yAt(step.state.nowMs))
    }

    @Test
    fun `U114 y z normal tracking, stuck before the destination with one outlier fix, is the T12_1 rule (no OVERSHOOT)`() {
        // (y) the tester's O1 repro (R2-1): DISTANCE 500, stopped at 1 900 m, outlier at 800 m.
        val (sy, dy) = jam(cfg(AlarmMode.DISTANCE, thr = 500), 1_900.0, 0.0, 1_100.0)
        val ay = sy.events.filterIsInstance<Alarm>().single()
        LOG.append("y: first alarm ${ay.reason} at truth d=${dy.toInt()} m\n")
        assertEquals(AlarmReason.DISTANCE, ay.reason, "y")
        assertTrue(dy in 400.0..500.0, "y: DISTANCE at d=$dy (T12.1: 480 m)")
        // (z) TIME 5, crawling 0.3 m/s (lag-2 true after 3 fixes).
        val (sz, dz) = jam(cfg(AlarmMode.TIME, thrMin = 5), 1_900.0, 0.3, 1_100.0)
        val az = sz.events.filterIsInstance<Alarm>().single()
        LOG.append("z: first alarm ${az.reason} at truth d=${dz.toInt()} m\n")
        File(outDir, "u114-gap.txt").writeText(LOG.toString())
        assertTrue(az.reason != AlarmReason.OVERSHOOT && sz.events.none { it is Overshoot }, "z: ${az.reason}")
    }

    @Test
    fun `U114 aa the chord flag survives parking jitter and is cleared by an observed fix closer than the chord`() {
        // (i) chord minD ≈ 0, then parked 3.1 km beyond with ±50 m jitter, Doppler 0: the flag stays, OVERSHOOT as U114 a2.
        val r = Mix(114_027L)
        val fixes = (0 until 40).map { i -> Fx(n + 5_000L * i, -(3_100.0 + r.dbl(-50.0, 50.0)), r.dbl(-50.0, 50.0), 0.0) }
        val i1 = drive(reproState(), fixes)
        assertTrue(i1.all { it.state.minDChord }, "aa (i): flag kept")
        val (t1, a1) = firstAlarm(i1)!!
        LOG.append("aa (i): ${a1.reason} at n+${(t1 - n) / 1000.0} s\n")
        assertEquals(AlarmReason.OVERSHOOT, a1.reason)
        assertTrue(t1 <= n + 10_000, "aa (i) at n+${(t1 - n) / 1000.0} s")
        // (ii) chord 400 m east of the destination (dChord ≈ 400), the vehicle turns back and drives straight to the destination:
        // the first observed dSmooth < dChord clears the flag; no OVERSHOOT. DISTANCE 200 so the vehicle gets below dChord first.
        val l = rec(pt(29_410.0, 400.0), n - 1_761_000)
        val st = reproState(cfg(AlarmMode.DISTANCE, thr = 200))
            .copy(last = l, recent = listOf(l), dSmooth = l.d, minD = l.d, last3 = listOf(l.d), dStartM = l.d + 20_000.0)
        val back = (0 until 200).map { i ->
            val rr = maxOf(0.0, 1.0 - 15.0 * 5.0 * i / kotlin.math.sqrt(3_100.0 * 3_100.0 + 400.0 * 400.0))
            Fx(n + 5_000L * i, -3_100.0 * rr, 400.0 * rr, 15.0)
        }
        val ii = drive(st, back)
        assertTrue(kotlin.math.abs(ii.first().state.minD!! - 400.0) <= 2.0 && ii.first().state.minDChord, "aa (ii) chord ${ii.first().state.minD}")
        val cleared = ii.indexOfFirst { !it.state.minDChord }
        assertTrue(cleared > 0 && ii[cleared].state.dSmooth!! < ii.first().state.minD!! + 1e-9, "aa (ii) cleared at $cleared")
        assertTrue(ii.flatMap { it.events }.none { it is Overshoot }, "aa (ii) no Overshoot")
        val (t2, a2) = firstAlarm(ii)!!
        LOG.append("aa (ii): flag cleared at fix ${cleared + 1}, first alarm ${a2.reason} at n+${(t2 - n) / 1000.0} s\n")
        File(outDir, "u114-gap.txt").writeText(LOG.toString())
        assertEquals(AlarmReason.DISTANCE, a2.reason)
        assertTrue(ii.last().state.dSmooth!! <= 200.0)
    }

    /**
     * U114 (ab) (T10.5 vòng 3f, the coder's O1 repro from round 7): D500, fixes every 30 s, the vehicle stopped at 1 200 m, two
     * outlier fixes 2 km closer (800 m beyond the destination): outlier 1 rejected (IMPLAUSIBLE), outlier 2 accepted with Δt = 60 s
     * = lostAfterS, the next true fix rejected, the one after accepted. With `rejects` non-empty neither accepted fix is a chord
     * fix: minDChord stays false, no OVERSHOOT, DISTANCE as on HEAD (T12.1).
     */
    @Test
    fun `U114 ab an outlier accepted after a rejected one is not a GPS-gap chord fix (round 3f)`() {
        val (s, d) = jam(cfg(AlarmMode.DISTANCE, thr = 500), 1_200.0, 0.0, 2_000.0, outliers = 2)
        val a = s.events.filterIsInstance<Alarm>().single()
        LOG.append("ab: first alarm ${a.reason} at truth d=${d.toInt()} m, rejected fixes $jamRejected, minD after the outliers ${jamMinDs.firstOrNull { it < 1_100.0 }?.toInt()}\n")
        File(outDir, "u114-gap.txt").writeText(LOG.toString())
        assertTrue(jamRejected >= 2, "ab: outlier 1 and the next true fix rejected ($jamRejected)")
        val firstLow = jamMinDs.first { it < 1_100.0 }
        assertTrue(kotlin.math.abs(firstLow - 800.0) <= 20.0, "ab: outlier 2 accepted, minD $firstLow (not a chord ≈ 0)")
        assertEquals(AlarmReason.DISTANCE, a.reason, "ab")
        assertTrue(d in 400.0..500.0, "ab: DISTANCE at d=$d (HEAD: 488 m)")
    }

    /**
     * U114 (ac) (round 3f): the tunnel builder of U114 (a) with one STALE fix (age 90 s) and one INACCURATE fix (acc 1 500 m) arriving
     * inside the gap: both are DROPped but not IMPLAUSIBLE, `rejects` stays empty, so the first fix after the gap is still a chord fix.
     */
    @Test
    fun `U114 ac STALE and INACCURATE fixes inside the gap keep the chord fix`() {
        var st = reproState()
        val p1 = pt(20_000.0)
        val stale = TripEngine.reduce(st, LocationFix(n - 600_000, n - 690_000, p1.lat, p1.lng, 8.0, 10.0))
        assertEquals(st.droppedFixes + 1, stale.state.droppedFixes, "ac: STALE dropped")
        st = stale.state
        val inacc = TripEngine.reduce(st, LocationFix(n - 300_000, n - 300_000, p1.lat, p1.lng, 1_500.0, 10.0))
        assertEquals(st.droppedFixes + 1, inacc.state.droppedFixes, "ac: INACCURATE dropped")
        st = inacc.state
        assertTrue(st.rejects.isEmpty())
        val steps = drive(st, away(3_100.0, 18.0))
        assertTrue(steps.first().state.minDChord && steps.first().state.minD!! <= 1.0, "ac: chord fix (minD ${steps.first().state.minD})")
        assertAlarm(steps, AlarmReason.OVERSHOOT, n + 10_000, "ac")
    }

    /**
     * U114 (ad) (round 3f, RK20 d, pinned): as U114 (a) but one jump fix rejected as IMPLAUSIBLE inside the gap: the first fix after
     * the gap is not a chord fix (T12.1 rule: minD 3 100 m, nothing to ring while moving away), silent for the hour driven here.
     */
    @Test
    fun `U114 ad one IMPLAUSIBLE fix inside the gap makes the first fix after it a plain fix (T12_1 rule, pinned)`() {
        val p1 = pt(500_000.0)
        val jump = TripEngine.reduce(reproState(), LocationFix(n - 1_000_000, n - 1_000_000, p1.lat, p1.lng, 8.0, 10.0))
        assertEquals(1, jump.state.rejects.size, "ad: IMPLAUSIBLE kept in rejects")
        val steps = drive(jump.state, away(3_100.0, 18.0, count = 720))
        note("ad", steps)
        assertTrue(steps.all { !it.state.minDChord }, "ad: no chord fix")
        assertTrue(kotlin.math.abs(steps.first().state.minD!! - 3_100.0) <= 1.0, "ad: minD ${steps.first().state.minD}")
        assertNull(firstAlarm(steps), "ad: pinned silent for 1 h (RK20 d)")
    }

    // ================================================================ U116 a, U117

    private fun probes() = Suite.outcomes.values.flatMap { o -> o.gapProbes.map { o to it } }

    @Test
    fun `U116 a the GPS-gap chord never goes through a fixture destination (u outside 0 to 1 at every GpsRecovered Step)`() {
        val probes = probes()
        val traces = probes.map { it.first.key.traceId }.toSortedSet()
        val lines = probes.joinToString("\n") { (o, g) ->
            "${o.key.run} t=${(g.atMs - o.startMs) / 1000.0} recovered=${g.recovered} gapFix=${g.gapFix} u=${g.u} chord=${g.chordM} " +
                "dChord=${g.dChord} standingTerm=${g.standingTerm}"
        }
        File(outDir, "u116-gap.txt").writeText("traces=$traces probes=${probes.size}\n$lines\n")
        assertTrue(probes.any { it.second.recovered }, "no GpsRecovered Step on the fixtures?")
        assertTrue(traces.size >= 5, "traces with probes: $traces")
        val hit = probes.filter { it.second.dChord != null }
        assertTrue(hit.isEmpty()) { "chord through the destination on fixtures: ${hit.take(10).map { it.first.key.run }}" }
    }

    @Test
    fun `U117 the standing term of the overshoot rule never holds on a fixture run without an earlier GPS-gap chord`() {
        val bad = ArrayList<String>()
        var standing = 0
        for (o in Suite.outcomes.values) {
            var chordSeen = false
            for (g in o.gapProbes.sortedBy { it.atMs }) {
                if (g.dChord != null) chordSeen = true
                if (g.standingTerm) {
                    standing++
                    if (!chordSeen) bad += "${o.key.run} t=${(g.atMs - o.startMs) / 1000.0}"
                }
            }
        }
        File(outDir, "u117-standing.txt").writeText("standingTerm=$standing withoutChord=${bad.size}\n${bad.joinToString("\n")}\n")
        assertTrue(bad.isEmpty()) { "standing term without a chord: ${bad.take(10)}" }
    }

    private companion object {
        /** u114-gap.txt (all U114 sequences, any test order). */
        val LOG = StringBuffer()
    }
}
