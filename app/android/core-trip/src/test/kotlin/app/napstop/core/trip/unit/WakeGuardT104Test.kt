package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.WAKE_GUARD_MS
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * T10.4 (T10 mục cuối "T10.4" §7.1): wakeGuardMs on the wake-up candidates (GAP-1) and lostAfterS that never shrinks between
 * two fixes (GAP-2). U99 and U100 replace the tester's pinned `T12T GAP-1` / `T12T GAP-2` repros (same builder, flipped).
 */
class WakeGuardT104Test {
    /** Tester's repro base: TRACKING, established, DISTANCE 1000, closing 12.5 m/s (k 1.2), one fix at S, tier SPARSE, field 5. */
    private fun lostTrip(t0S: Int): EngineDriver =
        driverFrom(trackingState(d = 1000.0 + 12.5 * t0S, tier = SamplingTier.SPARSE, policyAtFix = 5))

    private fun assertI13(s: Step, tag: String) {
        val w = s.view.wakeAtMs
        if (s.view.phase == TripPhase.ENDED) {
            assertEquals(null, w, "$tag: I13 ENDED")
        } else {
            assertNotNull(w, "$tag: I13 wakeAtMs null in ${s.view.phase}")
            assertTrue(w!! > s.state.nowMs, "$tag: I13 wakeAtMs not after now")
        }
    }

    private fun assertI14(s: Step, tag: String) {
        val again = TripEngine.reduce(s.state, Tick(s.state.nowMs))
        assertTrue(again.events.isEmpty(), "$tag: I14 events ${again.events}")
        assertEquals(s.state, again.state, "$tag: I14 state")
        assertEquals(s.view, again.view, "$tag: I14 view")
    }

    /** Doze loop: only Tick(view.wakeAtMs) until a Step has an Alarm. Returns (wake time − S, Step) per wake-up. */
    private fun doze(e: EngineDriver, tag: String, max: Int = 2_000): List<Pair<Long, Step>> {
        val out = ArrayList<Pair<Long, Step>>()
        var prev = Long.MIN_VALUE
        while (true) {
            assertI13(e.last, tag)
            val w = e.view.wakeAtMs!!
            assertTrue(w > prev, "$tag: wake-ups not strictly increasing")
            prev = w
            val s = e.tickMs(w)
            out += (w - S) to s
            if (s.events.any { it is Alarm }) {
                assertI13(s, tag)
                return out
            }
            check(out.size < max) { "$tag: no alarm after $max wake-ups" }
        }
    }

