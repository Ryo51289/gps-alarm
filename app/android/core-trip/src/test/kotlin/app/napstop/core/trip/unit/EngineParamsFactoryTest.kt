package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.PARAM_SPECS
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class EngineParamsFactoryTest {
    private val def = EngineParams()

    private fun parse(json: String?) = EngineParamsFactory.parseOverrides(json)

    @Test
    fun `U02 invalid keys keep defaults, unknown key ignored, broken JSON gives defaults`() {
        val r = parse("{\"gpsLostMinS\": 5, \"fixMaxAgeS\": \"x\", \"foo\": 1}")
        assertEquals(60, r.params.gpsLostMinS)
        assertEquals(60, r.params.fixMaxAgeS)
        assertEquals(listOf("gpsLostMinS", "fixMaxAgeS"), r.rejected)
        assertEquals(def, EngineParamsFactory.fromOverrides("{\"gpsLostMinS\": "))
    }

    @Test
    fun `U67 a-g Int accepts integral numbers, cross groups G1 to G5`() {
        assertEquals(60, parse("{\"gpsLostMinS\": 60.0}").params.gpsLostMinS)
        parse("{\"gpsLostMinS\": 60.5}").let { assertEquals(60, it.params.gpsLostMinS); assertEquals(listOf("gpsLostMinS"), it.rejected) }
        parse("{\"routeFactorMin\": 1.4, \"routeFactorPrior\": 1.3}").let {
            assertEquals(1.0, it.params.routeFactorMin); assertEquals(1.2, it.params.routeFactorPrior); assertEquals(2.0, it.params.routeFactorMax)
            assertEquals(listOf("routeFactorMin", "routeFactorPrior"), it.rejected)
        }
        parse("{\"denseEnterS\": 1800, \"mediumEnterS\": 1200}").params.let { assertEquals(900, it.denseEnterS); assertEquals(3600, it.mediumEnterS) }
        parse("{\"maxTripMinS\": 90000, \"maxTripCapS\": 86400}").params.let { assertEquals(14400, it.maxTripMinS); assertEquals(172800, it.maxTripCapS) }
        parse("{\"lowBatteryAlarmPct\": 15, \"lowBatteryEarlierPct\": 15}").params.let { assertEquals(5, it.lowBatteryAlarmPct); assertEquals(15, it.lowBatteryEarlierPct) }
        parse("{\"fallbackQuietBeforeS\": 120, \"fallbackNearS\": 150}").params.let { assertEquals(30, it.fallbackQuietBeforeS); assertEquals(600, it.fallbackNearS) }
    }

    @Test
    fun `U67 h-m sampling group G6, G7, out of range, lostSpeedGuardUpdates`() {
        for (j in listOf("{\"samplingDenseIntervalS\": 15, \"samplingMediumIntervalS\": 10}", "{\"samplingSparseIntervalS\": 180, \"samplingSparseMinIntervalS\": 200}")) {
            val p = parse(j).params
            assertEquals(listOf(180, 90, 30, 15, 5, 2), listOf(p.samplingSparseIntervalS, p.samplingSparseMinIntervalS, p.samplingMediumIntervalS, p.samplingMediumMinIntervalS, p.samplingDenseIntervalS, p.samplingDenseMinIntervalS))
        }
        parse("{\"fallbackLagS\": 10, \"samplingDenseIntervalS\": 10}").let {
            assertEquals(30, it.params.fallbackLagS); assertEquals(10, it.params.samplingDenseIntervalS); assertEquals(listOf("fallbackLagS"), it.rejected)
        }
        parse("{\"fallbackLagS\": 12, \"samplingDenseIntervalS\": 10}").let {
            assertEquals(12, it.params.fallbackLagS); assertEquals(10, it.params.samplingDenseIntervalS); assertTrue(it.rejected.isEmpty())
        }
        assertEquals(600, parse("{\"fallbackNearS\": 60}").params.fallbackNearS)
        assertEquals(30, parse("{\"fallbackLagS\": 5}").params.fallbackLagS)
        for ((v, want) in listOf("0" to 0, "5" to 5, "2.0" to 2, "6" to 2, "-1" to 2, "1.5" to 2)) {
            assertEquals(want, parse("{\"lostSpeedGuardUpdates\": $v}").params.lostSpeedGuardUpdates, v)
        }
    }

    @Test
    fun `U67 n T25 U05 edges for shortDistanceWarnS`() {
        for (v in listOf("300", "300.0", "3e2")) assertEquals(300, parse("{\"shortDistanceWarnS\": $v}").params.shortDistanceWarnS, v)
        for (v in listOf("300.5", "\"300\"", "true", "null", "59", "601", "1e300")) {
            val r = parse("{\"shortDistanceWarnS\": $v}")
            assertEquals(240, r.params.shortDistanceWarnS, v)
            assertEquals(listOf("shortDistanceWarnS"), r.rejected, v)
        }
        assertEquals(60, parse("{\"shortDistanceWarnS\": 60}").params.shortDistanceWarnS)
        assertEquals(600, parse("{\"shortDistanceWarnS\": 600}").params.shortDistanceWarnS)
        parse("{\"foo\": 1}").let { assertTrue(it.rejected.isEmpty()); assertFalse(it.malformed) }
    }

    @Test
    fun `U67 o-q negative zero, duplicate keys, malformed inputs`() {
        assertEquals(0, parse("{\"preAlertMinGapS\": -0.0}").params.preAlertMinGapS)
        assertEquals(0, parse("{\"preAlertMinGapS\": -0}").params.preAlertMinGapS)
        assertEquals(java.lang.Double.doubleToRawLongBits(0.0), java.lang.Double.doubleToRawLongBits(parse("{\"accRelMax\": -0.0}").params.accRelMax))
        assertEquals(120, parse("{\"gpsLostMinS\": 90, \"gpsLostMinS\": 120}").params.gpsLostMinS)
        assertEquals(60, parse("{\"gpsLostMinS\": 90, \"gpsLostMinS\": \"x\"}").params.gpsLostMinS)
        parse("{\"gpsLostMinS\": 1e400}").let { assertFalse(it.malformed); assertEquals(listOf("gpsLostMinS"), it.rejected); assertEquals(def, it.params) }
        for (j in listOf("﻿{\"gpsLostMinS\": 90}", "{\"gpsLostMinS\": 90,}", "{\"gpsLostMinS\": 012}", "[]", "\"42\"", "null")) {
            val r = parse(j)
            assertTrue(r.malformed, j)
            assertEquals(def, r.params, j)
        }
        for (j in listOf("", "   ", null)) parse(j).let { assertFalse(it.malformed); assertEquals(def, it.params) }
    }

    @Test
    fun `U67 r PARAM_SPECS has the 83 rows of T10 section 5`() {
        // Handwritten copy of the T10 §5 table: name type default min max.
        val table = """
            fixMaxAgeS I 60 10 300|accAbsMaxM D 100 20 500|accRelMax D 0.05 0 0.2|accHardMaxM D 2000 200 5000|maxPlausibleSpeedMps D 55 30 100
            outlierResetSpanS I 30 10 300|smoothWindowS I 12 0 60|stationarySpeedMps D 1 0.3 3|motionAccFactor D 1 0.5 3|stopExitMinM I 50 20 300
            speedEmaTauS I 300 30 1800|shortStopIncludeS I 60 0 300|speedEstablishedMovingS I 120 0 600|speedEstablishedSamples I 3 1 20
            maxSpeedSampleGapS I 900 60 3600|speedSampleMaxAccM D 50 10 200|routeFactorPrior D 1.2 1 2|routeFactorMin D 1 1 1.5|routeFactorMax D 2 1.2 4
            expectedSpeedKmhTrain I 55 5 150|expectedSpeedKmhCoach I 60 5 150|expectedSpeedKmhBus I 20 5 150|expectedSpeedKmhUnknown I 60 5 150
            etaStopPenaltyS I 20 0 120|minSpeedForEtaMps D 0.5 0.1 3|etaUncertaintyFrac D 0.1 0 0.5|distanceModeFactor D 1 1 1.5
            smartTargetS I 600 300 1200|smartFloorM I 1000 500 3000|smartSlowSpeedKmh I 15 5 30|smartSlowHysteresisKmh I 2 0 10
            shortDistanceWarnS I 240 60 600|preAlertLeadS I 1800 600 3600|preAlertDistanceFactor I 5 2 10|preAlertMinDistanceM I 3000 1000 10000
            preAlertMinGapS I 300 0 900|gpsLostMinS I 60 20 300|gpsLostIntervalFactor I 3 2 5|gpsLostAlarmEtaS I 1200 300 3600
            acquireTimeoutS I 120 30 600|lostErrFrac D 0.25 0 1|lostSpeedGuardUpdates I 2 0 5|overshootNearMinM I 1000 300 3000
            overshootOpenM I 1000 300 3000|overshootMinSpeedKmh I 10 3 30|passedClosestMinRadiusM I 3000 1000 10000|passedClosestReachFactor D 2 1 4
            passedClosestOpenMinM I 500 200 3000|passedClosestOpenFrac D 0.5 0.2 2|arrivedRadiusM I 300 50 1000|snoozeS I 60 30 600|maxSnoozes I 1 0 3
            alarmMaxActiveS I 3600 600 14400|maxTripMinS I 14400 3600 259200|maxTripCapS I 172800 3600 259200|lowBatteryAlarmPct I 5 2 20
            lowBatteryEarlierPct I 15 5 40|batteryPriorDrainPctPerH D 2 0.5 10|batteryMinRatePctPerH D 0.5 0.1 5|batteryMinRateWindowS I 1200 300 7200
            batteryReserveAfterAlarmS I 900 0 3600|denseEnterS I 900 300 1800|mediumEnterS I 3600 1200 7200|tierHysteresisFactor D 1.25 1 2
            samplingSparseIntervalS I 180 60 600|samplingSparseMinIntervalS I 90 60 600|samplingMediumIntervalS I 30 10 120|samplingMediumMinIntervalS I 15 10 120
            samplingDenseIntervalS I 5 1 15|samplingDenseMinIntervalS I 2 1 15|maxSavingIntervalFactor I 2 1 4|fallbackLagS I 30 10 120
            fallbackEarlyFrac D 0.25 0 0.5|fallbackEarlyMaxS I 3600 0 7200|fallbackHintSpeedFactor D 1 0 2|fallbackNearS I 600 120 1800
            fallbackNearSlackS I 60 10 300|fallbackMinLeadS I 10 5 60|fallbackQuietBeforeS I 30 30 120|fallbackMinShiftS I 30 10 300
            fallbackMinIntervalS I 60 10 300|fallbackRetryS I 60 10 300|vehicleBusMaxAvgKmh I 30 10 50
        """.trimIndent().replace("\n", "|").split("|").map { it.trim().split(" ") }
        assertEquals(83, table.size)
        assertEquals(83, PARAM_SPECS.size)
        for ((i, row) in table.withIndex()) {
            val s = PARAM_SPECS[i]
            assertEquals(row[0], s.name)
            assertEquals(row[1] == "I", s.isInt, s.name)
            assertEquals(row[2].toDouble(), s.default, s.name)
            assertEquals(row[3].toDouble(), s.min, s.name)
            assertEquals(row[4].toDouble(), s.max, s.name)
            assertEquals(s.default, s.get(def), s.name)
        }
    }

    @Test
    fun `U97 a T10_2 fallback parameters ranges`() {
        assertEquals(0.0, parse("{\"fallbackHintSpeedFactor\": 0}").params.fallbackHintSpeedFactor)
        assertEquals(2.0, parse("{\"fallbackHintSpeedFactor\": 2}").params.fallbackHintSpeedFactor)
        for (v in listOf("2.5", "-0.1", "\"1\"")) assertEquals(1.0, parse("{\"fallbackHintSpeedFactor\": $v}").params.fallbackHintSpeedFactor, v)
        assertEquals(0.5, parse("{\"fallbackEarlyFrac\": 0.5}").params.fallbackEarlyFrac)
        assertEquals(0.25, parse("{\"fallbackEarlyFrac\": 0.55}").params.fallbackEarlyFrac)
        assertEquals(7200, parse("{\"fallbackEarlyMaxS\": 7200}").params.fallbackEarlyMaxS)
        assertEquals(3600, parse("{\"fallbackEarlyMaxS\": 7201}").params.fallbackEarlyMaxS)
    }
}
