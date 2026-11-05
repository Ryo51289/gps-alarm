package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.SnapshotFormatException
import app.napstop.core.trip.Step
import app.napstop.core.trip.TMath
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.distanceM
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.lostLongAtS
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * T10.6 (T10 mục cuối "T10.6" §7): "long loss" rule W (U119, U120), speed before `established` while LOST (U122), slow-vehicle
 * passed-closest net `passAnchorD` (U123 c–i; U123 a, b in T105GapTest), snapshot key (U124).
 */
class T106Test {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val log = StringBuilder()

    private fun hex(x: Double?): String = x?.let { java.lang.Double.toHexString(it) } ?: "null"

    private fun i13(s: Step, tag: String) {
        val w = s.view.wakeAtMs
        if (s.view.phase == TripPhase.ENDED) {
            assertNull(w, "$tag: I13 ENDED")
        } else {
            assertNotNull(w, "$tag: I13 wakeAtMs null in ${s.view.phase}")
            assertTrue(w!! > s.state.nowMs, "$tag: I13 wakeAtMs not after now")
        }
    }

    // ================================================================ U119: lostLongAtS (pure)

    /** TRAIN (default), EMA ground/closing, gps LOST, the last fix at S, now = S + 60 s. */
    private fun lostState(
        d: Double,
        p: EngineParams = EngineParams(),
        hint: VehicleKind = VehicleKind.TRAIN,
        ground: Double? = 15.0,
        closing: Double? = 12.5,
        gps: GpsStatus = GpsStatus.LOST,
    ): EngineState = trackingState(cfg(hint = hint), p = p, d = d, ground = ground, closing = closing, gps = gps, now = S + 60_000L, lastFixAt = S)

    private fun lla(s: EngineState): Double? {
        val e = estimateOf(s)
        val pure = lostLongAtS(work(s), e)
        assertEquals(e.lostLongAtS?.let { java.lang.Double.doubleToRawLongBits(it) }, pure?.let { java.lang.Double.doubleToRawLongBits(it) })
        return pure
    }

    @Test
    fun `U119 lostLongAtS the long-loss mark W of C25`() {
        val out = StringBuilder()
        // (a) T122 c builder, L = 3 600 / 7 200 / 10 800.
        for ((l, want) in listOf(3_600 to 2_784.8, 7_200 to 5_435.7, 10_800 to 8_086.6)) {
            val x = lla(lostState(12.5 * (1_180.0 + l)))!!
            assertEquals(want, x, 0.1, "a L=$l")
            out.append("a L=$l: $x ${hex(x)}\n")
        }
        // (b) hint BUS: cvH = cvDr, thS 7 200, earlyS 1 650.
        val b = lla(lostState(12.5 * 8_380.0, hint = VehicleKind.BUS))!!
        assertEquals(5_550.0, b, 1e-9, "b")
        // (c) dSmooth 15 000: the floor gpsLostLongS.
        val c = lla(lostState(15_000.0))!!
        assertEquals(1_800.0, c, "c")
        // (d) gpsLostLongS 0: off.
        assertNull(lla(lostState(12.5 * 8_380.0, p = params("{\"gpsLostLongS\": 0}"))), "d")
        // (e) no hint floor, L = 7 200.
        val e = lla(lostState(12.5 * 8_380.0, p = params("{\"gpsLostLongHintFactor\": 0}")))!!
        assertEquals(5_550.0, e, 1e-9, "e")
        // (f) ground 0, cvGuard empty (cvDr 0), dSmooth 50 000: the TRAIN floor alone.
        val fs = lostState(50_000.0, ground = 0.0, closing = 0.0)
        assertEquals(0.0, estimateOf(fs).cvDr)
        val f = lla(fs)!!
        assertEquals(2_210.45, f, 0.01, "f")
        // (g) as (f) without the floor: cvH 0 → null.
        assertNull(lla(lostState(50_000.0, p = params("{\"gpsLostLongHintFactor\": 0}"), ground = 0.0, closing = 0.0)), "g")
        // (h) gps OK → null.
        assertNull(lla(lostState(12.5 * 8_380.0, gps = GpsStatus.OK)), "h")
        out.append("b: ${hex(b)}\nc: ${hex(c)}\ne: ${hex(e)}\nf: $f ${hex(f)}\n")
        File(outDir, "u119-lostlong.txt").writeText(out.toString())
    }

