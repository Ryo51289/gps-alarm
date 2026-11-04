package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.Step
import app.napstop.core.trip.StepWork
import app.napstop.core.trip.TMath
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.estimate
import app.napstop.core.trip.lostAfterS
import app.napstop.core.trip.slowAway
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.estimateOf
import app.napstop.core.trip.support.params
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.updatePassAnchor
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Tester T12.3 (T10.6, Kotlin): cases outside the T10 "T10.6" §7 table — boundaries of W (`gpsLostLongS` floor, `>=`), a real
 * T12.2 snapshot restored by the T10.6 engine in the middle of a long loss, boundaries of the slow-vehicle net (`<=` on accuracy,
 * `>=` on the rise, the open gap), Remote Config values out of range, and the §9 thresholds that the spec writes as numbers.
 */
class TesterT123Test {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }

    private fun alarms(s: Step): List<Alarm> = s.events.filterIsInstance<Alarm>()

    // ============================================================ W: the gpsLostLongS floor, to the millisecond

    /**
     * TRAIN hint (floor 12.73 m/s) but the vehicle really crawls (ground 4.8, closing 4.0), last fix at S, 15 km left: the hint
     * floor makes thS < 0, so lostLongAtS is exactly the floor gpsLostLongS (1 800 s); the ETA rule (cvDr 4) would wait until
     * about S + 2 570 s. Returns the driver after the Step that declared GpsLost.
     */
    private fun crawlLost(p: EngineParams = EngineParams()) = driverFrom(
        trackingState(cfg(AlarmMode.DISTANCE, thr = 1000, hint = VehicleKind.TRAIN), p = p, d = 15_000.0, ground = 4.8, closing = 4.0),
    ).also { e ->
        val st = e.state
        val lost = e.tickMs(S + lostAfterS(st.params, st.policyIntervalAtLastFixS, st.policy) * 1000L)
        assertTrue(lost.events.any { it is GpsLost }, "GpsLost")
    }

    @Test
    fun `T123 a W rings exactly at last fix + gpsLostLongS, not one millisecond earlier`() {
        val e = crawlLost()
        val est = estimateOf(e.state)
        assertEquals(1_800.0, est.lostLongAtS, "floor")
        assertTrue(est.etaS!! > 1_200.0 + 700.0, "the ETA rule must not be the one ringing (etaS ${est.etaS})")
        assertEquals(S + 1_800_000L, e.view.predictedAlarmAtMs, "predicted = lostLongAt")
        val before = e.tickMs(S + 1_799_999L)
        assertTrue(alarms(before).isEmpty(), "rang 1 ms before the floor: ${before.events}")
        assertEquals(TripPhase.TRACKING, before.view.phase)
        val at = e.tickMs(S + 1_800_000L)
        val a = alarms(at).single()
        assertEquals(AlarmReason.GPS_LOST, a.reason)
        assertTrue(a.ringNow)
        assertEquals(S + 1_800_000L, a.atMs)
    }

    @Test
    fun `T123 b gpsLostLongS 1801 moves the floor by one second, 0 turns W off entirely`() {
        val e = crawlLost(params("{\"gpsLostLongS\": 1801}"))
        assertEquals(1_801.0, estimateOf(e.state).lostLongAtS)
        assertTrue(alarms(e.tickMs(S + 1_800_000L)).isEmpty())
        assertTrue(alarms(e.tickMs(S + 1_800_999L)).isEmpty())
        assertEquals(AlarmReason.GPS_LOST, alarms(e.tickMs(S + 1_801_000L)).single().reason)

        // Off: no mark at any Step, nothing at the W time; the ETA rule (T10.5) rings later, with the wake-up loop only.
        val off = crawlLost(params("{\"gpsLostLongS\": 0, \"gpsLostLongHintFactor\": 2}"))
        assertNull(estimateOf(off.state).lostLongAtS)
        assertTrue(alarms(off.tickMs(S + 1_800_000L)).isEmpty(), "off rang at the W time")
        var guard = 0
        while (alarms(off.last).isEmpty() && guard++ < 500) {
            assertNull(estimateOf(off.state).lostLongAtS, "off: W mark at ${off.state.nowMs - S}")
            off.tickMs(off.view.wakeAtMs!!)
        }
        val a = alarms(off.last).single()
        assertEquals(AlarmReason.GPS_LOST, a.reason)
        assertTrue(a.atMs - S in 2_400_000L..2_800_000L, "off: ETA rule at ${(a.atMs - S) / 1000.0} s")
        // gpsLostLongHintFactor has no effect while W is off (same alarm as factor 0 and 1).
        for (f in listOf("0", "1")) {
            val o = crawlLost(params("{\"gpsLostLongS\": 0, \"gpsLostLongHintFactor\": $f}"))
            o.tickMs(S + 1_800_000L)
            var g = 0
            while (alarms(o.last).isEmpty() && g++ < 500) o.tickMs(o.view.wakeAtMs!!)
            assertEquals(a, alarms(o.last).single(), "hint factor $f with W off")
        }
    }

    // ============================================================ App update in the middle of a long loss: a real T12.2 snapshot

    private fun headSnapshot(): EngineState = TripEngine.decodeSnapshot(T122_SNAPSHOT)

    @Test
    fun `T123 c a T12_2 snapshot (no passAnchorD, no T10_6 params) decodes with the defaults and rings W, earlier than T12_2`() {
        val st = headSnapshot()
        assertFalse(T122_SNAPSHOT.contains("passAnchorD"))
        assertFalse(T122_SNAPSHOT.contains("gpsLostLongS"))
        assertNull(st.passAnchorD)
        assertEquals(1_800, st.params.gpsLostLongS)
        assertEquals(1.0, st.params.gpsLostLongHintFactor)
        assertEquals(300, st.params.passedClosestSlowRiseM)
        assertEquals(GpsStatus.LOST, st.gps)
        assertEquals(S + 4_026_000L, st.nowMs)
        val lla = estimateOf(st).lostLongAtS!!
        val lostLongAt = st.last!!.fixAtMs + TMath.floorMs(lla)
        assertTrue(lostLongAt > st.nowMs, "the mark is still ahead at the snapshot")

        // (1) Restore PENDING one minute later: no alarm yet, prediction = lostLongAt, then the wake-up loop rings at +1 s.
        val r1 = TripEngine.restore(st, st.nowMs + 60_000L, RestoreInfo(FallbackRestoreStatus.PENDING))
        assertTrue(alarms(r1).isEmpty())
        assertEquals(lostLongAt, r1.view.predictedAlarmAtMs)
        var s = r1
        var g = 0
        while (alarms(s).isEmpty() && g++ < 500) s = TripEngine.reduce(s.state, Tick(s.view.wakeAtMs!!))
        val a1 = alarms(s).single()
        assertEquals(AlarmReason.GPS_LOST, a1.reason)
        assertEquals(lostLongAt + 1_000L, a1.atMs)
        assertTrue(a1.atMs < S + T122_ALARM_MS, "T10.6 after an update rang later than T12.2 would have")

        // (2) Restore after the mark (process dead while the app was updated): GPS_LOST rings in the restore Step itself.
        for (status in listOf(FallbackRestoreStatus.PENDING, FallbackRestoreStatus.MISSING, FallbackRestoreStatus.UNKNOWN)) {
            val r2 = TripEngine.restore(headSnapshot(), lostLongAt + 120_000L, RestoreInfo(status))
            val a2 = alarms(r2)
            assertEquals(1, a2.size, "$status: ${r2.events}")
            assertEquals(AlarmReason.GPS_LOST, a2.single().reason, "$status")
            assertTrue(a2.single().ringNow, "$status")
        }
        File(outDir, "t123-c-update.txt").writeText(
            "T12.2 snapshot at ${(st.nowMs - S) / 1000.0} s; lostLongAtS $lla; T10.6 rings ${(a1.atMs - S) / 1000.0} s; " +
                "T12.2 rang ${T122_ALARM_MS / 1000.0} s\n",
        )
    }

    // ============================================================ Slow-vehicle net boundaries (C27)

    /** Gap open: minD 600, dStart 10 000 (open 9 400 >= 500), passedRadius 3 000 (> 600), openNeed max(500, 300) = 500. */
    private fun netState(d: Double, acc: Double, anchor: Double?, p: EngineParams = EngineParams(), gps: GpsStatus = GpsStatus.OK): StepWork {
        val st = trackingState(cfg(AlarmMode.DISTANCE, thr = 500), p = p, d = d, minD = 600.0, dStart = 10_000.0, acc = acc, gps = gps)
            .copy(passAnchorD = anchor)
        return StepWork(st)
    }

    private fun anchorAfter(w: StepWork): Double? {
        updatePassAnchor(w, estimate(w))
        return w.passAnchorD
    }

    @Test
    fun `T123 d passAnchorD boundaries - accuracy equal to speedSampleMaxAccM is good, the open gap at exactly openNeedM`() {
        assertEquals(1_200.0, anchorAfter(netState(1_200.0, 50.0, null)), "acc == 50 is a good fix")
        assertNull(anchorAfter(netState(1_200.0, Math.nextUp(50.0), null)), "acc just above 50 sets no mark")
        assertEquals(1_150.0, anchorAfter(netState(1_200.0, Math.nextUp(50.0), 1_150.0)), "a poor fix keeps the mark")
        assertEquals(1_150.0, anchorAfter(netState(1_200.0, 8.0, 1_150.0)), "min")
        assertEquals(1_100.0, anchorAfter(netState(1_100.0, 8.0, null)), "dSmooth - minD == openNeedM opens")
        assertNull(anchorAfter(netState(Math.nextDown(1_100.0), 8.0, 1_150.0)), "gap closed just below openNeedM clears the mark")
        assertNull(anchorAfter(netState(1_200.0, 8.0, 1_150.0, gps = GpsStatus.LOST)), "gps not OK clears the mark")
        assertNull(anchorAfter(netState(1_200.0, 8.0, 1_150.0, params("{\"passedClosestSlowRiseM\": 0}"))), "0 turns the net off")
    }

    @Test
    fun `T123 e slowAway boundaries - rise exactly passedClosestSlowRiseM counts, the second-to-last value decides`() {
        fun away(l3: List<Double>, acc: Double = 8.0, anchor: Double? = 1_000.0): Boolean {
            val w = netState(l3.last(), acc, anchor)
            w.last3 = l3
            return slowAway(w)
        }
        assertTrue(away(listOf(1_250.0, 1_300.0, 1_310.0)), "rise == 300")
        assertFalse(away(listOf(1_250.0, Math.nextDown(1_300.0), 1_310.0)), "rise just under 300")
        assertFalse(away(listOf(1_250.0, 1_290.0, 1_900.0)), "one far value (the last) is not enough")
        assertTrue(away(listOf(1_250.0, 1_300.0, 1_310.0), acc = 50.0), "acc == 50")
        assertFalse(away(listOf(1_250.0, 1_300.0, 1_310.0), acc = Math.nextUp(50.0)), "current fix poor")
        assertFalse(away(listOf(1_300.0, 1_310.0)), "fewer than 3 values")
        assertFalse(away(listOf(1_250.0, 1_300.0, 1_310.0), anchor = null), "no mark")
    }

    // ============================================================ Remote Config (T29 passes the JSON through)

    @Test
    fun `T123 f Remote Config values out of range or of the wrong type are rejected one by one and keep the default`() {
        val bad = mapOf(
            "gpsLostLongS" to listOf("1e10", "-0.5", "21600.0001", "\"1800\"", "null", "[1800]"),
            "gpsLostLongHintFactor" to listOf("\"1\"", "false", "1e309", "-1e-9", "2.0000001"),
            "passedClosestSlowRiseM" to listOf("-1", "300.5", "3000.5", "\"0\""),
        )
        for ((k, vs) in bad) {
            for (v in vs) {
                val r = EngineParamsFactory.parseOverrides("{\"$k\": $v, \"etaStopPenaltyS\": 30}")
                assertFalse(r.malformed, "$k=$v")
                assertEquals(listOf(k), r.rejected, "$k=$v")
                assertEquals(EngineParams().copy(etaStopPenaltyS = 30), r.params, "$k=$v: other keys still applied, this one default")
            }
        }
        // Edge values that are valid: integral doubles for Int params, -0 as 0.
        assertEquals(1_800, EngineParamsFactory.parseOverrides("{\"gpsLostLongS\": 1800.0}").params.gpsLostLongS)
        assertEquals(0, EngineParamsFactory.parseOverrides("{\"gpsLostLongS\": -0}").params.gpsLostLongS)
        assertEquals(0.0, EngineParamsFactory.parseOverrides("{\"gpsLostLongHintFactor\": -0.0}").params.gpsLostLongHintFactor)
        assertEquals(1_000, EngineParamsFactory.parseOverrides("{\"passedClosestSlowRiseM\": 1e3}").params.passedClosestSlowRiseM)
    }

    // ============================================================ T10 "T10.6" §9: thresholds written as numbers

    /**
     * Gate on the numeric §9 thresholds of U126 that the coder only prints: seed 55 (withfix) and 787 (nofix-mixed) late <= 1 200 s,
     * seed 433 (withfix) before the 1 km crossing, withfix / nofix-mixed 0 DISTANCE cases late > 1 800 s, no `class=?` line in any
     * fuzz nor in e1/e2. Runs U126 a / b (about 30 s) and reads their files.
     */
    @Tag("slow")
    @Test
    fun `T123 g U126 numeric thresholds of T10_6 section 9 hold`() {
        TesterT121Test().`U126 a Doze fuzz lateness T12_2 vs T10_6, long-loss alarms and the review seeds`()
        TesterT122Test().`U126 b e1 e2 fuzz lateness T12_2 vs T10_6 and long-loss alarms`()
        val a = File(outDir, "u126-longloss.txt").readText()
        val b = File(outDir, "u126-longloss-t122.txt").readText()
        assertFalse(a.contains("class=?"), "class=? in u126-longloss.txt")
        assertFalse(b.contains("class=?"), "class=? in u126-longloss-t122.txt")
        val groups = a.split("\n## ").associate { it.substringBefore('\n').trim() to it }
        for (g in listOf("withfix", "nofix-mixed")) {
            val m = Regex("late > 1800 s: off \\d+ -> T10\\.6 (\\d+)").find(groups.getValue(g))!!
            assertEquals("0", m.groupValues[1], "$g: DISTANCE cases late > 1 800 s")
        }
        fun lateOf(group: String, seed: Int): Int {
            val line = groups.getValue(group).lines().single { it.startsWith("seed T10.6 seed=$seed ") }
            return Regex("vs DISTANCE crossing (-?\\d+) s").find(line)!!.groupValues[1].toInt()
        }
        assertTrue(lateOf("withfix", 55) <= 1_200, "seed 55 late ${lateOf("withfix", 55)}")
        assertTrue(lateOf("nofix-mixed", 787) <= 1_200, "seed 787 late ${lateOf("nofix-mixed", 787)}")
        assertTrue(lateOf("withfix", 433) < 0, "seed 433 not before the crossing: ${lateOf("withfix", 433)}")
    }

    private companion object {
        /** Where the T12.2 engine (HEAD 1bea01e) rings when left alone from [T122_SNAPSHOT] (Tick-only wake-up loop), ms after S. */
        const val T122_ALARM_MS = 7_626_000L

        /**
         * Snapshot written by the T12.2 engine (HEAD 1bea01e, default params): TRAIN, DISTANCE 1 000, fixes every 5 s at 12.5 m/s
         * from 110 km for 900 s, then no fix; first wake-up Tick at or after S + 3 000 s (S + 4 026 s). Synthetic coordinates.
         */
        const val T122_SNAPSHOT: String =
            "{\"snapshotVersion\":1,\"params\":{\"fixMaxAgeS\":60,\"accAbsMaxM\":100.0,\"accRelMax\":0.05,\"accHardMaxM\":2000.0,\"maxPl" +
            "ausibleSpeedMps\":55.0,\"outlierResetSpanS\":30,\"smoothWindowS\":12,\"stationarySpeedMps\":1.0,\"motionAccFactor\":1.0" +
            ",\"stopExitMinM\":50,\"speedEmaTauS\":300,\"shortStopIncludeS\":60,\"speedEstablishedMovingS\":120,\"speedEstablishedSa" +
            "mples\":3,\"maxSpeedSampleGapS\":900,\"speedSampleMaxAccM\":50.0,\"routeFactorPrior\":1.2,\"routeFactorMin\":1.0,\"route" +
            "FactorMax\":2.0,\"expectedSpeedKmhTrain\":55,\"expectedSpeedKmhCoach\":60,\"expectedSpeedKmhBus\":20,\"expectedSpeedKm" +
            "hUnknown\":60,\"etaStopPenaltyS\":20,\"minSpeedForEtaMps\":0.5,\"etaUncertaintyFrac\":0.1,\"distanceModeFactor\":1.0,\"s" +
            "martTargetS\":600,\"smartFloorM\":1000,\"smartSlowSpeedKmh\":15,\"smartSlowHysteresisKmh\":2,\"shortDistanceWarnS\":240" +
            ",\"preAlertLeadS\":1800,\"preAlertDistanceFactor\":5,\"preAlertMinDistanceM\":3000,\"preAlertMinGapS\":300,\"gpsLostMin" +
            "S\":60,\"gpsLostIntervalFactor\":3,\"gpsLostAlarmEtaS\":1200,\"acquireTimeoutS\":120,\"lostErrFrac\":0.25,\"lostSpeedGua" +
            "rdUpdates\":2,\"overshootNearMinM\":1000,\"overshootOpenM\":1000,\"overshootMinSpeedKmh\":10,\"passedClosestMinRadiusM" +
            "\":3000,\"passedClosestReachFactor\":2.0,\"passedClosestOpenMinM\":500,\"passedClosestOpenFrac\":0.5,\"arrivedRadiusM\"" +
            ":300,\"snoozeS\":60,\"maxSnoozes\":1,\"alarmMaxActiveS\":3600,\"maxTripMinS\":14400,\"maxTripCapS\":172800,\"lowBatteryAl" +
            "armPct\":5,\"lowBatteryEarlierPct\":15,\"batteryPriorDrainPctPerH\":2.0,\"batteryMinRatePctPerH\":0.5,\"batteryMinRate" +
            "WindowS\":1200,\"batteryReserveAfterAlarmS\":900,\"denseEnterS\":900,\"mediumEnterS\":3600,\"tierHysteresisFactor\":1.2" +
            "5,\"samplingSparseIntervalS\":180,\"samplingSparseMinIntervalS\":90,\"samplingMediumIntervalS\":30,\"samplingMediumMi" +
            "nIntervalS\":15,\"samplingDenseIntervalS\":5,\"samplingDenseMinIntervalS\":2,\"maxSavingIntervalFactor\":2,\"fallbackL" +
            "agS\":30,\"fallbackEarlyFrac\":0.25,\"fallbackEarlyMaxS\":3600,\"fallbackHintSpeedFactor\":1.0,\"fallbackNearS\":600,\"f" +
            "allbackNearSlackS\":60,\"fallbackMinLeadS\":10,\"fallbackQuietBeforeS\":30,\"fallbackMinShiftS\":30,\"fallbackMinInter" +
            "valS\":60,\"fallbackRetryS\":60,\"vehicleBusMaxAvgKmh\":30},\"config\":{\"tripId\":\"snap-1\",\"destLat\":16.2,\"destLng\":10" +
            "7.6,\"mode\":\"DISTANCE\",\"distanceThresholdM\":1000,\"timeThresholdMin\":null,\"preAlertEnabled\":true,\"vehicleHint\":\"" +
            "TRAIN\"},\"nowMs\":1800004026000,\"startedAtMs\":1800000000000,\"phase\":\"TRACKING\",\"gps\":\"LOST\",\"locationCause\":\"AVA" +
            "ILABLE\",\"last\":{\"fixAtMs\":1800000900000,\"lat\":15.31291771469637,\"lng\":107.6,\"accM\":6.0,\"d\":98639.18588808276,\"" +
            "groundSample\":12.5},\"stopAnchor\":null,\"recent\":[{\"fixAtMs\":1800000890000,\"lat\":15.311794825727631,\"lng\":107.6," +
            "\"accM\":6.0,\"d\":98764.04561705506,\"groundSample\":12.5},{\"fixAtMs\":1800000895000,\"lat\":15.312356270212002,\"lng\":" +
            "107.6,\"accM\":6.0,\"d\":98701.61575256882,\"groundSample\":12.5},{\"fixAtMs\":1800000900000,\"lat\":15.31291771469637,\"" +
            "lng\":107.6,\"accM\":6.0,\"d\":98639.18588808276,\"groundSample\":12.5}],\"rejects\":[],\"dSmooth\":98701.61575256882,\"dS" +
            "tartM\":109814.13163109969,\"minD\":98701.61575256882,\"minDChord\":false,\"last3\":[98826.47548154111,98764.04561705" +
            "506,98701.61575256882],\"ground\":12.5,\"closing\":12.485972897224906,\"movingTimeS\":895.0,\"movingSamples\":179,\"mov" +
            "ingDistM\":11187.5,\"stopStartMs\":null,\"slow\":false,\"cvGuard\":[12.485972897224752,12.485972897225142],\"policy\":{" +
            "\"tier\":\"MEDIUM\",\"intervalS\":30,\"minIntervalS\":15,\"accuracy\":\"HIGH\"},\"policyIntervalAtLastFixS\":180,\"gpsLostAtM" +
            "s\":1800001440000,\"lostEmittedBeforeFirstFix\":false,\"preAlertArmed\":true,\"preAlertFired\":false,\"arrivedFired\":f" +
            "alse,\"alarm\":{\"atMs\":null,\"reason\":null,\"source\":null,\"lastRingAtMs\":null,\"lastReason\":null,\"ringing\":false,\"s" +
            "noozeCount\":0,\"snoozeUntilMs\":null,\"dismissedAtMs\":null},\"overshootAtMs\":null,\"overshootPastM\":null,\"fallback\"" +
            ":{\"targetAtMs\":1800006836133,\"emittedAtMs\":1800004026000,\"status\":\"REQUESTED\",\"confirmedAtMs\":null,\"resync\":fa" +
            "lse,\"near\":false},\"battery\":{\"levelPct\":null,\"charging\":false,\"segT0\":null,\"segL0\":null,\"armed\":false,\"riskEmi" +
            "tted\":false,\"choice\":null,\"choicePct\":null},\"maxTripDurationS\":17291,\"droppedFixes\":0,\"ended\":null}"
    }
}
