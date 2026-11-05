package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AlarmSource
import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SnapshotFormatException
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.distanceM
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.Transcript
import app.napstop.core.trip.isGapFix
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.policyFor
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.LatLng
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.SplitMix64
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * T10.7 (T10 mục cuối "T10.7", C30; RK24): the GPS-gap chord is also taken after an alarm (ALARMING/SNOOZED,
 * overshootAtMs == null), only for the usual overshoot rule (increasing && fast, PO #18). U127 (a)–(l) of T10 "T10.7" §9.1.
 * T10.7 round 2 (C31, Q14 = A): after the alarm the chord only proves "came near" (alarmedChordD → nearD); "moved away 1 km" is
 * measured from minD (observed fixes). U127 (m), (n) and U129 (codec) of "T10.7 vòng 2" §7.
 * Builder `gapState` = the U114 (a) builder (T105GapTest `reproState`) after a GPS_LOST alarm rang in the gap, 15 min before n.
 * Report: `u127.txt` (times relative to n, pastM, the isGapFix truth table; no coordinates), lines sorted by case.
 */
class T107Test {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val n = S + 3_600_000L

    // ---------------------------------------------------------------- builders (as T105GapTest U114)

    /** Point [south] m south (negative = north) and [east] m east of the destination. */
    private fun pt(south: Double, east: Double = 0.0): LatLng {
        val p0 = TestGeo.pointOnMeridian(DEST, south)
        return if (east == 0.0) p0 else TestGeo.jitter(p0, east, 0.0)
    }

    /** U114 (a) builder (T105GapTest `reproState`): GPS lost since n − [gapS] s, dead reckoning still 11.8 km out at 10 m/s. */
    private fun reproState(config: TripConfig = cfg(AlarmMode.DISTANCE, thr = 1000), gapS: Int = 1_761): EngineState {
        val dr = 11_800.0 + 10.0 * gapS
        return trackingState(
            config, d = dr, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000, lastFixAt = n - gapS * 1000L,
            tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
            fallback = FallbackState(n + 29_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, true),
        )
    }

    private fun alarmed(ringing: Boolean, at: Long = n - 900_000, reason: AlarmReason = AlarmReason.GPS_LOST): AlarmState =
        AlarmState(at, reason, AlarmSource.ENGINE, at, reason, ringing, 0, null, null)

    /** U127 builder: [phase] after a GPS_LOST alarm at n − 900 s (chime stopped when ![ringing]); fallback cleared. */
    private fun gapState(phase: TripPhase = TripPhase.ALARMING, ringing: Boolean = false): EngineState =
        reproState().copy(phase = phase, alarm = alarmed(ringing), fallback = FallbackState.CLEARED)

    /** One fix of a sequence: time, metres south (negative = north), metres east, Doppler speed, accuracy. */
    private class Fx(val at: Long, val south: Double, val east: Double, val spd: Double?, val acc: Double = 8.0)

    private fun locFix(f: Fx): LocationFix {
        val p = pt(f.south, f.east)
        return LocationFix(f.at, f.at, p.lat, p.lng, f.acc, f.spd)
    }

    /** Feeds every fix of [fixes] from [st] (stops at ENDED); returns every Step. */
    private fun drive(st: EngineState, fixes: List<Fx>): List<Step> {
        val out = ArrayList<Step>()
        var s = st
        for (f in fixes) {
            if (s.phase == TripPhase.ENDED) break
            val step = TripEngine.reduce(s, locFix(f))
            out += step
            s = step.state
        }
        return out
    }

    /** U114 (a) `away`: a fix every 5 s from n, moving away north from [past] m beyond the destination at [v] m/s; 120 s by default. */
    private fun away(past: Double = 3_100.0, v: Double = 18.0, count: Int = 25, firstSpd: Double? = v): List<Fx> =
        (0 until count).map { i -> Fx(n + 5_000L * i, -(past + v * 5.0 * i), 0.0, if (i == 0) firstSpd else v) }

    private fun events(steps: List<Step>) = steps.flatMap { it.events }

    /** Index of the first Step with an event of type [T], or -1. */
    private inline fun <reified T> firstIdx(steps: List<Step>): Int = steps.indexOfFirst { s -> s.events.any { it is T } }

    /** I1 (no Alarm(ringNow) while the previous still rings), I6, I11, I12, I13, C16 on a Step sequence from [st0]. */
    private fun invariants(st0: EngineState, steps: List<Step>, tag: String) {
        var prev = st0
        for (s in steps) {
            val alarms = s.events.filterIsInstance<Alarm>()
            assertTrue(alarms.size <= 1, "$tag I11 ${s.events}")
            assertTrue(s.events.count { it is FallbackAlarmChanged } <= 1, "$tag I12 ${s.events}")
            for (a in alarms) assertTrue(!a.ringNow || !prev.alarm.ringing, "$tag I1 at ${rel(s)}")
            assertNull(Checks.i13Violation(s.view), "$tag I13 at ${rel(s)}")
            assertEquals(s.view.snoozeUntilMs != null, s.view.phase == TripPhase.SNOOZED, "$tag C16 at ${rel(s)}")
            prev = s.state
        }
        assertTrue(events(steps).count { it is Overshoot } <= 1, "$tag I6")
    }

    private fun rel(s: Step): Double = (s.state.nowMs - n) / 1000.0

    private fun note(key: String, text: String) {
        synchronized(LOG) {
            LOG[key] = text
            File(outDir, "u127.txt").writeText(LOG.entries.joinToString("\n", postfix = "\n") { "${it.key}: ${it.value}" })
        }
    }

    /** Index and pastM of the first Overshoot (asserted present). */
    private fun overshootAt(steps: List<Step>, tag: String): Pair<Int, Int> {
        val i = firstIdx<Overshoot>(steps)
        assertTrue(i >= 0, "$tag: no Overshoot")
        return i to steps[i].events.filterIsInstance<Overshoot>().single().pastM
    }

    // ---------------------------------------------------------------- (a) (b) (c)

    @Test
    fun `U127 a b c after a GPS_LOST alarm the chord proves came near and the usual overshoot rule re-rings, Overshoot only, or supersedes the snooze`() {
        // (a) ALARMING, the chime stopped by itself. T10.7 round 2 (C31): minD stays observed, the chord goes to alarmedChordD.
        val a0 = gapState(ringing = false)
        val a = drive(a0, away())
        invariants(a0, a, "a")
        val first = a.first()
        assertTrue(first.events.any { it is GpsRecovered }, "a first fix ${first.events}")
        assertTrue(first.events.none { it is Alarm || it is Overshoot }, "a first fix ${first.events}")
        assertTrue(first.state.minD!! >= 3_099.0, "a minD ${first.state.minD} (not lowered by the chord)")
        assertTrue(first.state.alarmedChordD!! <= 1.0, "a alarmedChordD ${first.state.alarmedChordD}")
        assertTrue(!first.state.minDChord, "a minDChord")
        assertNull(first.state.stopStartMs, "a stopStartMs as before the Step")
        assertNull(first.state.passAnchorD, "a passAnchorD")
        val (ia, pastA) = overshootAt(a, "a")
        assertEquals(n + U127_AT_MS, a[ia].state.nowMs, "a: Overshoot once dSmooth − minD (observed) >= 1 000")
        assertEquals(U127_PAST_M, pastA, "a pastM")
        val alA = a[ia].events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.OVERSHOOT, alA.reason)
        assertTrue(alA.ringNow, "a re-ring")
        assertEquals(1, events(a).count { it is Alarm }, "a: one Alarm")
        assertTrue(events(a).none { it is FallbackAlarmChanged }, "a: ${events(a).filterIsInstance<FallbackAlarmChanged>()}")
        assertEquals(TripPhase.OVERSHOT, a.last().state.phase)
        note("a", "Alarm(OVERSHOOT, ringNow=true)+Overshoot at n+${rel(a[ia])} s pastM=$pastA")

        // (b) ALARMING, the chime still rings: Overshoot only (screen 8), no double ring.
        val b0 = gapState(ringing = true)
        val b = drive(b0, away())
        invariants(b0, b, "b")
        val (ib, pastB) = overshootAt(b, "b")
        assertEquals(ia, ib, "b: same Step as (a)")
        assertEquals(pastA, pastB, "b pastM")
        assertTrue(events(b).none { it is Alarm }, "b: ${events(b).filterIsInstance<Alarm>()}")
        assertEquals(TripPhase.OVERSHOT, b.last().state.phase)
        assertTrue(b.last().state.alarm.ringing, "b: still ringing")
        note("b", "Overshoot only at n+${rel(b[ib])} s pastM=$pastB")

        // (c) SNOOZED until n + 120 s (T10.7 round 2: the re-ring is at n + 65 s, so the snooze is longer than in round 1 to keep
        // the intent: still SNOOZED at the overshoot): Alarm(OVERSHOOT) + Overshoot + SUPERSEDED, no SNOOZE_END later.
        val p = EngineParams()
        val until = n + 120_000
        val c0 = gapState(TripPhase.SNOOZED).copy(
            alarm = alarmed(false).copy(snoozeCount = 1, snoozeUntilMs = until),
            fallback = FallbackState(until + p.fallbackLagS * 1000L, n - 300_000, FallbackStatus.CONFIRMED, n - 299_000, false, false),
        )
        val c = drive(c0, away(count = 30))
        invariants(c0, c, "c")
        val (ic, pastC) = overshootAt(c, "c")
        assertEquals(ia, ic, "c: same Step as (a)")
        assertEquals(pastA, pastC, "c pastM")
        val sc = c[ic]
        assertTrue(sc.state.nowMs < until)
        val alC = sc.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.OVERSHOOT, alC.reason)
        assertTrue(alC.ringNow)
        val facC = sc.events.filterIsInstance<FallbackAlarmChanged>().single()
        assertNull(facC.fallbackAtMs)
        assertEquals(FallbackCause.SUPERSEDED, facC.cause)
        assertEquals(TripPhase.OVERSHOT, sc.state.phase)
        assertNull(sc.state.alarm.snoozeUntilMs, "c snoozeUntilMs (C16)")
        assertTrue(events(c).none { it is Alarm && it.reason == AlarmReason.SNOOZE_END }, "c: no SNOOZE_END")
        assertTrue(c.last().state.nowMs > until, "c: driven past snoozeUntil")
        note("c", "SNOOZED: Alarm(OVERSHOOT, ringNow=true)+Overshoot+SUPERSEDED at n+${rel(sc)} s pastM=$pastC")
    }

    // ---------------------------------------------------------------- (d)

    @Test
    fun `U127 d a vehicle parked beyond the destination after the chime stopped does not re-ring, MISSED after alarmMaxActiveS`() {
        val p = EngineParams()
        val st0 = gapState(ringing = false)
        val endAt = st0.alarm.lastRingAtMs!! + p.alarmMaxActiveS * 1000L
        val count = ((endAt + 10_000 - n) / 5_000).toInt() + 1
        // (d1) Doppler 0, acc 8; (d2) acc 80, no Doppler, repeated coordinates (U114 q). First fix as (a).
        for ((tag, acc, spd) in listOf(Triple<String, Double, Double?>("d1", 8.0, 0.0), Triple<String, Double, Double?>("d2", 80.0, null))) {
            val fixes = (0 until count).map { i -> if (i == 0) Fx(n, -3_100.0, 0.0, 18.0) else Fx(n + 5_000L * i, -3_100.0, 0.0, spd, acc) }
            val steps = drive(st0, fixes)
            invariants(st0, steps, tag)
            assertTrue(events(steps).none { it is Alarm || it is Overshoot }, "$tag: ${events(steps).filter { it is Alarm || it is Overshoot }}")
            val iEnd = firstIdx<TripEnded>(steps)
            assertTrue(iEnd >= 0, "$tag: no TripEnded")
            assertTrue(steps.subList(0, iEnd).all { !it.state.minDChord && it.state.alarmedChordD!! <= 1.0 }, "$tag: alarmedChordD until the end")
            val te = steps[iEnd].events.filterIsInstance<TripEnded>().single()
            assertEquals(TripOutcome.MISSED, te.outcome, tag)
            assertEquals(EndReason.ALARM_UNANSWERED, te.endReason, tag)
            assertEquals(endAt, steps[iEnd].state.nowMs, "$tag: the first Step at or after lastRingAtMs + alarmMaxActiveS")
            note(tag, "parked 3 100 m beyond: no Alarm, no Overshoot; TripEnded(MISSED, ALARM_UNANSWERED) at n+${rel(steps[iEnd])} s")
        }
    }

    // ---------------------------------------------------------------- (e)

    /** U114 (i) geometry: fix before the gap 20 km south, 700 s gap; ALARMING after GPS_LOST, chime stopped. */
    private fun bypassState(): EngineState {
        val lp = pt(20_000.0)
        val ld = distanceM(lp.lat, lp.lng, DEST.lat, DEST.lng)
        val base = trackingState(
            cfg(AlarmMode.DISTANCE, thr = 1000), d = ld, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000,
            lastFixAt = n - 700_000, tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
        )
        val l = FixRec(n - 700_000, lp.lat, lp.lng, 8.0, ld, null)
        return base.copy(
            last = l, recent = listOf(l), dSmooth = ld, minD = ld, last3 = listOf(ld), dStartM = ld + 20_000.0,
            phase = TripPhase.ALARMING, alarm = alarmed(false), fallback = FallbackState.CLEARED,
        )
    }

    /** Signed distance along the bypass line (from 2 km north / 0.5 km east through the destination): > 0 before it. */
    private val d0 = kotlin.math.sqrt(2_000.0 * 2_000.0 + 500.0 * 500.0)

    private fun lineFix(at: Long, r: Double, spd: Double): Fx = Fx(at, -2_000.0 * r, 500.0 * r, spd)

    @Test
    fun `U127 e bypass entering from the far side after an alarm - no Overshoot while approaching or standing, re-ring once really past`() {
        val st0 = bypassState()
        // (e1) approach at 10 m/s through the destination, then away on the same line.
        val e1Fixes = (0 until 200).map { i -> lineFix(n + 5_000L * i, 1.0 - 10.0 * 5.0 * i / d0, if (i == 0) 30.0 else 10.0) }
        val e1 = drive(st0, e1Fixes)
        invariants(st0, e1, "e1")
        assertTrue(!e1.first().state.minDChord && e1.first().state.alarmedChordD!! < 1_000.0, "e1 chord ${e1.first().state.alarmedChordD}")
        val chordMinD = e1.first().state.alarmedChordD!!
        val passI = e1Fixes.indexOfFirst { it.south > 0.0 } // first fix beyond the destination
        val (io, past) = overshootAt(e1, "e1")
        assertTrue(io > passI, "e1: Overshoot at fix $io before passing the destination (fix $passI)")
        val alarm = e1[io].events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.OVERSHOOT, alarm.reason)
        assertTrue(alarm.ringNow)
        val minD = e1[io].state.minD!!
        assertTrue(minD < chordMinD, "e1: minD observed ($minD) below the chord ($chordMinD)")
        assertTrue(e1[io].state.dSmooth!! - minD >= 1_000.0)
        assertEquals(U127_E1_FIX, io, "e1: fix index of the Overshoot")
        note("e1", "chord minD=${chordMinD.toInt()} passed at fix $passI; Overshoot+Alarm(OVERSHOOT, ringNow=true) at fix $io (n+${rel(e1[io])} s) pastM=$past")

        // (e2) as (e1), but the vehicle stands 2 minutes at the first fix before driving on (U114 v rang a wrong OVERSHOOT in TRACKING).
        val stand = (0 until 24).map { i -> lineFix(n + 5_000L * i, 1.0, if (i == 0) 30.0 else 0.0) }
        val go = (0 until 200).map { i -> lineFix(n + 120_000L + 5_000L * i, 1.0 - 10.0 * 5.0 * (i + 1) / d0, 10.0) }
        val e2Fixes = stand + go
        val e2 = drive(st0, e2Fixes)
        invariants(st0, e2, "e2")
        val passI2 = e2Fixes.indexOfFirst { it.south > 0.0 }
        val io2 = firstIdx<Overshoot>(e2)
        assertTrue(io2 < 0 || io2 > passI2, "e2: Overshoot at fix $io2 while standing / approaching (passed at $passI2)")
        assertEquals(U127_E2_FIX, io2, "e2: fix index of the Overshoot (measured)")
        assertTrue(e2[io2].events.any { it is Alarm && it.reason == AlarmReason.OVERSHOOT && it.ringNow }, "e2: re-ring with the Overshoot")
        note("e2", "stand 120 s then approach: no Overshoot before passing (fix $passI2); first Overshoot at fix $io2" +
            (if (io2 >= 0) " (n+${rel(e2[io2])} s)" else ""))
    }

    // ---------------------------------------------------------------- (f)

    @Test
    fun `U127 f process killed in the gap, restore RANG - after AlarmSilenced as (a), else as (b), snapshot round trip keeps the chord`() {
        val ref = drive(gapState(ringing = false), away())
        val (ia, pastA) = overshootAt(ref, "a")
        val snap = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(reproState()))
        val r = TripEngine.restore(snap, n - 60_000, RestoreInfo(FallbackRestoreStatus.RANG, n - 360_000))
        val fb = r.events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.FALLBACK, fb.reason)
        assertTrue(!fb.ringNow)
        assertTrue(r.events.none { it is GpsLost }, "f: already LOST ${r.events}")
        assertTrue(r.state.alarm.ringing)

        // (f1) the OS ring stopped by itself: AlarmSilenced, then = (a).
        val s1 = TripEngine.reduce(r.state, AlarmSilenced(n - 59_000, n - 60_000))
        assertTrue(!s1.state.alarm.ringing)
        val f1 = drive(s1.state, away())
        invariants(s1.state, f1, "f1")
        val (i1, past1) = overshootAt(f1, "f1")
        assertEquals(ia, i1, "f1: same Step as (a)")
        assertEquals(pastA, past1, "f1 pastM")
        val al1 = f1[i1].events.filterIsInstance<Alarm>().single()
        assertTrue(al1.reason == AlarmReason.OVERSHOOT && al1.ringNow, "f1 $al1")
        assertEquals(1, events(f1).count { it is Alarm })
        note("f1", "restore RANG + AlarmSilenced: Alarm(OVERSHOOT, ringNow=true)+Overshoot at n+${rel(f1[i1])} s pastM=$past1")

        // (f2) still ringing: = (b).
        val f2 = drive(r.state, away())
        invariants(r.state, f2, "f2")
        val (i2, past2) = overshootAt(f2, "f2")
        assertEquals(ia, i2, "f2: same Step as (a)")
        assertEquals(pastA, past2, "f2 pastM")
        assertTrue(events(f2).none { it is Alarm }, "f2: ${events(f2).filterIsInstance<Alarm>()}")
        note("f2", "restore RANG, still ringing: Overshoot only at n+${rel(f2[i2])} s pastM=$past2")

        // (f3) (a) with a snapshot round trip + restore(PENDING) after the Step at n + 5 s: the same (t, events, view) as (a).
        val fixes = away()
        val head = drive(gapState(ringing = false), fixes.take(2))
        val st = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(head.last().state))
        assertEquals(head.last().state.alarmedChordD, st.alarmedChordD, "f3: alarmedChordD after decode (I8)")
        assertNotNull(st.alarmedChordD)
        val rp = TripEngine.restore(st, n + 5_000, RestoreInfo(FallbackRestoreStatus.PENDING))
        assertTrue(rp.events.isEmpty(), "f3 restore PENDING at now: ${rp.events}")
        val tail = drive(rp.state, fixes.drop(2))
        fun line(s: Step) = "${s.state.nowMs - n} ${s.events.joinToString { Transcript.encodeEvent(it, n) }} ${Transcript.encodeView(s.view, n)}"
        assertEquals(ref.drop(2).map(::line), tail.map(::line), "f3: (t, events, view) as (a)")
        note("f3", "snapshot round trip at n+5 s: ${tail.size} Steps equal to (a)")
    }

    // ---------------------------------------------------------------- (g) (h) (i) (j) (k)

    @Test
    fun `U127 g h i j k not passed, a stop from before the gap kept, OVERSHOT, an IMPLAUSIBLE fix, and the time term`() {
        // (g) same side, 5 000 m (U114 h): no chord (u >= 1), no Overshoot.
        val g0 = gapState(ringing = false)
        val g = TripEngine.reduce(g0, LocationFix(n, n, pt(5_000.0).lat, pt(5_000.0).lng, 8.0, 0.8))
        assertTrue(!g.state.minDChord, "g minDChord")
        assertNull(g.state.alarmedChordD, "g alarmedChordD")
        assertTrue(g.state.minD!! >= 4_999.0, "g minD ${g.state.minD} (not lowered by a chord)")
        assertTrue(g.events.none { it is Overshoot || it is Alarm }, "g ${g.events}")

        // (h) a stop in progress before the gap: kept at the chord fix in ALARMING (decision #2), ended by the first MOVING sample.
        val last = gapState().last!!
        val h0 = gapState(ringing = false).copy(stopStartMs = n - 1_900_000, stopAnchor = last)
        val h = drive(h0, away())
        invariants(h0, h, "h")
        assertEquals(n - 1_900_000, h[0].state.stopStartMs, "h: stop kept at the chord fix")
        assertTrue(h[0].state.minD!! >= 3_099.0 && !h[0].state.minDChord, "h minD ${h[0].state.minD} (not lowered)")
        assertTrue(h[0].state.alarmedChordD!! <= 1.0, "h alarmedChordD ${h[0].state.alarmedChordD}")
        assertNull(h[1].state.stopStartMs, "h: stop ended by the first MOVING sample")
        val hT = reproState().copy(stopStartMs = n - 1_900_000, stopAnchor = last)
        assertNull(TripEngine.reduce(hT, locFix(away().first())).state.stopStartMs, "h control (TRACKING, U114 m): cleared at the chord fix")
        val (ih, pastH) = overshootAt(h, "h")
        note("h", "stop kept at n+0, ended at n+${rel(h[1])} s; Overshoot at n+${rel(h[ih])} s pastM=$pastH")

        // (i) OVERSHOT: no chord fix, no new overshoot event (I6).
        val i0 = gapState(ringing = false).copy(phase = TripPhase.OVERSHOT, overshootAtMs = n - 300_000, overshootPastM = 1_200)
        val i = drive(i0, away())
        assertTrue(i.all { !it.state.minDChord && it.state.alarmedChordD == null }, "i minDChord / alarmedChordD")
        assertTrue(i.first().state.minD!! >= 3_099.0, "i minD ${i.first().state.minD}")
        assertTrue(events(i).none { it is Overshoot || it is Alarm }, "i ${events(i).filter { it is Overshoot || it is Alarm }}")

        // (j) one IMPLAUSIBLE fix in the gap (U114 ad): not a chord fix (round 3f kept in ALARMING), silent for 10 minutes (RK20 d).
        val jump = TripEngine.reduce(gapState(ringing = false), LocationFix(n - 1_000_000, n - 1_000_000, pt(500_000.0).lat, pt(500_000.0).lng, 8.0, 10.0))
        assertEquals(1, jump.state.rejects.size, "j: IMPLAUSIBLE kept in rejects")
        val j = drive(jump.state, away(count = 120))
        assertTrue(j.all { !it.state.minDChord && it.state.alarmedChordD == null }, "j: no chord fix")
        assertTrue(events(j).none { it is Overshoot || it is Alarm }, "j ${events(j).filter { it is Overshoot || it is Alarm }}")

        // (k1) GPS still OK (Doze, no Step in the gap; U114 k): the time term of gapFix makes it a chord fix, as (a).
        val k0 = gapState(ringing = false).copy(gps = GpsStatus.OK, gpsLostAtMs = null, nowMs = n - 1_761_000)
        val k = drive(k0, away())
        invariants(k0, k, "k1")
        assertTrue(k.first().events.none { it is GpsRecovered }, "k1: gps was OK")
        assertTrue(!k.first().state.minDChord && k.first().state.alarmedChordD!! <= 1.0, "k1 alarmedChordD ${k.first().state.alarmedChordD}")
        val (ik, pastK) = overshootAt(k, "k1")
        assertEquals(n + U127_AT_MS, k[ik].state.nowMs, "k1: as (a)")
        assertTrue(k[ik].events.any { it is Alarm && it.reason == AlarmReason.OVERSHOOT && it.ringNow })
        // (k2) Δt = lostAfterS + 1 s exactly (a DISTANCE alarm whose chime stopped; 400 m before → 1 800 m beyond, 36 m/s).
        val k2Cfg = cfg(AlarmMode.DISTANCE, thr = 1000)
        val k2State = trackingState(
            k2Cfg, d = 400.0, ground = 18.0, closing = 18.0, now = n - 61_000, lastFixAt = n - 61_000, tier = SamplingTier.DENSE,
            maxTripS = 14_400, startedAt = n - 3_000_000, phase = TripPhase.ALARMING,
            alarm = alarmed(false, at = n - 120_000, reason = AlarmReason.DISTANCE),
        )
        assertEquals(60, lostAfterS(k2State.params, k2State.policyIntervalAtLastFixS, k2State.policy))
        val k2 = drive(k2State, away(past = 1_800.0))
        invariants(k2State, k2, "k2")
        assertTrue(!k2.first().state.minDChord && k2.first().state.alarmedChordD!! <= 1.0, "k2 alarmedChordD ${k2.first().state.alarmedChordD}")
        val (ik2, pastK2) = overshootAt(k2, "k2")
        assertEquals(n + U127_K2_AT_MS, k2[ik2].state.nowMs, "k2: measured (designer by hand ≈ n + 35 s)")
        assertTrue(k2[ik2].events.any { it is Alarm && it.reason == AlarmReason.OVERSHOOT && it.ringNow })
        note("k", "k1 Overshoot at n+${rel(k[ik])} s pastM=$pastK; k2 (dt = lostAfterS + 1 s) Overshoot at n+${rel(k2[ik2])} s pastM=$pastK2")
    }

    // ---------------------------------------------------------------- (m) (n) T10.7 round 2

    /**
     * U127 (m) (T10.7 round 2 §7, the unit version of U128 L4): after the GPS_LOST alarm (chime stopped) the chord passes through the
     * destination (dChord ≈ 0) while the vehicle drives a loop around it at 3 100 m, 18 m/s, uniform noise ±5 m per axis
     * (splitmix64 seed 127) for 10 minutes; then it heads straight for the destination and 2 km past it. No Overshoot until the
     * vehicle is really past; then Overshoot + Alarm(OVERSHOOT, ringNow=true) within 120 s.
     */
    @Test
    fun `U127 m after an alarm a chord through the destination then a loop around it at 3 100 m - no Overshoot until really past`() {
        val st0 = gapState(ringing = false)
        val rnd = SplitMix64(127)
        val r0 = 3_100.0
        val v = 18.0
        val loopS = 600
        val fixes = ArrayList<Fx>()
        val truth = ArrayList<Double>() // signed distance along the way in: > 0 before the destination
        fun add(atS: Int, x: Double, y: Double, d: Double) {
            val nx = rnd.dbl(-5.0, 5.0)
            val ny = rnd.dbl(-5.0, 5.0)
            fixes += Fx(n + atS * 1000L, -(y + ny), x + nx, v)
            truth += d
        }
        var t = 0
        while (t <= loopS) {
            val th = kotlin.math.PI / 2 - v * t / r0
            add(t, r0 * kotlin.math.cos(th), r0 * kotlin.math.sin(th), r0)
            t += 5
        }
        val thEnd = kotlin.math.PI / 2 - v * loopS / r0
        var k = 1
        while (r0 - v * 5.0 * k >= -2_000.0) {
            val r = r0 - v * 5.0 * k
            add(loopS + 5 * k, r * kotlin.math.cos(thEnd), r * kotlin.math.sin(thEnd), r)
            k++
        }
        val steps = drive(st0, fixes)
        invariants(st0, steps, "m")
        assertTrue(steps.first().state.alarmedChordD!! <= 10.0, "m chord (noise ±5 m) ${steps.first().state.alarmedChordD}")
        val passI = truth.indexOfFirst { it <= 0.0 }
        val io = firstIdx<Overshoot>(steps)
        assertTrue(io > passI, "m: Overshoot at fix $io before the destination was passed (fix $passI, truth ${truth.getOrNull(io)})")
        val dtS = (steps[io].state.nowMs - fixes[passI].at) / 1000.0
        assertTrue(dtS <= 120.0, "m: Overshoot ${dtS} s after passing")
        assertTrue(steps[io].events.any { it is Alarm && it.reason == AlarmReason.OVERSHOOT && it.ringNow }, "m: re-ring")
        val pastM = steps[io].events.filterIsInstance<Overshoot>().single().pastM
        note("m", "loop 600 s at 3 100 m (±5 m): no Overshoot; passed at fix $passI (n+${(fixes[passI].at - n) / 1000} s); " +
            "Overshoot+Alarm(OVERSHOOT, ringNow=true) at fix $io (+${dtS.toInt()} s) pastM=$pastM")
    }

    /** U127 (n) (I8): round trip + restore(PENDING) after every Step of (a) (alarmedChordD in the snapshot) continues as (a). */
    @Test
    fun `U127 n snapshot round trip and restore PENDING after any Step of (a) continues the same (t, events, view)`() {
        val fixes = away()
        val ref = drive(gapState(ringing = false), fixes)
        fun line(s: Step) = "${s.state.nowMs - n} ${s.events.joinToString { Transcript.encodeEvent(it, n) }} ${Transcript.encodeView(s.view, n)}"
        val want = ref.map(::line)
        for (k in 0 until ref.size - 1) {
            val st = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(ref[k].state))
            assertEquals(ref[k].state, st, "n: decode after Step $k")
            val rp = TripEngine.restore(st, st.nowMs, RestoreInfo(FallbackRestoreStatus.PENDING))
            assertTrue(rp.events.isEmpty(), "n restore PENDING at now after Step $k: ${rp.events}")
            assertEquals(want.drop(k + 1), drive(rp.state, fixes.drop(k + 1)).map(::line), "n: after Step $k")
        }
        assertNotNull(ref[1].state.alarmedChordD)
        note("n", "round trip + restore PENDING after each of ${ref.size - 1} Steps: equal to (a)")
    }

    // ---------------------------------------------------------------- U129

    @Test
    fun `U129 alarmedChordD is written right after passAnchorD, round-trips, a missing key reads null and a wrong type fails`() {
        for (chord in listOf<Double?>(null, 4.131000057, 0.1, 5e-324, 1_234.5)) {
            val st = trackingState().copy(passAnchorD = 7.25, alarmedChordD = chord)
            val json = TripEngine.encodeSnapshot(st)
            val lit = chord?.toString() ?: "null"
            assertTrue(json.contains("\"passAnchorD\":7.25,\"alarmedChordD\":$lit,\"last3\""), json.substringAfter("\"passAnchorD\"").take(60))
            val back = TripEngine.decodeSnapshot(json)
            assertEquals(st, back)
            assertEquals(chord?.let { java.lang.Double.doubleToRawLongBits(it) }, back.alarmedChordD?.let { java.lang.Double.doubleToRawLongBits(it) })
            // Third named exception to C20: an older snapshot without the key reads null.
            val without = json.replace(",\"alarmedChordD\":$lit", "")
            assertTrue(!without.contains("alarmedChordD"))
            assertEquals(st.copy(alarmedChordD = null), TripEngine.decodeSnapshot(without))
            for (wrong in listOf("\"1\"", "true", "1e999")) {
                assertThrows(SnapshotFormatException::class.java) {
                    TripEngine.decodeSnapshot(json.replace("\"alarmedChordD\":$lit", "\"alarmedChordD\":$wrong"))
                }
            }
        }
    }

    // ---------------------------------------------------------------- (l)

    /**
     * U127 (l): `isGapFix` truth table (C30), compared with the §2 expression written out here, and `notYet` (only clears the stop).
     * Rows: phase (6) × overshootAtMs {null, set} × alarm.atMs {null, set} × L {null, present} × gps {OK, LOST} × Δt {5 s,
     * lostAfterS}; one line each in `u127.txt` (Swift compares byte for byte).
     */
    @Test
    fun `U127 l isGapFix truth table over phase, overshootAtMs, alarm, L, gps and the time term`() {
        val p = EngineParams()
        val pol = policyFor(SamplingTier.DENSE, p, false)
        val lostS = lostAfterS(p, pol.intervalS, pol)
        val f = FixRec(n, 0.0, DEST.lng, 8.0, 1.0, null)
        val rows = ArrayList<String>()
        var trueRows = 0
        for (phase in TripPhase.entries) for (ov in listOf(null, n - 1L)) for (al in listOf(null, n - 2L)) for (hasL in listOf(false, true)) {
            for (gps in listOf(GpsStatus.OK, GpsStatus.LOST)) for (dtS in listOf(5, lostS)) {
                val l = if (hasL) FixRec(n - dtS * 1000L, -0.01, DEST.lng, 8.0, 1_000.0, null) else null
                val got = isGapFix(phase, ov, gps, l, f, p, pol.intervalS, pol)
                val inPhase = phase == TripPhase.ACQUIRING || phase == TripPhase.TRACKING || phase == TripPhase.ALARMING || phase == TripPhase.SNOOZED
                val want = hasL && inPhase && ov == null && (gps == GpsStatus.LOST || dtS >= lostS)
                val notYet = (phase == TripPhase.ACQUIRING || phase == TripPhase.TRACKING) && al == null
                assertEquals(want, got, "isGapFix phase=$phase overshoot=$ov alarm=$al L=$hasL gps=$gps dt=$dtS")
                if (got) trueRows++
                rows += "phase=${phase.name} overshoot=${if (ov == null) "null" else "set"} alarm=${if (al == null) "null" else "set"} " +
                    "L=${if (hasL) "yes" else "no"} gps=${gps.name} dt=$dtS gapFix=$got notYet=$notYet"
            }
        }
        assertEquals(192, rows.size)
        assertEquals(4 * 2 * 3, trueRows, "gapFix rows: 4 phases × alarm {null, set} × (LOST any dt, OK dt = lostAfterS)")
        note("l", "lostAfterS=$lostS rows=${rows.size} gapFix=$trueRows\n" + rows.joinToString("\n") { "  $it" })
    }

    private companion object {
        /** u127.txt by case key (any test order). */
        val LOG = sortedMapOf<String, String>()

        /**
         * U127 (a): T10.7 round 2 — the re-ring when dSmooth − minD (observed, 3 100) >= 1 000: designer by hand n + 65 s, pastM ≈ 4 180
         * (dSmooth = d(t − 5 s), nearD = alarmedChordD ≈ 0). Round 1: n + 20 s, 3 370.
         */
        const val U127_AT_MS = 65_000L
        const val U127_PAST_M = 4180

        /**
         * U127 (k2): measured n + 5 s (as round 1, pastM 1 890). Designer by hand ≈ n + 35 s assumed minD ≈ d_f; here minD is the
         * observed fix 400 m before the destination (61 s before), so dSmooth − minD = 1 890 − 400 >= 1 000 at the 2nd fix (T12.4 round 3 notes).
         */
        const val U127_K2_AT_MS = 5_000L

        /** U127 (e1): measured index of the Overshoot fix. */
        const val U127_E1_FIX = 63

        /** U127 (e2): measured index of the Overshoot fix (after the destination, review T12.4 nit #3). */
        const val U127_E2_FIX = 86
    }
}
