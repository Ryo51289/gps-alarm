package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.Estimate
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.TMath
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.fallbackPredictedAt
import app.napstop.core.trip.fallbackTarget
import app.napstop.core.trip.predictedAlarmAt
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.est
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Random

/** T10.2 rows of FallbackPlannerTest (U93–U95, U97 b), kept in their own file for size. */
class FallbackPlannerT102Test {
    private val n = S + 1_000_000

    private data class R(val predicted: Long, val predictedFb: Long, val target: Long)

    private fun eval(mode: AlarmMode, e: Estimate?, p: EngineParams = EngineParams(), gps: GpsStatus = GpsStatus.OK): R {
        val w = work(trackingState(cfg(mode, hint = VehicleKind.TRAIN), p, now = n, gps = gps))
        val pr = predictedAlarmAt(w, e).withBattery!!
        val fb = fallbackPredictedAt(w, e, pr)!!
        return R(pr, fb, fallbackTarget(n, pr, fb, p)!!)
    }

    @Test
    fun `U93 fallbackPredictedAt with the vehicle-hint speed floor`() {
        val e10 = est(50_000.0, 10.0, 5020.0)
        assertEquals(R(n + 4_900_000, n + 3_848_727, n + 3_066_546), eval(AlarmMode.DISTANCE, e10))
        val e15 = est(50_000.0, 15.0, 50_000 * 1.2 / 18 + 20)
        assertEquals(R(n + 3_266_666, n + 3_266_666, n + 2_630_000), eval(AlarmMode.DISTANCE, e15))
        val off = params("{\"fallbackHintSpeedFactor\": 0}")
        assertEquals(R(n + 4_900_000, n + 4_900_000, n + 3_855_000), eval(AlarmMode.DISTANCE, e10, off))
        assertEquals(R(n + 4_120_000, n + 3_047_272, n + 2_465_454), eval(AlarmMode.TIME, e10))
        val lost = eval(AlarmMode.DISTANCE, e10, gps = GpsStatus.LOST)
        assertEquals(n + 3_820_000, lost.predicted)
        assertEquals(n + 2_747_272, lost.predictedFb)
        val w = work(trackingState(cfg(), now = n))
        assertEquals(n + 123, fallbackPredictedAt(w, null, n + 123))
    }

    @Test
    fun `U94 time floor now plus 600 s in the far zone, exact P plus 30 s on entering the near zone at N plus 20 s`() {
        val c = cfg(AlarmMode.TIME, thrMin = 30, hint = VehicleKind.TRAIN)
        // Two earlier fixes so the median of 3 (one-sample lag) gives dSmooth = 12 000 at N.
        val pA = TestGeo.pointAtExactDistance(DEST, 12_025.0)
        val pB = TestGeo.pointAtExactDistance(DEST, 12_000.0)
        val base = trackingState(c, now = n - 5000, lastFixAt = n - 5000, d = 12_000.0, ground = 6.0, closing = 5.0, tier = SamplingTier.DENSE)
        val fA = base.last!!.copy(fixAtMs = n - 10_000, lat = pA.lat, d = 12_025.0)
        val fB = base.last!!.copy(lat = pB.lat)
        val s0 = base.copy(last = fB, recent = listOf(fA, fB), last3 = listOf(12_025.0, 12_000.0))
        val e = driverFrom(s0)
        var k = 0
        val emissions = ArrayList<Pair<Long, Long>>()
        while (true) {
            val t = n + k * 5000L
            val st = e.fixAt(((t - e.startMs) / 1000).toInt(), TestGeo.pointAtExactDistance(DEST, 11_975.0 - 25.0 * k), spd = 6.0)
            st.events.filterIsInstance<FallbackAlarmChanged>().forEach { ev -> ev.fallbackAtMs?.let { emissions += t to it } }
            if (k == 0) {
                assertEquals(2420, st.view.etaS)
                assertEquals(n + 620_000, st.view.predictedAlarmAtMs)
            }
            if (st.events.any { it is Alarm }) {
                assertEquals(AlarmReason.TIME, st.events.filterIsInstance<Alarm>().single().reason)
                assertEquals(n + 620_000, t)
                break
            }
            assertTrue(kotlin.math.abs(st.view.predictedAlarmAtMs!! - (n + 620_000)) <= 1, "k=$k")
            val fb = st.view.fallbackAtMs!!
            assertTrue(fb > t)
            if (t < n + 20_000) assertTrue(fb - t >= 540_000, "k=$k")
            k++
        }
        // T10.3 corrected U94: at N + 20 000, T = 600 <= fallbackNearS (near zone) -> raised to exactly P + 30 s = N + 650 000.
        assertEquals(listOf(n to n + 600_000, n + 20_000 to n + 650_000), emissions)
        assertEquals(2, emissions.size)
    }

