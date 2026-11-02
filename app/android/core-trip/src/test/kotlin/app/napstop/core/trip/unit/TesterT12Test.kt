package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Tester additions for T12 (docs/test-reports/T12.md): C11 step 1b ordering, the C16 ENDED exception (mirrored in Swift by the
 * T13 tester with the same values), the Remote Config "blank" character set of parseOverrides, and a seeded property fuzz of
 * the reducer ("is there any input sequence after which the engine can no longer wake the user?").
 */
class TesterT12Test {
    // ---------------------------------------------------------------- C11 step 1b

    private fun err(c: TripConfig): String =
        assertThrows(IllegalArgumentException::class.java) { TripEngine.start(c, EngineParams(), S) }.message!!

    @Test
    fun `T12T C11 step 1b lone surrogate in tripId is checked after empty and before every other rule`() {
        val base = cfg(AlarmMode.DISTANCE, thr = 1000)
        // 1b before 2 (destLat), 3 (destLng), 4 (required), 6 (range): every later rule is also violated here.
        val allBad = base.copy(destLat = 91.0, destLng = 200.0, distanceThresholdM = null)
        assertEquals("tripId: invalid", err(allBad.copy(tripId = "trip\uD800")))
        assertEquals("tripId: invalid", err(base.copy(tripId = "\uDC00", destLat = Double.NaN)))
        assertEquals("tripId: invalid", err(base.copy(tripId = "\uDC00\uD800", destLng = 180.0))) // reversed pair
        assertEquals("tripId: invalid", err(base.copy(tripId = "\uD800a", distanceThresholdM = 150))) // high + non-low
        assertEquals("tripId: invalid", err(cfg(AlarmMode.TIME, thrMin = null).copy(tripId = "x\uDBFF")))
        // 1 still wins over everything (an empty string cannot hold a surrogate).
        assertEquals("tripId: empty", err(allBad.copy(tripId = "")))
        // A well-formed pair (emoji) and non-BMP text are valid; the snapshot round-trips the tripId unchanged.
        val emoji = "chuyến-\uD83D\uDE8C-1"
        val st = TripEngine.start(base.copy(tripId = emoji), EngineParams(), S).state
        assertEquals(emoji, TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(st)).config.tripId)
        // Only "empty" is a rule: whitespace-only tripIds are accepted (C11 says nothing about blank).
        TripEngine.start(base.copy(tripId = " "), EngineParams(), S)
    }

    // ---------------------------------------------------------------- C16 ENDED exception

    /**
     * Mirror values for T13: S = 1 800 000 000 000. TRACKING at 900 m (DISTANCE 1000, stopped) → Tick(S) rings
     * Alarm(DISTANCE) → UserAction(S + 10 000, DISMISS) → ENDED. Then the ENDED state is hand-edited to
     * alarm.snoozeUntilMs = X = S + 60 000 (a pre-C16 snapshot).
     */
    private fun endedWithStaleSnooze(): EngineState {
        val e = driverFrom(trackingState(cfg(), EngineParams(), d = 900.0, inStop = true))
        e.tick(0)
        val ended = e.user(10, UserActionKind.DISMISS)
        assertEquals(TripPhase.ENDED, ended.view.phase)
        assertNull(ended.state.alarm.snoozeUntilMs)
        return ended.state.copy(alarm = ended.state.alarm.copy(snoozeUntilMs = S + 60_000))
    }

    private fun assertUnchanged(input: EngineState, s: Step, tag: String) {
        assertSame(input, s.state, tag) // returned as is: not normalized, nowMs not advanced
        assertTrue(s.events.isEmpty(), tag)
        assertEquals(TripPhase.ENDED, s.view.phase, tag)
        assertEquals(S + 60_000, s.view.snoozeUntilMs, tag) // C16 exception: still X
        assertEquals(S + 60_000, s.state.alarm.snoozeUntilMs, tag)
        // C22: ENDED view
        assertNull(s.view.predictedAlarmAtMs, tag)
        assertFalse(s.view.batteryRisk, tag)
        assertNull(s.view.wakeAtMs, tag)
        assertEquals(input.nowMs, s.view.atMs, tag) // view at the state's own now (S + 10 000)
    }

    @Test
    fun `T12T C16 ENDED state with a stale snoozeUntilMs is returned unchanged by reduce and restore, not normalized`() {
        val st = endedWithStaleSnooze()
        assertEquals(S + 10_000, st.nowMs)
        val t = S + 20_000
        val p = TestGeo.pointOnMeridian(DEST, 500.0)
        val inputs: List<EngineInput> = listOf(
            Tick(t), Tick(S), Tick(S + 3_600_000),
            LocationFix(t, t, p.lat, p.lng, 8.0, 10.0),
            BatterySample(t, 3, false), LocationAvailability(t, AvailabilityCause.SERVICES_OFF),
            FallbackScheduled(t, S + 90_000, true), FallbackScheduled(t, S + 90_000, false), FallbackFired(t, S + 15_000),
            AlarmSilenced(t, t),
        ) + UserActionKind.entries.map { UserAction(t, it) }
        for (x in inputs) assertUnchanged(st, TripEngine.reduce(st, x), "reduce $x")
        val infos = listOf(
            RestoreInfo(FallbackRestoreStatus.PENDING), RestoreInfo(FallbackRestoreStatus.MISSING),
            RestoreInfo(FallbackRestoreStatus.UNKNOWN), RestoreInfo(FallbackRestoreStatus.RANG, S + 15_000),
            RestoreInfo(FallbackRestoreStatus.DISMISSED, S + 15_000, S + 16_000),
        )
        for (i in infos) assertUnchanged(st, TripEngine.restore(st, t, i), "restore $i")
        // Same through the snapshot: decode does not check C16 (§5 C16), the next Step does not normalize an ENDED state.
        val decoded = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(st))
        assertEquals(S + 60_000, decoded.alarm.snoozeUntilMs)
        assertUnchanged(decoded, TripEngine.reduce(decoded, Tick(t)), "decoded reduce")
        assertUnchanged(decoded, TripEngine.restore(decoded, t, RestoreInfo(FallbackRestoreStatus.MISSING)), "decoded restore")
    }

    @Test
    fun `T12T C16 a non-ENDED state with a stale snoozeUntilMs is normalized by the next Step`() {
        // Contrast case: TRACKING with snoozeUntilMs = S + 60 000 (impossible from the engine, possible from a hand-made snapshot).
        val st0 = trackingState(d = 20_000.0)
        val st = st0.copy(alarm = st0.alarm.copy(snoozeUntilMs = S + 60_000))
        val s = TripEngine.reduce(TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(st)), Tick(S + 5_000))
        assertNull(s.view.snoozeUntilMs)
        assertNull(s.state.alarm.snoozeUntilMs)
        assertEquals(TripPhase.TRACKING, s.view.phase)
    }

    // ---------------------------------------------------------------- parseOverrides blank set (Remote Config string)

    @Test
    fun `T12T C12 parseOverrides blank set is Kotlin isBlank (isWhitespace or isSpaceChar)`() {
        // Blank → defaults, malformed = false.
        val blank = listOf(
            "", " ", "\t", "\n", "\r\n", "\u000B", "\u000C", "\u001C", "\u001D", "\u001E", "\u001F",
            "\u00A0", "\u1680", "\u2000", "\u2007", "\u200A", "\u2028", "\u2029", "\u202F", "\u205F", "\u3000",
            " \u00A0\t\u3000\n",
        )
        for (s in blank) {
            val r = EngineParamsFactory.parseOverrides(s)
            assertFalse(r.malformed, "blank U+" + s.map { it.code.toString(16) })
            assertTrue(r.rejected.isEmpty())
            assertEquals(EngineParams(), r.params)
        }
        // Not blank → handed to MiniJson, which rejects it → defaults, malformed = true.
        val notBlank = listOf("\u200B", "\uFEFF", "\u0085", "\u180E", "\u2060", "\u0000", " \u200B ")
        for (s in notBlank) {
            val r = EngineParamsFactory.parseOverrides(s)
            assertTrue(r.malformed, "not blank U+" + s.map { it.code.toString(16) })
            assertEquals(EngineParams(), r.params)
        }
        // Around a valid object only RFC 8259 whitespace (space, tab, LF, CR) is allowed.
        assertEquals(90, EngineParamsFactory.parseOverrides(" \t\r\n{\"gpsLostMinS\":90}\n ").params.gpsLostMinS)
        for (pad in listOf("\u00A0", "\u3000", "\u000B", "\u000C", "\u2028", "\uFEFF")) {
            val r = EngineParamsFactory.parseOverrides(pad + "{\"gpsLostMinS\":90}")
            assertTrue(r.malformed, "pad U+" + pad[0].code.toString(16))
            assertEquals(60, r.params.gpsLostMinS)
        }
        // null is the same as blank.
        assertFalse(EngineParamsFactory.parseOverrides(null).malformed)
    }


    // ---------------------------------------------------------------- spec gaps found by the tester (pinned, see report)

    /** Repro base for GAP-1/GAP-2: TRACKING, established, closing 12.5 m/s (k 1.2), one DENSE fix at S, tier SPARSE, then no fix. */
    private fun lostTrip(t0S: Int): EngineDriver =
        driverFrom(trackingState(d = 1000.0 + 12.5 * t0S, tier = SamplingTier.SPARSE, policyAtFix = 5))

    /**
     * GAP-1 (T10 §4.5 lostAt vs §4.5 alarmReason, §4.15): lostAt = atTime(gpsLostAlarmEtaS) is the instant etaS == 1200, but the
     * alarm needs etaS < 1200. A Tick exactly at predictedAlarmAtMs therefore does not alarm, predicted becomes == now and every
     * wakeAt candidate is <= now: TRACKING with wakeAtMs == null. A platform that only ticks at wakeAtMs (Doze, T10 §2.6) never
     * gets another engine Step; only the fallback OS alarm (P + 30 s) wakes the user. Pinned as current (spec-literal) behaviour:
     * flip this test when the designer closes the gap.
     */
    @Test
    fun `T12T GAP-1 GPS lost, Tick exactly at predicted does not alarm and leaves TRACKING without wakeAtMs`() {
        val e = lostTrip(3610)
        e.tick(10) // T = 3600 → MEDIUM, lostAfterS = 90
        assertEquals(GpsLostCause.NO_FIX_TIMEOUT, e.tick(90).events.filterIsInstance<GpsLost>().single().cause)
        assertEquals(S + 2_510_000, e.view.predictedAlarmAtMs)
        // The platform ticks only at wakeAtMs (Doze, T10 §2.6): c4 (P − 900 s), c3 (P − 600 s), c8 (fb − 90 s), then c3 = P.
        val wakes = ArrayList<Long>()
        while (e.view.wakeAtMs != null && e.events().none { it is Alarm }) {
            wakes += e.view.wakeAtMs!! - S
            e.tickMs(e.view.wakeAtMs!!)
        }
        assertEquals(listOf(1_610_000L, 1_910_000L, 2_450_000L, 2_510_000L), wakes) // + c8 = fb − 90 s
        val s = e.last
        assertEquals(TripPhase.TRACKING, s.view.phase)
        assertEquals(GpsStatus.LOST, s.view.gps)
        assertTrue(s.events.isEmpty())
        assertEquals(S + 2_510_000, s.view.predictedAlarmAtMs) // == now
        assertNull(s.view.wakeAtMs) // GAP: no further Step requested while TRACKING
        assertEquals(S + 2_540_000, s.view.fallbackAtMs) // only the OS fallback remains (P + 30 s)
        // One more Tick (CPU awake, <= 60 s) alarms: etaS < 1200.
        assertEquals(AlarmReason.GPS_LOST, e.tickMs(S + 2_515_000).events.filterIsInstance<Alarm>().single().reason)
    }

    /**
     * GAP-2 (T10 §4.8 vs §4.12 step order and the §4.12 property "reduce(s, Tick(s.nowMs)) emits nothing"): GpsMonitor (step 4)
     * uses the policy before SamplingPlanner (step 9). When step 9 shortens the interval (SPARSE → MEDIUM here; also any → DENSE on
     * an alarm), a fix that is already older than the new lostAfterS is not reported lost in this Step, and wakeAt c2 (computed
     * with the new policy) is already in the past, so it is dropped. A Tick at the same now then emits GpsLost (property broken),
     * and with wakeAt-only ticking the GPS_LOST alarm comes 195 s later than with 5 s ticks.
     */
    @Test
    fun `T12T GAP-2 policy shortened in the same Step defers GpsLost and the GPS_LOST alarm`() {
        val e = lostTrip(3700)
        val s = e.tick(100) // age 100 s: lostAfterS was 540 (SPARSE) at step 4, is 90 (MEDIUM) after step 9
        assertEquals(SamplingTier.MEDIUM, s.view.samplingPolicy!!.tier)
        assertTrue(s.events.none { it is GpsLost })
        assertEquals(GpsStatus.OK, s.view.gps)
        val again = TripEngine.reduce(s.state, Tick(s.state.nowMs))
        assertEquals(GpsLost(S + 100_000, GpsLostCause.NO_FIX_TIMEOUT, 100), again.events.first()) // §4.12 property broken
        assertEquals(S + 2_800_000, s.view.wakeAtMs) // c4 predicted − 900 s; c2 (S + 90 000) dropped
        // wakeAt-only platform: GpsLost and Alarm(GPS_LOST) together at 2 800 s.
        val w = e.tickMs(s.view.wakeAtMs!!)
        assertTrue(w.events.any { it is GpsLost })
        assertEquals(AlarmReason.GPS_LOST, w.events.filterIsInstance<Alarm>().single().reason)
        // 5 s ticks: GpsLost at 105 s, Alarm(GPS_LOST) at 2 605 s.
        val f = lostTrip(3700)
        var t = 0
        var lostT = -1
        var alarmT = -1
        while (alarmT < 0 && t < 4000) {
            t += 5
            val st = f.tick(t)
            if (lostT < 0 && st.events.any { it is GpsLost }) lostT = t
            if (st.events.any { it is Alarm }) alarmT = t
        }
        assertEquals(105, lostT)
        assertEquals(2605, alarmT)
    }

    // ---------------------------------------------------------------- seeded property fuzz

    private class Fuzz(seed: Long) {
        var x = seed xor 0x5DEECE66DL

        fun next(): Long { // splitmix64, deterministic on every JVM
            x += -0x61c8864680b583ebL
            var z = x
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }

        fun int(n: Int): Int = ((next() ushr 1) % n).toInt()

        fun dbl(): Double = (next() ushr 11).toDouble() / (1L shl 53).toDouble()

        fun chance(p: Double): Boolean = dbl() < p
    }

    /** Violations found by the fuzz: "GAP-1"/"GAP-2" are the pinned spec gaps above, anything else is a defect. */
    private class Findings {
        val counts = sortedMapOf<String, Int>()
        val firstOf = sortedMapOf<String, String>()

        fun add(kind: String, where: String) {
            counts[kind] = (counts[kind] ?: 0) + 1
            if (kind !in firstOf) firstOf[kind] = where
        }

        fun defects(): Map<String, String> = firstOf.filterKeys { !it.startsWith("GAP-") }
    }

    private fun checkStep(prev: EngineState, s: Step, where: String, f: Findings) {
        fun fail(kind: String, cond: Boolean) { if (!cond) f.add(kind, where) }
        fail("finite", Checks.finiteStateViolation(s.state) == null)
        fail("C16", (s.view.phase == TripPhase.SNOOZED) == (s.view.snoozeUntilMs != null))
        val enc = TripEngine.encodeSnapshot(s.state)
        val dec = TripEngine.decodeSnapshot(enc)
        fail("snapshot round-trip", s.state == dec && enc == TripEngine.encodeSnapshot(dec))
        val ph = s.view.phase
        val active = ph == TripPhase.ACQUIRING || ph == TripPhase.TRACKING
        if (active) {
            // Wake-up safety net: while the engine has not alarmed, a backup OS alarm is always requested.
            fail("active without fallback target", s.state.fallback.targetAtMs != null)
            fail("active without predicted", s.view.predictedAlarmAtMs != null)
        }
        val w = s.view.wakeAtMs
        if (ph == TripPhase.ENDED) {
            fail("ENDED with wakeAt", w == null)
        } else if (w == null) {
            val gap1 = active && s.view.predictedAlarmAtMs == s.state.nowMs && s.events.none { it is Alarm }
            f.add(if (gap1) "GAP-1" else "wakeAt null while ${ph.name}", where)
        } else {
            fail("wakeAt not after now", w > s.state.nowMs)
        }
        if (s.events.any { it is Alarm && it.ringNow }) {
            fail("ringNow alarm outside ALARMING/OVERSHOT", ph == TripPhase.ALARMING || ph == TripPhase.OVERSHOT)
            fail("ringNow alarm not ringing", s.state.alarm.ringing)
        }
        if (prev.alarm.atMs != null) fail("first alarm time changed", prev.alarm.atMs == s.state.alarm.atMs)
        if (ph != TripPhase.ENDED) {
            // §4.12 property: reduce(s, Tick(s.nowMs)) emits nothing (basis of I8).
            val again = TripEngine.reduce(s.state, Tick(s.state.nowMs))
            if (again.events.isNotEmpty()) {
                val shrunk = (s.state.policy?.intervalS ?: 0) < (prev.policy?.intervalS ?: Int.MAX_VALUE)
                val gap2 = shrunk && again.events.any { it is GpsLost && it.cause == GpsLostCause.NO_FIX_TIMEOUT }
                f.add(if (gap2) "GAP-2" else "Tick(now) emitted ${again.events.map { it.javaClass.simpleName }}", where)
            }
        }
    }

    /** One random trip; returns the final state. Fully deterministic for a seed. */
    private fun fuzzTrip(seed: Long, f: Findings, inputs: MutableList<String>? = null): EngineState {
        val r = Fuzz(seed)
        val mode = AlarmMode.entries[r.int(3)]
        val config = TripConfig(
            "fuzz-$seed", 0.0, 106.0, mode,
            if (mode == AlarmMode.DISTANCE || r.chance(0.3)) 200 + r.int(9801) else null,
            if (mode == AlarmMode.TIME || (mode != AlarmMode.DISTANCE && r.chance(0.3))) 5 + r.int(56) else null,
            r.chance(0.7), VehicleKind.entries[r.int(4)],
        )
        var step = TripEngine.start(config, EngineParams(), S)
        checkStep(step.state, step, "seed=$seed START", f)
        var t = S
        var d = 2_000.0 + r.dbl() * 120_000.0
        val v = 3.0 + r.dbl() * 25.0
        var lastFb: Long? = step.state.fallback.targetAtMs
        val n = 300 + r.int(500)
        for (i in 0 until n) {
            val prev = step.state
            if (prev.phase == TripPhase.ENDED) break
            val dt = when (r.int(10)) {
                0 -> 0L
                1 -> -(r.int(30_000)).toLong() // clock jumps back (input atMs < state now)
                2 -> 60_000L + r.int(1_200_000)
                else -> 1_000L + r.int(30_000)
            }
            t += dt
            val k = r.int(100)
            val x: EngineInput = when {
                k < 55 -> {
                    d = (d - v * (maxOf(dt, 0L) / 1000.0) * (0.5 + r.dbl())).coerceAtLeast(-3_000.0)
                    var dd = kotlin.math.abs(d)
                    if (r.chance(0.08)) dd += 5_000.0 * (r.dbl() - 0.3) // GPS jump
                    dd = dd.coerceAtLeast(0.0)
                    val p = TestGeo.jitter(TestGeo.pointOnMeridian(DEST, dd), (r.dbl() - 0.5) * 40.0, 0.0)
                    val acc = if (r.chance(0.15)) 100.0 + r.dbl() * 2_000.0 else 3.0 + r.dbl() * 30.0
                    val age = if (r.chance(0.1)) r.int(200_000).toLong() else r.int(3_000).toLong()
                    val spd = when (r.int(4)) { 0 -> null; 1 -> 0.0; else -> v * (0.5 + r.dbl()) }
                    LocationFix(t, t - age, p.lat, p.lng, acc, spd)
                }
                k < 75 -> Tick(t)
                k < 79 -> BatterySample(t, r.int(101), r.chance(0.2))
                k < 82 -> LocationAvailability(t, AvailabilityCause.entries[r.int(3)])
                k < 88 -> FallbackScheduled(t, if (r.chance(0.8) && lastFb != null) lastFb else t + r.int(3_600_000), r.chance(0.85))
                k < 90 -> FallbackFired(t, t - r.int(60_000))
                k < 93 -> AlarmSilenced(t, t)
                else -> {
                    val a = UserActionKind.entries[r.int(UserActionKind.entries.size)]
                    // DISMISS / STOP rarely, so most trips run long.
                    if ((a == UserActionKind.DISMISS || a == UserActionKind.STOP_TRIP) && !r.chance(0.15)) Tick(t) else UserAction(t, a)
                }
            }
            val label: String
            step = if (r.chance(0.03)) {
                // Process restart mid-trip: snapshot → restore with a random OS status.
                val st = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(prev))
                val status = FallbackRestoreStatus.entries[r.int(5)]
                val fired = if (status == FallbackRestoreStatus.RANG || status == FallbackRestoreStatus.DISMISSED) t - r.int(60_000) else null
                val dismissed = if (status == FallbackRestoreStatus.DISMISSED) t else null
                label = "RESTORE $status"
                TripEngine.restore(st, t, RestoreInfo(status, fired, dismissed))
            } else {
                label = x.toString()
                TripEngine.reduce(prev, x)
            }
            inputs?.add(label)
            checkStep(prev, step, "seed=$seed i=$i after $label", f)
            lastFb = step.state.fallback.targetAtMs ?: lastFb
        }
        return step.state
    }

    @Test
    fun `T12T fuzz 1000 seeded trips keep the safety invariants at every Step (only the pinned gaps occur)`() {
        val f = Findings()
        var steps = 0
        for (seed in 1L..1000L) {
            val tr = ArrayList<String>()
            fuzzTrip(seed, f, tr)
            steps += tr.size
        }
        assertTrue(steps > 50_000) { "fuzz too small: $steps" }
        assertTrue(f.defects().isEmpty()) { "defects: ${f.defects()} counts=${f.counts}" }
        File(System.getProperty("napstop.outDir") ?: "build/napstop", "tester-fuzz.txt").also { it.parentFile.mkdirs() }
            .writeText("steps=$steps counts=${f.counts}\nfirst=${f.firstOf}\n")
    }

    @Test
    fun `T12T fuzz is deterministic`() {
        for (seed in listOf(7L, 77L, 777L)) {
            val a = fuzzTrip(seed, Findings())
            val b = fuzzTrip(seed, Findings())
            assertEquals(TripEngine.encodeSnapshot(a), TripEngine.encodeSnapshot(b))
        }
    }

    /**
     * Liveness (Doze model, T10 §2.6): after any fuzz prefix the platform delivers only Ticks at view.wakeAtMs and the OS fallback
     * alarm (FallbackFired at fallbackAtMs when the status is not FAILED); no fix, nobody answers. Something must ring no later
     * than deadline + fallbackLagS, and the trip must then end (MISSED) after alarmMaxActiveS.
     */
    @Test
    fun `T12T liveness with wakeAt ticks and the OS fallback something rings before the deadline and the trip ends`() {
        var viaFallback = 0
        for (seed in 1L..200L) {
            val s0 = fuzzTrip(seed, Findings())
            if (s0.phase == TripPhase.ENDED) continue
            var step = TripEngine.reduce(s0, Tick(s0.nowMs))
            var rang = s0.alarm.atMs != null || step.events.any { it is Alarm }
            val deadline = s0.startedAtMs + s0.maxTripDurationS * 1000L + s0.params.fallbackLagS * 1000L
            var guard = 0
            while (step.state.phase != TripPhase.ENDED) {
                val now = step.state.nowMs
                val fb = step.state.fallback.targetAtMs?.takeIf { step.state.fallback.status != FallbackStatus.FAILED }
                val w = step.view.wakeAtMs
                val next = listOfNotNull(w, fb?.coerceAtLeast(now)).minOrNull()
                assertNotNull(next, "seed=$seed: nothing will ever run again in ${step.state.phase}")
                if (!rang) assertTrue(now <= deadline, "seed=$seed still silent after the deadline")
                step = if (fb != null && next == fb.coerceAtLeast(now) && (w == null || fb <= w)) {
                    viaFallback++
                    rang = true
                    TripEngine.reduce(step.state, FallbackFired(next!!, fb))
                } else {
                    TripEngine.reduce(step.state, Tick(next!!))
                }
                if (step.events.any { it is Alarm }) rang = true
                if (++guard > 20_000) error("seed=$seed: no end after 20 000 wake-ups")
            }
            assertTrue(rang, "seed=$seed ended without any alarm")
        }
        assertTrue(viaFallback >= 0)
    }
}