    @Test
    fun `U99 GAP-1 a Tick exactly at predicted keeps a wake-up and the next one rings GPS_LOST`() {
        val e = lostTrip(3610) // etaS = 3 710 − t
        val s10 = e.tick(10)
        assertEquals(SamplingTier.MEDIUM, s10.view.samplingPolicy!!.tier)
        assertTrue(s10.events.none { it is GpsLost })
        assertEquals(180, s10.state.policyIntervalAtLastFixS)
        assertEquals(S + 540_000, s10.view.wakeAtMs) // c2
        // (a) Doze loop.
        val wakes = doze(e, "U99 a")
        assertEquals(listOf(540_000L, 1_611_000L, 1_911_000L, 2_450_000L, 2_511_000L), wakes.map { it.first })
        val lost = wakes[0].second
        assertEquals(GpsLost(S + 540_000, GpsLostCause.NO_FIX_TIMEOUT, 540), lost.events.filterIsInstance<GpsLost>().single())
        assertEquals(S + 2_510_000, lost.view.predictedAlarmAtMs)
        assertEquals(SamplingTier.DENSE, wakes[1].second.view.samplingPolicy!!.tier)
        assertEquals(
            FallbackAlarmChanged(S + 1_911_000, S + 2_540_000, FallbackCause.ETA),
            wakes[2].second.events.filterIsInstance<FallbackAlarmChanged>().single(),
        )
        val ring = wakes[4].second
        val alarm = ring.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.GPS_LOST, alarm.reason)
        assertTrue(alarm.ringNow)
        assertEquals(FallbackAlarmChanged(S + 2_511_000, null, FallbackCause.SUPERSEDED), ring.events.filterIsInstance<FallbackAlarmChanged>().single())
        // (b) Same wake-ups up to the c8 Step, then a Tick exactly at P.
        val b = lostTrip(3610)
        b.tick(10)
        for (w in listOf(540_000L, 1_611_000L, 1_911_000L, 2_450_000L)) b.tickMs(S + w)
        val atP = b.tickMs(S + 2_510_000)
        assertTrue(atP.events.isEmpty(), "Tick at P: ${atP.events}")
        assertEquals(TripPhase.TRACKING, atP.view.phase)
        assertEquals(S + 2_510_000, atP.view.predictedAlarmAtMs)
        assertEquals(S + 2_511_000, atP.view.wakeAtMs) // before T10.4: null
        assertEquals(AlarmReason.GPS_LOST, b.tickMs(S + 2_511_000).events.filterIsInstance<Alarm>().single().reason)
    }

    @Test
    fun `U100 GAP-2 a policy shortened in the Step keeps c2 and Tick(now) silent`() {
        val e = lostTrip(3700) // etaS = 3 800 − t
        val s = e.tick(100)
        assertEquals(SamplingTier.MEDIUM, s.view.samplingPolicy!!.tier)
        assertEquals(GpsStatus.OK, s.view.gps)
        assertTrue(s.events.none { it is GpsLost })
        assertEquals(S + 540_000, s.view.wakeAtMs) // c2 not dropped
        assertI14(s, "U100") // before T10.4: GpsLost(NO_FIX_TIMEOUT, 100)
        // (a) Doze loop.
        val wakes = doze(e, "U100 a")
        assertEquals(listOf(540_000L, 1_701_000L, 2_001_000L, 2_540_000L, 2_601_000L), wakes.map { it.first })
        assertEquals(GpsLost(S + 540_000, GpsLostCause.NO_FIX_TIMEOUT, 540), wakes[0].second.events.filterIsInstance<GpsLost>().single())
        assertEquals(S + 2_600_000, wakes[0].second.view.predictedAlarmAtMs)
        assertEquals(AlarmReason.GPS_LOST, wakes.last().second.events.filterIsInstance<Alarm>().single().reason) // before: 2 800 000
        // (b) Ticks every 5 s.
        val f = lostTrip(3700)
        var lostT = -1
        var alarmT = -1
        var t = 0
        while (alarmT < 0 && t < 4000) {
            t += 5
            val st = f.tick(t)
            if (lostT < 0 && st.events.any { it is GpsLost }) lostT = t
            if (st.events.any { it is Alarm }) alarmT = t
        }
        assertEquals(540, lostT) // before T10.4: 105
        assertEquals(2605, alarmT)
    }

    @Test
    fun `U101 policyIntervalAtLastFixS is the longest interval in force since the last fix was requested`() {
        val p = EngineParams()
        // (a) DENSE (field 5), a fix whose predicted is far (T > 1 125 s) → MEDIUM: field 30, c2 = fix + 90 s.
        val a = driverFrom(trackingState(d = 30_000.0, tier = SamplingTier.DENSE))
        assertEquals(5, a.state.policyIntervalAtLastFixS)
        val sa = a.fix(5, 30_000.0 - 62.5)
        assertEquals(SamplingTier.MEDIUM, sa.view.samplingPolicy!!.tier)
        assertEquals(30, sa.state.policyIntervalAtLastFixS)
        assertEquals(S + 95_000, sa.state.last!!.fixAtMs + lostAfterS(p, sa.state.policyIntervalAtLastFixS, sa.state.policy) * 1000L)
        assertEquals(S + 95_000, sa.view.wakeAtMs)
        // (b) SPARSE (field 180), MAX_SAVING (360), then ALARM_EARLIER (back to 180): field keeps 360 → GpsLost at 1 080 s.
        fun b(): EngineDriver {
            val e = driverFrom(trackingState(d = 100_000.0, tier = SamplingTier.SPARSE))
            assertEquals(180, e.state.policyIntervalAtLastFixS)
            assertEquals(360, e.user(10, UserActionKind.BATTERY_MAX_SAVING).state.policyIntervalAtLastFixS)
            val s20 = e.user(20, UserActionKind.BATTERY_ALARM_EARLIER)
            assertEquals(180, s20.view.samplingPolicy!!.intervalS)
            assertEquals(360, s20.state.policyIntervalAtLastFixS)
            return e
        }
        val eb = b()
        assertTrue(eb.tick(1079).events.none { it is GpsLost }) // before T10.4: GpsLost at 540 s
        assertEquals(GpsLost(S + 1_080_000, GpsLostCause.NO_FIX_TIMEOUT, 1080), eb.tick(1080).events.filterIsInstance<GpsLost>().single())
        // (c) A fix resets the field to the policy at the start of its Step.
        val ec = b()
        val sc = ec.fix(1000, 100_000.0 - 12_500.0)
        assertEquals(S + 1_000_000, sc.state.last!!.fixAtMs)
        assertEquals(180, sc.state.policyIntervalAtLastFixS)
        val c2 = sc.state.last!!.fixAtMs + lostAfterS(p, sc.state.policyIntervalAtLastFixS, sc.state.policy) * 1000L
        assertEquals(S + 1_540_000, c2)
        assertTrue(sc.view.wakeAtMs!! <= c2)
        // (d) FallbackFired while SPARSE → ALARMING, DENSE: field stays 180, c2 kept, I14.
        val ed = driverFrom(trackingState(d = 100_000.0, tier = SamplingTier.SPARSE))
        val sd = ed.fired(100, S + 100_000)
        assertEquals(TripPhase.ALARMING, sd.view.phase)
        assertEquals(SamplingTier.DENSE, sd.view.samplingPolicy!!.tier)
        assertEquals(180, sd.state.policyIntervalAtLastFixS)
        assertTrue(sd.view.wakeAtMs!! <= S + 540_000 && sd.view.wakeAtMs!! > sd.state.nowMs)
        assertI14(sd, "U101 d")
        // (e) start: DENSE requested at once, field 5.
        assertEquals(5, TripEngine.start(cfg(), p, S).state.policyIntervalAtLastFixS)
    }

    // ---------------------------------------------------------------- U103 (P08 in a unit test)

    /** splitmix64, deterministic on every JVM. */
    private class Rng(seed: Long) {
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

    private class ModeCase(val name: String, val config: TripConfig, val slow: Boolean)

    private val modes = listOf(
        ModeCase("DISTANCE 500", cfg(AlarmMode.DISTANCE, thr = 500), false),
        ModeCase("DISTANCE 1000", cfg(AlarmMode.DISTANCE, thr = 1000), false),
        ModeCase("DISTANCE 10000", cfg(AlarmMode.DISTANCE, thr = 10_000), false),
        ModeCase("TIME 5", cfg(AlarmMode.TIME, thrMin = 5), false),
        ModeCase("TIME 15", cfg(AlarmMode.TIME, thrMin = 15), false),
        ModeCase("TIME 20", cfg(AlarmMode.TIME, thrMin = 20), false),
        ModeCase("TIME 30", cfg(AlarmMode.TIME, thrMin = 30), false),
        ModeCase("SMART", cfg(AlarmMode.SMART), false),
        ModeCase("SMART slow", cfg(AlarmMode.SMART), true),
    )

    /** One set: lost GPS at lostAfterS, then the Doze loop. Returns true when the alarm came at the GpsLost Step itself. */
    private fun p08Set(m: ModeCase, d: Double, ground: Double, closing: Double, guard: List<Double>, tag: String): Boolean {
        val st0: EngineState = trackingState(m.config, d = d, ground = ground, closing = closing, slow = m.slow, cvGuard = guard)
        val e = driverFrom(st0)
        val lostAt = S + lostAfterS(st0.params, st0.policyIntervalAtLastFixS, st0.policy) * 1000L
        val lost = e.tickMs(lostAt)
        assertTrue(lost.events.any { it is GpsLost }, "$tag: no GpsLost at lostAfterS")
        assertI13(lost, tag)
        if (lost.events.any { it is Alarm }) return true
        val p0 = lost.view.predictedAlarmAtMs!!
        val wakes = doze(e, tag)
        val ringStep = wakes.last().second
        val prevView = if (wakes.size >= 2) wakes[wakes.size - 2].second.view else lost.view
        val a = ringStep.events.filterIsInstance<Alarm>().single()
        assertTrue(a.ringNow, "$tag: ringNow")
        assertTrue(a.reason != AlarmReason.FALLBACK && a.reason != AlarmReason.FALLBACK_MISSED, "$tag: ${a.reason}")
        assertTrue(a.atMs in (p0 + 999)..(p0 + 1001), "$tag: alarm at ${a.atMs - p0} ms after P0")
        val fb = prevView.fallbackAtMs
        assertNotNull(fb, "$tag: no fallback before the alarm")
        assertTrue(a.atMs <= fb!! - 28_000, "$tag: alarm ${a.atMs - fb} ms vs fallback")
        return false
    }

    @Test
    fun `U103 P08 with GPS lost and only wake-up Ticks every mode rings 1 s after the predicted time`() {
        val rng = Rng(103)
        var sets = 0
        val immediate = ArrayList<String>()
        for (m in modes) {
            val round = Triple(46_000.0, 15.0, 12.5)
            val all = ArrayList<Pair<String, Triple<Double, Double, Double>>>()
            all += "(i)" to round
            repeat(50) { i ->
                val g = rng.dbl(3.0, 30.0)
                all += "(ii) #$i" to Triple(rng.dbl(3_000.0, 120_000.0), g, rng.dbl(0.6 * g, g))
            }
            for ((label, x) in all) {
                val (d, g, c) = x
                val ground = if (m.slow && label == "(i)") 3.0 else g
                val closing = if (m.slow && label == "(i)") 2.5 else c
                val tag = "${m.name} $label d=$d ground=$ground closing=$closing"
                if (p08Set(m, d, ground, closing, emptyList(), tag)) immediate += tag
                sets++
            }
            // (iii) lifted: cvGuard above closingV.
            val tag = "${m.name} (iii) lift"
            if (p08Set(m, round.first, round.second, round.third, listOf(1.3 * round.third), tag)) immediate += tag
            sets++
        }
        assertEquals(9 * 52, sets)
        assertTrue(immediate.size < sets / 2) { "too many sets alarm at the GpsLost Step: ${immediate.size}/$sets" }
        File(System.getProperty("napstop.outDir") ?: "build/napstop", "u103.txt").also { it.parentFile.mkdirs() }
            .writeText("sets=$sets alarmAtGpsLostStep=${immediate.size}\n${immediate.joinToString("\n")}\n")
    }

    // ---------------------------------------------------------------- U104 (I14 on states from real Steps)

    @Test
    fun `U104 I14 Tick at the state's own now emits nothing and changes nothing`() {
        val cases = ArrayList<Pair<String, Step>>()
        cases += "start" to TripEngine.start(cfg(), EngineParams(), S)
        cases += "ACQUIRING after NEVER_ACQUIRED" to EngineDriver().tick(120).also {
            assertEquals(GpsLostCause.NEVER_ACQUIRED, it.events.filterIsInstance<GpsLost>().single().cause)
        }
        for ((tier, d) in listOf(SamplingTier.SPARSE to 100_000.0, SamplingTier.MEDIUM to 30_000.0, SamplingTier.DENSE to 8_000.0)) {
            val s = driverFrom(trackingState(d = d, tier = tier)).fix(5, d - 62.5)
            assertEquals(tier, s.view.samplingPolicy!!.tier)
            cases += "TRACKING OK $tier" to s
        }
        cases += "TRACKING LOST" to driverFrom(trackingState(d = 50_000.0)).tick(60).also { assertEquals(GpsStatus.LOST, it.view.gps) }
        cases += "policy shortened (U100)" to lostTrip(3700).tick(100)
        val failed = EngineDriver().also { it.fix(0, 50_000.0) }
        cases += "fb FAILED" to failed.scheduled(1, failed.state.fallback.targetAtMs!!, false).also {
            assertEquals(FallbackStatus.FAILED, it.state.fallback.status)
        }
        fun alarmed(): EngineDriver = driverFrom(trackingState(d = 900.0, inStop = true)).also { it.tick(0) }
        cases += "ALARMING" to alarmed().last
        cases += "SNOOZED" to alarmed().user(0, UserActionKind.SNOOZE).also { assertEquals(TripPhase.SNOOZED, it.view.phase) }
        val ov = EngineDriver(cfg(AlarmMode.DISTANCE, thr = 1000))
        var t = 0
        for (d in listOf(3000.0, 2300.0, 1600.0, 900.0, 300.0, 400.0, 800.0, 1350.0)) {
            ov.fix(t, d, spd = 40 / 3.6)
            t += 60
        }
        assertEquals(TripPhase.OVERSHOT, ov.view.phase)
        cases += "OVERSHOT" to ov.last
        fun tracking(): EngineDriver = EngineDriver().also { it.fix(0, 50_000.0) }
        val target = tracking().state.fallback.targetAtMs!!
        val after = ((target - S) / 1000 + 1).toInt()
        cases += "restore RANG" to tracking().restore(after, RestoreInfo(FallbackRestoreStatus.RANG, target))
        cases += "restore MISSING" to tracking().restore(10, RestoreInfo(FallbackRestoreStatus.MISSING))
        cases += "restore PENDING" to tracking().restore(10, RestoreInfo(FallbackRestoreStatus.PENDING))
        for ((name, s) in cases) {
            assertTrue(s.view.phase != TripPhase.ENDED, name)
            assertI13(s, name)
            assertI14(s, name)
        }
    }
}