    // ================================================================ U120: W through reduce

    private class DozeOut(val steps: List<Step>, val alarm: Step)

    /** Only Tick(view.wakeAtMs) until a Step with an Alarm; I13 at every Step. */
    private fun doze(e: EngineDriver, tag: String, until: Long = Long.MAX_VALUE, max: Int = 2_000): DozeOut? {
        val out = ArrayList<Step>()
        if (e.steps.isEmpty()) out += e.tick(0)
        while (true) {
            i13(e.last, tag)
            val w = e.view.wakeAtMs!!
            if (w >= until) return null
            val s = e.tickMs(w)
            out += s
            if (s.events.any { it is Alarm }) {
                i13(s, tag)
                return DozeOut(out, s)
            }
            check(out.size < max) { "$tag: no alarm after $max wake-ups" }
        }
    }

    private fun t122c(lossS: Int, p: EngineParams = EngineParams()): EngineDriver =
        driverFrom(trackingState(cfg(AlarmMode.DISTANCE, thr = 1000), p = p, d = 12.5 * (1_180.0 + lossS), tier = SamplingTier.DENSE)).also { it.tick(0) }

    private fun firstAlarm(steps: List<Step>): Alarm = steps.flatMap { it.events }.filterIsInstance<Alarm>().first()

    @Test
    fun `U120 a c f the long-loss rule rings GPS_LOST at lostLongAt + 1 s from a wake-up Tick, constant prediction, off is T12_2`() {
        // (a) T122 c, L = 7 200, Doze loop, no fix.
        val a = t122c(7_200)
        val ra = doze(a, "U120 a")!!
        val lostStep = ra.steps.first { st -> st.events.any { it is GpsLost } }
        // The designer's table says S + 60 s; the first Tick(S) moves the policy to SPARSE, so lostAfterS = 540 s (T10.4 GAP-2).
        // lostLongAt counts from the last fix, so the alarm time does not depend on it.
        assertEquals(S + 540_000L, lostStep.state.nowMs, "a: GpsLost (T10.4 GAP-2: SPARSE after the first Tick)")
        val lla = estimateOf(lostStep.state).lostLongAtS!!
        assertEquals(5_435.72, lla, 0.01)
        val p = S + TMath.floorMs(lla)
        for (st in ra.steps.dropWhile { it !== lostStep }) {
            if (st.events.none { it is Alarm }) assertEquals(p, st.view.predictedAlarmAtMs, "a: predicted at ${st.state.nowMs - S}")
        }
        val alarm = ra.alarm.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.GPS_LOST, alarm.reason)
        assertTrue(alarm.ringNow)
        assertEquals(p + 1_000L, alarm.atMs, "a: Tick c3 = predicted + 1 s (T10.5: S + 7 201 000)")
        // (c) gpsLostLongS 0: the T12.2 sequence (alarm S + 7 201 000, predicted S + 7 200 000 from GpsLost).
        val c = t122c(7_200, params("{\"gpsLostLongS\": 0}"))
        val rc = doze(c, "U120 c")!!
        val lostC = rc.steps.first { st -> st.events.any { it is GpsLost } }
        assertEquals(S + 7_200_000L, lostC.view.predictedAlarmAtMs)
        assertEquals(S + 7_201_000L, firstAlarm(rc.steps).atMs)
        assertEquals(AlarmReason.GPS_LOST, firstAlarm(rc.steps).reason)
        // (f) as (a), the loss comes from LocationAvailability(PERMISSION_REVOKED) at S + 1 s.
        val f = t122c(7_200)
        val lf = f.avail(1, AvailabilityCause.PERMISSION_REVOKED)
        assertEquals(GpsLostCause.PERMISSION_REVOKED, lf.events.filterIsInstance<GpsLost>().single().cause)
        assertEquals(p, lf.view.predictedAlarmAtMs)
        val rf = doze(f, "U120 f")!!
        assertEquals(p + 1_000L, firstAlarm(rf.steps).atMs)
        assertEquals(AlarmReason.GPS_LOST, firstAlarm(rf.steps).reason)
        log.append("U120 a: lostLongAtS $lla alarm ${(alarm.atMs - S) / 1000.0} s; c: 7201 s; f: ${(firstAlarm(rf.steps).atMs - S) / 1000.0} s\n")
    }

    @Test
    fun `U120 b a fix in the middle of the loss recomputes lostLongAt from the new fix`() {
        val e = t122c(7_200)
        assertNull(doze(e, "U120 b before", until = S + 1_799_000L))
        val dr = 12.5 * (1_180.0 + 7_200) - 12.5 * 1_799
        val fx = e.fix(1_799, dr, spd = 15.0)
        assertEquals(GpsStatus.OK, fx.view.gps)
        i13(fx, "U120 b fix")
        val r = doze(e, "U120 b after")!!
        val lost = r.steps.first { st -> st.events.any { it is GpsLost } }
        val lla = estimateOf(lost.state).lostLongAtS!!
        val p = lost.state.last!!.fixAtMs + TMath.floorMs(lla)
        assertEquals(S + 1_799_000L, lost.state.last!!.fixAtMs)
        assertEquals(p, lost.view.predictedAlarmAtMs, "b: lostLongAt from the new fix")
        val a = firstAlarm(r.steps)
        assertEquals(AlarmReason.GPS_LOST, a.reason)
        assertEquals(p + 1_000L, a.atMs)
        assertEquals(U120_B_ALARM_MS, a.atMs - S, "b: first alarm (pinned)")
    }

    @Test
    fun `U120 d e the A10 builder rings before the pre-alert zone, a zero-speed state rings by the hint floor`() {
        // (d) lostDoze of U107 (a) with the defaults: first set of every mode.
        val modes = listOf(
            Triple("TIME 5", cfg(AlarmMode.TIME, thrMin = 5), false),
            Triple("TIME 15", cfg(AlarmMode.TIME, thrMin = 15), false),
            Triple("TIME 20", cfg(AlarmMode.TIME, thrMin = 20), false),
            Triple("SMART", cfg(AlarmMode.SMART), false),
            Triple("SMART slow", cfg(AlarmMode.SMART), true),
        )
        for ((name, config, slow) in modes) {
            val (g, c) = if (slow) 3.0 to 2.5 else 15.0 to 12.5
            val st = trackingState(config, d = (5_000.0 - 20.0) * c, ground = g, closing = c, slow = slow)
            val e = driverFrom(st)
            val lost = e.tickMs(S + lostAfterS(st.params, st.policyIntervalAtLastFixS, st.policy) * 1000L)
            assertTrue(lost.events.any { it is GpsLost }, name)
            val lla = estimateOf(lost.state).lostLongAtS!!
            val r = doze(e, "U120 d $name")!!
            assertTrue(e.steps.none { s -> s.events.any { it is PreAlert } }, "$name: PreAlert (I5)")
            val a = firstAlarm(r.steps)
            assertEquals(AlarmReason.GPS_LOST, a.reason, name)
            assertEquals(S + TMath.floorMs(lla) + 1_000L, a.atMs, name)
            log.append("U120 d $name: lostLongAtS $lla\n")
        }
        // (e) ground 0, cvGuard empty, dSmooth 50 000, TRAIN: T10.5 rang only TIMEOUT.
        val e = driverFrom(trackingState(d = 50_000.0, ground = 0.0, closing = 0.0))
        val r = doze(e, "U120 e")!!
        val lla = estimateOf(r.steps.first { st -> st.events.any { it is GpsLost } }.state).lostLongAtS!!
        assertEquals(2_210.45, lla, 0.01)
        val a = firstAlarm(r.steps)
        assertEquals(AlarmReason.GPS_LOST, a.reason)
        assertEquals(S + TMath.floorMs(lla) + 1_000L, a.atMs, "e")
    }

    @Test
    fun `U120 g a snapshot round trip and restore PENDING in the middle of the loss gives the uninterrupted event sequence`() {
        fun eventsOf(steps: List<Step>): List<TripEvent> = steps.flatMap { it.events }
        // Reference: the same wake-ups plus a plain Tick at S + 3 000 s (restore PENDING is Tick(now) after the restore branch).
        val a = t122c(7_200)
        assertNull(doze(a, "U120 g ref before", until = S + 3_000_000L))
        a.tick(3_000)
        val ra = doze(a, "U120 g ref after")!!
        val g = t122c(7_200)
        assertNull(doze(g, "U120 g before", until = S + 3_000_000L))
        g.restore(3_000, RestoreInfo(FallbackRestoreStatus.PENDING))
        val rg = doze(g, "U120 g after")!!
        assertEquals(eventsOf(a.steps), eventsOf(g.steps), "g: events differ from the uninterrupted run")
        assertEquals(a.steps.map { it.view }, g.steps.map { it.view }, "g: views differ")
        // Same alarm as without the extra Step: lostLongAt + 1 s.
        val lla = estimateOf(g.steps.first { st -> st.events.any { it is GpsLost } }.state).lostLongAtS!!
        assertEquals(S + TMath.floorMs(lla) + 1_000L, firstAlarm(rg.steps).atMs)
        assertEquals(firstAlarm(ra.steps), firstAlarm(rg.steps))
    }

    // ================================================================ U122: speed before `established` while LOST (C26)

    /** Not established (movingTimeS 60, movingSamples 2), hint BUS, dSmooth 30 000, the fix at S. */
    private fun preState(ground: Double?, p: EngineParams = EngineParams()): EngineState =
        trackingState(cfg(hint = VehicleKind.BUS), p = p, d = 30_000.0, ground = ground, closing = null, established = false)
            .copy(movingTimeS = 60.0, movingSamples = 2)

    @Test
    fun `U122 preV lifts dead reckoning to the measured ground speed while LOST before established`() {
        // (a) ground 20: lift, cvDr 20/1.2, GPS_LOST at about N + 621 s (T10.5: N + 5 301 s).
        val a = driverFrom(preState(20.0))
        val ra = doze(a, "U122 a")!!
        val lostA = ra.steps.first { st -> st.events.any { it is GpsLost } }
        val ea = estimateOf(lostA.state)
        assertFalse(ea.established)
        assertTrue(ea.lift, "a lift")
        assertEquals(20.0 / 1.2, ea.cvDr)
        assertEquals((20.0 / 1.2) * 1.2, ea.vDr)
        val aa = firstAlarm(ra.steps)
        assertEquals(AlarmReason.GPS_LOST, aa.reason)
        assertEquals(U122_A_ALARM_MS, aa.atMs - S, "a: pinned")
        assertTrue(abs((aa.atMs - S) / 1000.0 - 621.0) <= 5.0)
        // (b) ground 4: preV 3.33 < hint 4.63, no lift; W rings at about N + 4 126 s.
        val b = driverFrom(preState(4.0))
        val rb = doze(b, "U122 b")!!
        val eb = estimateOf(rb.steps.first { st -> st.events.any { it is GpsLost } }.state)
        assertFalse(eb.lift, "b lift")
        val ab = firstAlarm(rb.steps)
        assertEquals(AlarmReason.GPS_LOST, ab.reason)
        assertEquals(U122_B_ALARM_MS, ab.atMs - S, "b: pinned")
        assertTrue(abs((ab.atMs - S) / 1000.0 - 4_126.0) <= 5.0)
        // (c) as (a), GPS still OK at N + 30 s: v = hint, no lift.
        val c = driverFrom(preState(20.0)).tick(30)
        assertEquals(GpsStatus.OK, c.view.gps)
        val ec = estimateOf(c.state)
        assertFalse(ec.lift)
        assertEquals(20.0 / 3.6, ec.v)
        // (d) lostSpeedGuardUpdates 0, (e) ground null: no lift.
        for ((tag, st) in listOf("d" to preState(20.0, params("{\"lostSpeedGuardUpdates\": 0}")), "e" to preState(null))) {
            val r = doze(driverFrom(st), "U122 $tag")!!
            assertFalse(estimateOf(r.steps.first { s -> s.events.any { it is GpsLost } }.state).lift, "$tag lift")
        }
        log.append("U122 a ${(aa.atMs - S) / 1000.0} s, b ${(ab.atMs - S) / 1000.0} s\n")
    }

    // ================================================================ U123 c–i: slow-vehicle net (C27)

    private class Fx(val y: Double, val east: Double, val acc: Double, val spd: Double? = null)

    /**
     * stand() of U114 generalised: route along the meridian [east] m east of the destination, start 3 km south (y = 3 000), y
     * decreasing northwards; [y] (t, s) gives the position at t; [fix] (k, t, y) the delivered fix (null = none) every [everyS] s.
     * Returns every Step (t, Step) until the first Alarm or [maxS].
     */
    private fun pass(
        config: TripConfig,
        east: Double,
        v: Double,
        everyS: Int,
        y: (Int) -> Double,
        maxS: Int = 7_200,
        params: EngineParams = EngineParams(),
        fix: (Int, Int, Double) -> Fx? = { _, _, yy -> Fx(yy, east, 8.0) },
    ): List<Pair<Int, Step>> {
        val p0 = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, 3_000.0), east, 0.0)
        val d0 = distanceM(p0.lat, p0.lng, DEST.lat, DEST.lng)
        val l = app.napstop.core.trip.FixRec(S, p0.lat, p0.lng, 8.0, d0, null)
        var st = trackingState(config, p = params, d = d0, ground = v, closing = v * 0.95, now = S, lastFixAt = S)
        st = st.copy(last = l, recent = listOf(l), dSmooth = d0, minD = d0, last3 = listOf(d0), dStartM = d0 + 5_000.0)
        val out = ArrayList<Pair<Int, Step>>()
        var t = 0
        var k = 0
        while (t < maxS) {
            t += everyS
            k++
            val yy = y(t)
            val moving = abs(yy - y(t - everyS)) > 0.0
            val f = fix(k, t, yy) ?: continue
            val pt = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, f.y), f.east, 0.0)
            val s = TripEngine.reduce(st, LocationFix(S + t * 1000L, S + t * 1000L, pt.lat, pt.lng, f.acc, f.spd ?: if (moving) v else 0.0))
            st = s.state
            out += t to s
            if (s.events.any { it is Alarm }) break
        }
        return out
    }

    /** (p) geometry: 2 m/s, stops [stopNorth] m north of the closest point. */
    private fun yStop(stopNorth: Double, v: Double = 2.0): (Int) -> Double = { t -> maxOf(3_000.0 - v * t, -stopNorth) }

    private fun yForD(d: Double, east: Double = 800.0) = -sqrt(d * d - east * east)

    private fun alarmOf(steps: List<Pair<Int, Step>>): Pair<Int, Alarm>? =
        steps.firstNotNullOfOrNull { (t, s) -> s.events.filterIsInstance<Alarm>().firstOrNull()?.let { t to it } }

    @Test
    fun `U123 c d d2 poor fixes never set the mark, the mark comes with the first good fix`() {
        // (c) U114 x, y (O1 repro) are unchanged with the defaults (T10.6 on): DISTANCE at 780 s / 480 m (pinned there).
        val d500 = cfg(AlarmMode.DISTANCE, thr = 500)
        // (d) as (p), every fix acc 80: no good fix, no mark, silent.
        val d = pass(d500, 800.0, 2.0, 5, yStop(2_000.0)) { _, _, yy -> Fx(yy, 800.0, 80.0) }
        assertNull(alarmOf(d), "d: silent")
        assertTrue(d.all { it.second.state.passAnchorD == null }, "d: no mark")
        // (d2) acc 80 until 1 800 m north of the closest point, then acc 8 (no stop: interpretation noted in T12.md).
        val d2 = pass(d500, 800.0, 2.0, 5, yStop(10_000.0)) { _, _, yy -> Fx(yy, 800.0, if (yy > -1_800.0) 80.0 else 8.0) }
        val firstGood = d2.indexOfFirst { (_, s) -> s.state.last!!.accM <= 50.0 }
        assertTrue(d2.take(firstGood).all { it.second.state.passAnchorD == null }, "d2: mark before the first good fix")
        val g = d2[firstGood].second.state
        assertEquals(g.dSmooth, g.passAnchorD, "d2: mark = dSmooth at the first good fix")
        val (ta, a) = alarmOf(d2)!!
        assertEquals(AlarmReason.PASSED_CLOSEST, a.reason)
        val ia = d2.indexOfFirst { it.first == ta }
        val sa = d2[ia].second.state
        val sp = d2[ia - 1].second.state
        assertTrue(sa.last3[1] - sa.passAnchorD!! >= 300.0, "d2: rang without two fixes 300 m above the mark")
        assertTrue(sp.last3.size < 3 || sp.last3[1] - sp.passAnchorD!! < 300.0 || !(sp.last3[1] < sp.last3[2]), "d2: should have rung earlier")
        log.append("U123 d2: mark ${g.passAnchorD} at ${d2[firstGood].first} s, PASSED_CLOSEST at $ta s\n")
    }

    @Test
    fun `U123 e f one fix away from a parked vehicle does not ring, two consecutive ones do`() {
        val d500 = cfg(AlarmMode.DISTANCE, thr = 500)
        val stopY = yForD(1_450.0)
        fun run(outliers: Map<Int, Double>): List<Pair<Int, Step>> =
            pass(d500, 800.0, 2.0, 30, { t -> maxOf(3_000.0 - 2.0 * t, stopY) }) { k, _, yy ->
                val o = outliers[k]
                if (o != null) Fx(yForD(o), 800.0, 15.0, 0.0) else Fx(yy, 800.0, 8.0, if (yy > stopY) 2.0 else 0.0)
            }
        // Parked from k ≈ 140 (t ≈ 4 200 s); outliers at k = 160 (and 161).
        val base = run(emptyMap())
        assertNull(alarmOf(base), "e base: silent")
        val mark = base.last().second.state.passAnchorD!!
        assertTrue(1_450.0 - mark < 300.0, "e: parked less than 300 m above the mark ($mark)")
        val e = run(mapOf(160 to 1_950.0))
        assertNull(alarmOf(e), "e: one fix 500 m away rang")
        val f = run(mapOf(160 to 1_850.0, 161 to 1_900.0))
        val (tf, af) = alarmOf(f)!!
        assertEquals(AlarmReason.PASSED_CLOSEST, af.reason, "f")
        assertEquals(161 * 30, tf, "f: at the second fix away")
        assertTrue(f.none { (_, s) -> s.events.any { it is Overshoot } })
        log.append("U123 e: mark $mark; f: PASSED_CLOSEST at $tf s\n")
    }

    @Test
    fun `U123 g a REANCHOR clears the mark`() {
        val d500 = cfg(AlarmMode.DISTANCE, thr = 500)
        // Mark set (about 1 300 m), then three fixes 5 km south at +5, +20, +35 s: IMPLAUSIBLE, IMPLAUSIBLE, REANCHOR.
        val base = pass(d500, 800.0, 2.0, 5, yStop(2_000.0), maxS = 2_100)
        val st0 = base.last().second.state
        assertNotNull(st0.passAnchorD, "g: mark set")
        var st = st0
        val tl = base.last().first
        val far = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, 5_000.0), 800.0, 0.0)
        val steps = listOf(5, 20, 35).map { dt ->
            val at = S + (tl + dt) * 1000L
            TripEngine.reduce(st, LocationFix(at, at, far.lat, far.lng, 8.0, 2.0)).also { st = it.state }
        }
        assertEquals(st0.passAnchorD, steps[0].state.passAnchorD, "g: a dropped fix keeps the mark")
        assertEquals(st0.passAnchorD, steps[1].state.passAnchorD, "g: a dropped fix keeps the mark")
        val re = steps[2].state
        assertEquals(re.last!!.d, re.minD, "g: REANCHOR")
        assertNull(re.passAnchorD, "g: mark after REANCHOR")
    }

    @Test
    fun `U123 h the mark is the minimum seen, turning back does not ring, moving away again does`() {
        val d500 = cfg(AlarmMode.DISTANCE, thr = 500)
        // Forward at 2 m/s to d = 1 550 (poor fixes until then, so the mark comes late), 5 min back at 0.9 m/s, forward again.
        val y1 = yForD(1_550.0)
        val t1 = ((3_000.0 - y1) / 2.0).toInt()
        val y: (Int) -> Double = { t ->
            when {
                t <= t1 -> 3_000.0 - 2.0 * t
                t <= t1 + 300 -> 3_000.0 - 2.0 * t1 + 0.9 * (t - t1)
                else -> 3_000.0 - 2.0 * t1 + 0.9 * 300 - 2.0 * (t - t1 - 300)
            }
        }
        val steps = pass(d500, 800.0, 2.0, 5, y) { _, t, yy -> Fx(yy, 800.0, if (t < t1) 80.0 else 8.0, if (t in (t1 + 1)..(t1 + 300)) 0.9 else 2.0) }
        val (ta, a) = alarmOf(steps)!!
        assertEquals(AlarmReason.PASSED_CLOSEST, a.reason)
        assertTrue(ta > t1 + 300, "h: rang at $ta s while turning back")
        // The mark only goes down while it exists, and equals the minimum dSmooth of the good fixes since it was set.
        var seen: Double? = null
        var first: Double? = null
        for ((_, s) in steps) {
            val m = s.state.passAnchorD
            if (m == null) {
                seen = null
                continue
            }
            val ds = s.state.dSmooth!!
            val good = s.state.last!!.accM <= 50.0
            seen = if (seen == null) ds else if (good) minOf(seen, ds) else seen
            assertEquals(seen, m, "h: mark is not the minimum seen")
            if (first == null) first = m
        }
        val atAlarm = steps.last().second.state
        assertTrue(atAlarm.passAnchorD!! < first!! - 100.0, "h: the turn back lowered the mark (${first} → ${atAlarm.passAnchorD})")
        assertTrue(atAlarm.last3[1] - atAlarm.passAnchorD!! >= 300.0)
        assertEquals(U123_H_ALARM_S, ta, "h: pinned")
        log.append("U123 h: first mark $first, mark at alarm ${atAlarm.passAnchorD}, PASSED_CLOSEST at $ta s\n")
    }

    /** splitmix64 (as Mix of T105GapTest). */
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

    @Test
    fun `U123 i a fake minD from one outlier then a parked vehicle with GNSS jitter never rings, 400 runs`() {
        // The designer's row says DISTANCE 500; with minD lowered to 400 m by the outlier, dSmooth = 400 <= 500 rings DISTANCE at
        // the outlier itself (dSmooth is the outlier alone after the gap), so the net is never reached. DISTANCE 200 keeps the
        // geometry (standing 1 500 m, fake minD 400 m) without a mode alarm (noted for the designer in T12.md).
        val config = cfg(AlarmMode.DISTANCE, thr = 200)
        var rings = 0
        var maxRise = Double.NEGATIVE_INFINITY
        val bad = ArrayList<String>()
        var runs = 0
        for (seed in 1L..200L) for (every in listOf(5, 30)) {
            val r = Mix(seed * 1_000_003L + every)
            val e = EngineDriver(config)
            val tStand = ((20_000.0 - 1_500.0) / 12.0).toInt()
            var t = 0
            var outlierDone = false
            var minDAfter: Double? = null
            while (t < tStand + 1_800) {
                t += every
                val standing = t >= tStand
                val d = if (standing) 1_500.0 else 20_000.0 - 12.0 * t
                val outT = tStand + 300
                val s = if (standing && !outlierDone && t >= outT) {
                    outlierDone = true
                    e.fix(t, 400.0, acc = 15.0, spd = 0.0).also { minDAfter = it.state.minD }
                } else if (standing && every == 5 && !outlierDone && t > outT - 30) {
                    continue // 25 s without a fix before the outlier so that it is plausible (as O1c)
                } else if (standing) {
                    e.fix(t, d + r.dbl(-50.0, 50.0), acc = 50.0, spd = 0.0, eastM = r.dbl(-50.0, 50.0))
                } else {
                    e.fix(t, d, spd = 12.0)
                }
                val st = s.state
                val m = st.passAnchorD
                if (m != null && st.last3.size == 3) maxRise = maxOf(maxRise, st.last3[1] - m)
                if (s.events.any { it is Overshoot || (it is Alarm && (it.reason == AlarmReason.PASSED_CLOSEST || it.reason == AlarmReason.OVERSHOOT)) }) {
                    rings++
                    bad += "seed $seed every $every t=$t ${s.events}"
                    break
                }
                if (s.events.any { it is Alarm }) {
                    rings++
                    bad += "seed $seed every $every t=$t other alarm ${s.events.filterIsInstance<Alarm>()}"
                    break
                }
            }
            assertTrue(abs((minDAfter ?: 0.0) - 400.0) <= 1.0, "i: the outlier lowered minD (seed $seed every $every: $minDAfter)")
            runs++
        }
        File(outDir, "u123-i-jitter.txt").writeText("runs=$runs rings=$rings max(last3[1] - passAnchorD)=$maxRise\n${bad.take(20).joinToString("\n")}\n")
        assertEquals(400, runs)
        assertEquals(0, rings, bad.take(5).joinToString("\n"))
    }

    // ================================================================ U124: snapshot key (C28)

    @Test
    fun `U124 passAnchorD is written right after minDChord, round-trips, a missing key reads null and a wrong type fails`() {
        for (anchor in listOf<Double?>(null, 1_304.25, 0.1, 5e-324)) {
            val st = trackingState().copy(minD = 1234.5, minDChord = true, passAnchorD = anchor)
            val json = TripEngine.encodeSnapshot(st)
            val lit = anchor?.toString() ?: "null"
            assertTrue(json.contains("\"minDChord\":true,\"passAnchorD\":$lit,\"alarmedChordD\":null,\"last3\""), json.substringAfter("\"minDChord\"").take(60))
            assertEquals(st, TripEngine.decodeSnapshot(json))
            val without = json.replace(",\"passAnchorD\":$lit", "")
            assertFalse(without.contains("passAnchorD"))
            assertEquals(st.copy(passAnchorD = null), TripEngine.decodeSnapshot(without))
            for (wrong in listOf("\"1\"", "true")) {
                assertThrows(SnapshotFormatException::class.java) { TripEngine.decodeSnapshot(json.replace("\"passAnchorD\":$lit", "\"passAnchorD\":$wrong")) }
            }
        }
    }

    @org.junit.jupiter.api.AfterEach
    fun writeLog() {
        if (log.isNotEmpty()) File(outDir, "t106-log.txt").appendText(log.toString())
    }

    private companion object {
        /** U120 (b): measured (T12.3). */
        const val U120_B_ALARM_MS = 5_911_009L

        /** U122 (a), (b): measured (T12.3); designer by hand about 621 s / 4 126 s. */
        const val U122_A_ALARM_MS = 620_000L
        const val U122_B_ALARM_MS = 4_126_000L

        /** U123 (h): measured (T12.3). */
        const val U123_H_ALARM_S = 2_655
    }
}