    @Test
    fun `U95 F3 far zone stays at least 540 s ahead, fallback never rings before the engine`() {
        for (hint in listOf(VehicleKind.TRAIN, VehicleKind.COACH)) for (cv in listOf(2.0, 5.0, 8.0, 12.0, 15.0, 20.0)) {
            val tag = "$hint c=$cv"
            val e = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000, hint = hint))
            val p = e.p
            var t = 0
            var lastFix = -1_000_000
            var fbOs: Long? = null
            var prevView = e.view
            var lastFarEmit: Int? = null
            var alarmAt: Int? = null
            val cvHint = p.fallbackHintSpeedFactor * (if (hint == VehicleKind.TRAIN) 55 else 60) / 3.6 / p.routeFactorPrior
            while (t <= 40_000) {
                val pred = prevView.predictedAlarmAtMs
                val tRem = if (pred == null) Long.MAX_VALUE else (pred - e.ms(t)) / 1000
                val interval = if (tRem > 3600) 180 else if (tRem > 900) 30 else 5
                val st = if (t - lastFix >= interval) {
                    lastFix = t
                    e.fix(t, TMath.max(0.0, 60_000.0 - cv * t), spd = cv)
                } else if (t % 60 == 0) {
                    e.tick(t)
                } else {
                    t += 5
                    continue
                }
                val now = e.ms(t)
                for (ev in st.events) if (ev is FallbackAlarmChanged) {
                    if (ev.cause == FallbackCause.ETA && prevView.fallbackAtMs != null && st.view.predictedAlarmAtMs != null) {
                        assertTrue(now < minOf(prevView.fallbackAtMs!!, st.view.predictedAlarmAtMs!!) - 30_000, "$tag I4 at $t")
                    }
                    val far = st.view.predictedAlarmAtMs?.let { it - now > 600_000 } ?: false
                    if (far && ev.fallbackAtMs != null && lastFarEmit != null && ev.fallbackAtMs!! > (prevView.fallbackAtMs ?: 0)) {
                        assertTrue(t - lastFarEmit >= 60, "$tag later far-zone move within 60 s at $t")
                    }
                    if (far) lastFarEmit = t
                    fbOs = ev.fallbackAtMs
                }
                if (st.events.any { it is Alarm }) {
                    fbOs = prevView.fallbackAtMs
                    val a = st.events.filterIsInstance<Alarm>().single()
                    assertTrue(a.ringNow, tag)
                    alarmAt = t
                    if (cv == 2.0) {
                        assertEquals(AlarmReason.TIMEOUT, a.reason, tag)
                        assertEquals(14_400, t, tag)
                        assertEquals(S + 14_430_000, fbOs, tag)
                    } else {
                        assertEquals(AlarmReason.DISTANCE, a.reason, tag)
                        assertEquals(prevView.predictedAlarmAtMs!! + 30_000, fbOs, tag)
                    }
                    break
                }
                assertTrue(fbOs == null || fbOs!! > now, "$tag fallback due at $t")
                val v = st.view
                val pr = v.predictedAlarmAtMs!!
                if (pr - now > 600_000) assertTrue(v.fallbackAtMs!! - now >= 540_000, "$tag F3 at $t")
                if (cv >= cvHint) {
                    val pFb = fallbackPredictedAt(work(st.state), estimateOf(st.state), pr)
                    assertEquals(pr, pFb, "$tag predictedFb at $t")
                }
                prevView = v
                t += 5
            }
            assertTrue(alarmAt != null, tag)
        }
    }

    @Test
    fun `U97 b old T10 parameters give the T10_1 fallback time bit for bit`() {
        val old = params("{\"fallbackEarlyFrac\": 0.1, \"fallbackEarlyMaxS\": 1800, \"fallbackHintSpeedFactor\": 0}")
        val rng = Random(97)
        val modes = AlarmMode.entries
        repeat(1000) { i ->
            val mode = modes[i % 3]
            val now = S + rng.nextInt(1_000_000_000)
            val tS = rng.nextDouble() * 172_800
            val pred = now + TMath.floorMs(tS)
            val cvDr = (1 - rng.nextDouble()) * 40
            val dNow = rng.nextDouble() * 1_200_000
            val e = est(dNow, cvDr, dNow * 1.2 / (cvDr * 1.2) + 20)
            val w = work(trackingState(cfg(mode, hint = VehicleKind.entries[i % 4]), old, now = now, slow = i % 7 == 0))
            val got = fallbackTarget(now, pred, fallbackPredictedAt(w, e, pred), old)!!
            val t = TMath.max(0.0, TMath.toS(pred - now))
            val want = TMath.max(now + 10_000, TMath.max(pred, now) + 30_000 - TMath.floorMs(TMath.min(1800.0, 0.1 * TMath.max(0.0, t - 600))))
            assertEquals(want, got, "i=$i")
        }
    }
}
