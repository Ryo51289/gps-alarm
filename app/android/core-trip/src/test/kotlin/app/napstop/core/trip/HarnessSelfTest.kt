package app.napstop.core.trip

import app.napstop.core.trip.harness.CaseModel
import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.ConfigError
import app.napstop.core.trip.harness.ExpectModel
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.StepRecord
import app.napstop.core.trip.harness.TraceModel
import app.napstop.core.trip.harness.caseSetup
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * Self-tests of the fixture harness (review T12 #1): must-understand keys, configuration errors and the T10.3
 * `allowFallbackFirst` rules (V14–V16) must fail loudly, never pass silently.
 */
class HarnessSelfTest {
    @TempDir
    lateinit var dir: File

    private val baseCase = """{"id":"c","status":"final","testIds":["TR01"],"config":{"mode":"distance","thresholdM":1000,"preAlert":true},
        |"expect":[],"forbid":[]}""".trimMargin()

    /** Tiny synthetic trace: 7 fixes, 5 s apart, south of the destination. Returns the TraceModel. */
    private fun trace(vararg cases: String): TraceModel {
        val start = "2026-03-14T00:00:00Z"
        val gpx = StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"t\" xmlns=\"http://www.topografix.com/GPX/1/1\" ")
        gpx.append("xmlns:napstop=\"https://napstop.app/xmlns/trace/1\"><trk><trkseg>\n")
        for (i in 0..6) {
            gpx.append("<trkpt lat=\"").append(-0.1 + i * 0.0005).append("\" lon=\"106.0\"><time>2026-03-14T00:00:")
            gpx.append((i * 5).toString().padStart(2, '0')).append("Z</time><extensions><napstop:acc>8.0</napstop:acc>")
            gpx.append("<napstop:spd>11.0</napstop:spd></extensions></trkpt>\n")
        }
        gpx.append("</trkseg></trk></gpx>\n")
        File(dir, "t.gpx").writeText(gpx.toString())
        val json = """{"schemaVersion":1,"generator":{"name":"x","version":"0"},
            |"trace":{"id":"t","vehicle":"coach","gpx":"t.gpx","startTime":"$start","sampleIntervalS":5,"durationS":30,"sampleCount":7,"futureKey":1},
            |"destination":{"lat":0.0,"lng":106.0},"truth":{"arrivalT":30},"milestones":{},
            |"cases":[${cases.joinToString(",")}]}""".trimMargin()
        val f = File(dir, "t.expect.json")
        f.writeText(json)
        return ExpectModel.load(f)
    }

    private fun with(extraCase: String = "", extraConfig: String = ""): String {
        var c = baseCase
        if (extraConfig.isNotEmpty()) c = c.replace("\"preAlert\":true", "\"preAlert\":true,$extraConfig")
        if (extraCase.isNotEmpty()) c = c.replace("\"expect\":[]", "$extraCase,\"expect\":[]")
        return c
    }

    private fun error(case: String): String? = trace(case).cases.single().error

    private val fallbackExpect = """"expect":[{"event":"alarm","reason":"FALLBACK","ringNow":false,"notBefore":0,"notAfter":0}]"""

    @Test
    fun `unknown keys anywhere inside a case fail the case, outside cases they are ignored`() {
        assertNull(error(baseCase))
        val bad = listOf(
            with(extraCase = "\"newKey\":1"),
            with(extraConfig = "\"newConfigKey\":1"),
            with(extraConfig = "\"params\":{\"notAParam\":1}"),
            with(extraConfig = "\"actions\":[{\"at\":{\"t\":5,\"extra\":1},\"action\":\"stop\"}]"),
            baseCase.replace("\"expect\":[]", "\"expect\":[{\"event\":\"alarm\",\"notBefore\":0,\"notAfter\":5,\"ref\":\"x\",\"weird\":true}]"),
            baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"forbidMatch\":[{\"event\":\"alarm\",\"reasonX\":\"DISTANCE\"}]"),
            baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"expectSummary\":{\"vehicleGuess\":\"BUS\",\"x\":1}"),
            baseCase.replace("\"expect\":[]", "\"expect\":[{\"event\":\"unknownEvent\",\"notBefore\":0,\"notAfter\":5}]"),
        )
        for (b in bad) assertNotNull(error(b), b)
    }

    @Test
    fun `allowFallbackFirst V14 to V16 are configuration errors, the valid form parses`() {
        val ok = with(extraCase = "\"allowFallbackFirst\":true").replace("\"expect\":[]", fallbackExpect)
        val okModel = trace(ok).cases.single()
        assertNull(okModel.error)
        assertTrue(okModel.model!!.allowFallbackFirst)
        assertFalse(trace(with(extraCase = "\"allowFallbackFirst\":false")).cases.single().model!!.allowFallbackFirst)
        assertEquals("allowFallbackFirst must be true or false", error(ok.replace("\"allowFallbackFirst\":true", "\"allowFallbackFirst\":\"yes\"")))
        assertEquals("allowFallbackFirst must be true or false", error(ok.replace("\"allowFallbackFirst\":true", "\"allowFallbackFirst\":1")))
        val v15 = "allowFallbackFirst cannot be used with config.kill or killSweep"
        assertEquals(v15, error(ok.replace("\"preAlert\":true", "\"preAlert\":true,\"kill\":{\"t\":10}")))
        val ks = "\"killSweep\":{\"from\":{\"t\":5},\"everyS\":5,\"notAfter\":{\"t\":30},\"earlyFrom\":{\"t\":20}}"
        assertEquals(v15, error(ok.replace("\"forbid\":[]", "\"forbid\":[],$ks")))
        val v16 = "allowFallbackFirst needs an expect entry for alarm with ringNow false"
        assertEquals(v16, error(with(extraCase = "\"allowFallbackFirst\":true")))
        assertEquals(v16, error(ok.replace("\"ringNow\":false", "\"ringNow\":true")))
    }

    @Test
    fun `P02 is exempted only by allowFallbackFirst`() {
        val ok = with(extraCase = "\"allowFallbackFirst\":true").replace("\"expect\":[]", fallbackExpect)
        val t = trace(ok, baseCase.replace("\"id\":\"c\"", "\"id\":\"d\"").replace("\"expect\":[]", fallbackExpect))
        val (cfg, p) = caseSetup(t, t.cases[0].model!!, emptyMap())
        val view = TripEngine.start(cfg, p, t.startMs).view
        val alarm = Alarm(t.startMs, AlarmReason.FALLBACK, false, true, null, null, null)
        fun run(case: CaseModel) = RunResult(
            RunKey("t", case.id, "all", false, 0), t.startMs, p,
            listOf(StepRecord(0, null, "[\"START\"]", listOf(alarm), view.copy(phase = TripPhase.ALARMING))),
            arrayOfNulls(7), arrayOfNulls(7), 0, mapOf("alarm" to 0), null, null, null, emptyList(), emptyMap(),
        )
        val exempt = Checks.check(t, t.cases[0].model!!, run(t.cases[0].model!!))
        assertTrue(exempt.none { it.startsWith("P02") }) { exempt.toString() }
        val strict = Checks.check(t, t.cases[1].model!!, run(t.cases[1].model!!))
        assertTrue(strict.any { it.startsWith("P02") }) { strict.toString() }
    }

    @Test
    fun `I15 flags a second Alarm(OVERSHOOT) and a silent AlarmSilenced after an overshoot while ringing (T10_8)`() {
        val t = trace(baseCase)
        val (cfg, p) = caseSetup(t, t.cases[0].model!!, emptyMap())
        val view = TripEngine.start(cfg, p, t.startMs).view
        val ms = t.startMs
        val dist = Alarm(ms, AlarmReason.DISTANCE, true, true, null, null, null)
        val ov = Alarm(ms + 10_000, AlarmReason.OVERSHOOT, true, false, null, null, null)
        val over = Overshoot(ms + 5_000, 1000)
        fun rec(tS: Int, input: EngineInput?, vararg ev: TripEvent) = StepRecord(tS, input, "", ev.toList(), view)
        val silenced = AlarmSilenced(ms + 10_000, ms + 10_000)
        val head = listOf(rec(0, null, dist), rec(5, null, over))
        assertEquals(emptyList<String>(), Checks.i15(head + rec(10, silenced, ov), "x"))
        assertTrue(Checks.i15(head + rec(10, silenced), "x").single().startsWith("I15: AlarmSilenced"))
        val ended = TripEnded(ms + 10_000, TripOutcome.MISSED, EndReason.ALARM_UNANSWERED, TripSummary(ms, ms, AlarmReason.DISTANCE, null, 0, 0, VehicleKind.COACH))
        assertEquals(emptyList<String>(), Checks.i15(head + rec(10, silenced, ended), "x"))
        // Review T12.5 nit 2: a re-ring that does not ring now does not count.
        val ovLater = Alarm(ms + 10_000, AlarmReason.OVERSHOOT, false, false, null, null, null)
        assertTrue(Checks.i15(head + rec(10, silenced, ovLater), "x").single().startsWith("I15: AlarmSilenced in OVERSHOT without"))
        // Review T12.5 nit 1: the Step that ends the trip (alarmMaxActiveS) must not ring as well.
        assertTrue(Checks.i15(head + rec(10, silenced, ov, ended), "x").single().startsWith("I15: AlarmSilenced Step rings OVERSHOOT and ends"))
        // The wait is only armed by an Overshoot Step without Alarm(OVERSHOOT): after an Overshoot that rang (TRACKING → OVERSHOT,
        // #18) a silent AlarmSilenced is not a failure.
        assertEquals(emptyList<String>(), Checks.i15(listOf(rec(0, null, ov, over), rec(10, silenced)), "x"))
        val twice = listOf(rec(0, null, ov, over), rec(10, silenced), rec(15, null, ov))
        assertTrue(Checks.i15(twice, "x").single().startsWith("I15: 2 Alarm(OVERSHOOT)"))
    }

    @Test
    fun `rejected params and runtime anchors that never happen are configuration errors`() {
        val t = trace(
            with(extraConfig = "\"params\":{\"gpsLostMinS\":5}"),
            with(extraConfig = "\"actions\":[{\"at\":{\"anchor\":\"event:overshoot\",\"offsetS\":5},\"action\":\"dismiss\"}]")
                .replace("\"id\":\"c\"", "\"id\":\"d\""),
        )
        val m0 = t.cases[0].model!!
        assertThrows(ConfigError::class.java) { caseSetup(t, m0, emptyMap()) }
        val m1 = t.cases[1].model!!
        val e = assertThrows(ConfigError::class.java) { CaseRun.run(t, m1, RunKey("t", "d", "all", false, 0)) }
        assertTrue(e.message!!.contains("never ran"))
    }

    /**
     * Every must-understand key of `cases[i]` and `config` has a semantic probe here. Adding a key to the harness without
     * implementing (and listing) its meaning fails this test, so a "known key with missing semantics" cannot pass silently.
     */
    @Test
    fun `every known case and config key is consumed by the model`() {
        val ks = "\"killSweep\":{\"from\":{\"t\":5},\"everyS\":5,\"notAfter\":{\"t\":30},\"earlyFrom\":{\"t\":20},\"statsOnly\":true}"
        val probes: Map<String, Pair<String, (CaseModel) -> Boolean>> = mapOf(
            "id" to (baseCase to { m -> m.id == "c" }),
            "status" to (baseCase to { _ -> true }), // informational, must-understand only
            "testIds" to (baseCase to { m -> m.testIds == listOf("TR01") }),
            "config" to (baseCase to { m -> m.config.mode == "distance" }),
            "samplingModes" to (with(extraCase = "\"samplingModes\":[\"all\"]") to { m -> m.samplingModes == listOf("all") }),
            "policyPhaseSweep" to (with(extraCase = "\"policyPhaseSweep\":true") to { m -> m.policyPhaseSweep }),
            "allowFallbackFirst" to (with(extraCase = "\"allowFallbackFirst\":true").replace("\"expect\":[]", fallbackExpect) to { m -> m.allowFallbackFirst }),
            "expect" to (baseCase.replace("\"expect\":[]", fallbackExpect) to { m -> m.expect.single().filter.ringNow == false }),
            "expectAfter" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"expectAfter\":[{\"event\":\"tripEnded\",\"after\":{\"anchor\":\"event:alarm\",\"offsetS\":0},\"withinS\":[0,5]}]") to { m -> m.expectAfter.single().hi == 5 }),
            "expectFallback" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"expectFallback\":{\"asOfT\":5,\"notBefore\":1,\"notAfter\":9}") to { m -> m.expectFallback!!.notAfter == 9 }),
            "killSweep" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],$ks") to { m -> m.killSweep!!.statsOnly }),
            "expectOutcome" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"expectOutcome\":\"MISSED\"") to { m -> m.expectOutcome == "MISSED" }),
            "expectSummary" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"expectSummary\":{\"vehicleGuess\":\"BUS\"}") to { m -> m.expectSummaryVehicle == "BUS" }),
            "forbid" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[\"gpsLost\"]") to { m -> m.forbid == listOf("gpsLost") }),
            "forbidMatch" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"forbidMatch\":[{\"event\":\"alarm\",\"reason\":\"DISTANCE\"}]") to { m -> m.forbidMatch.single().reason == "DISTANCE" }),
            "forbidAfter" to (baseCase.replace("\"forbid\":[]", "\"forbid\":[],\"forbidAfter\":[{\"event\":\"alarm\",\"after\":{\"anchor\":\"relaunch\",\"offsetS\":-5}}]") to { m -> m.forbidAfter.single().second.offsetS == -5 }),
            "config.mode" to (baseCase to { m -> m.config.mode == "distance" }),
            "config.thresholdM" to (baseCase to { m -> m.config.thresholdM == 1000 }),
            "config.thresholdMin" to (baseCase.replace("\"mode\":\"distance\",\"thresholdM\":1000", "\"mode\":\"time\",\"thresholdMin\":15") to { m -> m.config.thresholdMin == 15 }),
            "config.preAlert" to (baseCase to { m -> m.config.preAlert }),
            "config.vehicleHint" to (with(extraConfig = "\"vehicleHint\":\"bus\"") to { m -> m.config.vehicleHint == "bus" }),
            "config.params" to (with(extraConfig = "\"params\":{\"gpsLostMinS\":90}") to { m -> m.config.params != null }),
            "config.battery" to (with(extraConfig = "\"battery\":[{\"t\":0,\"levelPct\":50,\"charging\":false}]") to { m -> m.config.battery.single().levelPct == 50 }),
            "config.actions" to (with(extraConfig = "\"actions\":[{\"at\":{\"t\":5},\"action\":\"stop\"}]") to { m -> m.config.actions.single().action == "stop" }),
            "config.kill" to (with(extraConfig = "\"kill\":{\"t\":10}") to { m -> m.config.kill!!.t == 10 }),
            "config.relaunch" to (with(extraConfig = "\"kill\":{\"t\":10},\"relaunch\":{\"at\":{\"t\":20},\"fallbackStatus\":\"PENDING\"}") to { m -> m.config.relaunch!!.status == "PENDING" }),
            "config.osDismiss" to (with(extraConfig = "\"osDismiss\":{\"offsetS\":20}") to { m -> m.config.osDismissOffsetS == 20 }),
            "config.osSim" to (with(extraConfig = "\"osSim\":false") to { m -> !m.config.osSim }),
            "config.osRingMaxS" to (with(extraConfig = "\"osRingMaxS\":60") to { m -> m.config.osRingMaxS == 60 }),
        )
        val known = ExpectModel.CASE_KEYS + ExpectModel.CONFIG_KEYS.map { "config.$it" }
        assertEquals(known.toSortedSet(), probes.keys.toSortedSet()) { "keys without a semantic probe (add the meaning, then a probe)" }
        for ((key, probe) in probes) {
            val e = trace(probe.first).cases.single()
            assertNull(e.error, "$key: ${e.error}")
            assertTrue(probe.second(e.model!!), key)
        }
    }
}
