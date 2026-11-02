package app.napstop.core.trip.harness

import app.napstop.core.trip.JArray
import app.napstop.core.trip.JBool
import app.napstop.core.trip.JNumber
import app.napstop.core.trip.JObject
import app.napstop.core.trip.JString
import app.napstop.core.trip.JsonValue
import app.napstop.core.trip.MiniJson
import app.napstop.core.trip.PARAM_SPEC_BY_NAME
import java.io.File
import java.time.Instant

/** Case configuration error (must fail, never skip: README §6 point 9). */
internal class ConfigError(message: String) : RuntimeException(message)

/** `At`: static anchors carry `t`; runtime anchors (`event:*`, `relaunch`, `osFallbackFired`) have no `t`. */
internal data class At(val t: Int?, val anchor: String?, val offsetS: Int)

internal data class Filter(val event: String, val reason: String?, val ringNow: Boolean?, val cause: String?)

internal data class Expect(val filter: Filter, val notBefore: Int, val notAfter: Int)

internal data class ExpectAfter(val filter: Filter, val after: At, val lo: Int, val hi: Int)

internal data class ExpectFallback(val asOfT: Int, val notBefore: Int, val notAfter: Int)

internal data class KillSweepSpec(val from: At, val everyS: Int, val notAfter: At, val earlyFrom: At, val statsOnly: Boolean)

internal data class BatteryPoint(val t: Int, val levelPct: Int, val charging: Boolean)

internal data class ActionSpec(val at: At, val action: String)

internal data class RelaunchSpec(val at: At, val status: String)

internal data class CaseConfig(
    val mode: String,
    val thresholdM: Int?,
    val thresholdMin: Int?,
    val preAlert: Boolean,
    val vehicleHint: String?,
    val params: JObject?,
    val battery: List<BatteryPoint>,
    val actions: List<ActionSpec>,
    val kill: At?,
    val relaunch: RelaunchSpec?,
    val osDismissOffsetS: Int?,
    val osSim: Boolean,
    val osRingMaxS: Int?,
)

internal data class CaseModel(
    val id: String,
    val testIds: List<String>,
    val config: CaseConfig,
    val samplingModes: List<String>,
    val policyPhaseSweep: Boolean,
    /** T10.3 §8.2: exempt from P02 (first alarm may be the fallback, ringNow = false). */
    val allowFallbackFirst: Boolean,
    val expect: List<Expect>,
    val expectAfter: List<ExpectAfter>,
    val expectFallback: ExpectFallback?,
    val killSweep: KillSweepSpec?,
    val expectOutcome: String?,
    val expectSummaryVehicle: String?,
    val forbid: List<String>,
    val forbidMatch: List<Filter>,
    val forbidAfter: List<Pair<Filter, At>>,
)

/** A case that failed must-understand / type checks; reported as a failing test. */
internal data class CaseEntry(val id: String, val testIds: List<String>, val model: CaseModel?, val error: String?)

internal class TraceModel(
    val id: String,
    val vehicle: String,
    val gpxFile: File,
    val startMs: Long,
    val intervalS: Int,
    val durationS: Int,
    val sampleCount: Int,
    val destLat: Double,
    val destLng: Double,
    val arrivalT: Int,
    val cases: List<CaseEntry>,
    /** Number of `truth.gpsGaps` (TR39 selects traces with at least one). */
    val gpsGapCount: Int = 0,
) {
    val gpx: GpxTrace by lazy {
        val g = Gpx.read(gpxFile, intervalS)
        require(g.startMs == startMs && g.samples.size == sampleCount && g.samples.last().t == durationS) {
            "gpx/expect mismatch for $id"
        }
        g
    }
}

internal object ExpectModel {
    val CASE_KEYS = setOf(
        "id", "status", "testIds", "config", "samplingModes", "policyPhaseSweep", "allowFallbackFirst", "expect", "expectAfter", "expectFallback",
        "killSweep", "expectOutcome", "expectSummary", "forbid", "forbidMatch", "forbidAfter",
    )
    val CONFIG_KEYS = setOf(
        "mode", "thresholdM", "thresholdMin", "preAlert", "vehicleHint", "params", "battery", "actions", "kill", "relaunch",
        "osDismiss", "osSim", "osRingMaxS",
    )
    private val AT_KEYS = setOf("t", "anchor", "offsetS")
    private val FILTER_KEYS = setOf("event", "reason", "ringNow", "cause")
    val EVENT_NAMES = setOf(
        "preAlert", "alarm", "snoozed", "gpsLost", "gpsRecovered", "lowBatteryRisk", "overshoot", "arrived",
        "fallbackAlarmChanged", "samplingPolicyChanged", "tripEnded",
    )

    fun loadAll(dir: File): List<TraceModel> =
        (dir.listFiles { f -> f.name.endsWith(".expect.json") } ?: emptyArray()).sortedBy { it.name }.map { load(it) }

    fun load(file: File): TraceModel {
        val root = MiniJson.parse(file.readText(Charsets.UTF_8)) as JObject
        val ver = (root["schemaVersion"] as JNumber).asLongExact()
        require(ver == 1L) { "schemaVersion $ver not supported (consumer supports 1)" }
        val tr = root["trace"] as JObject
        val dest = root["destination"] as JObject
        val truth = root["truth"] as JObject
        val cases = (root["cases"] as JArray).items.map { parseCaseEntry(it as JObject) }
        return TraceModel(
            id = str(tr, "id"),
            vehicle = str(tr, "vehicle"),
            gpxFile = File(file.parentFile, str(tr, "gpx")),
            startMs = Instant.parse(str(tr, "startTime")).toEpochMilli(),
            intervalS = int(tr, "sampleIntervalS"),
            durationS = int(tr, "durationS"),
            sampleCount = int(tr, "sampleCount"),
            destLat = (dest["lat"] as JNumber).asDouble(),
            destLng = (dest["lng"] as JNumber).asDouble(),
            arrivalT = int(truth, "arrivalT"),
            cases = cases,
            gpsGapCount = (truth["gpsGaps"] as? JArray)?.items?.size ?: 0,
        )
    }

    private fun parseCaseEntry(o: JObject): CaseEntry {
        val id = (o["id"] as? JString)?.value ?: "<no id>"
        val testIds = (o["testIds"] as? JArray)?.items?.map { (it as JString).value } ?: emptyList()
        return try {
            CaseEntry(id, testIds, parseCase(o), null)
        } catch (e: ConfigError) {
            CaseEntry(id, testIds, null, e.message)
        } catch (e: ClassCastException) {
            CaseEntry(id, testIds, null, "wrong type in case $id")
        } catch (e: NullPointerException) {
            CaseEntry(id, testIds, null, "missing key in case $id")
        }
    }

    private fun keys(o: JObject, allowed: Set<String>, where: String) {
        for (k in o.fields.keys) if (k !in allowed) throw ConfigError("must-understand: unknown key '$k' in $where")
    }

    private fun str(o: JObject, k: String): String = (o[k] as? JString)?.value ?: throw ConfigError("missing/invalid '$k'")

    private fun int(o: JObject, k: String): Int =
        (o[k] as? JNumber)?.asLongExact()?.toInt() ?: throw ConfigError("missing/invalid '$k'")

    private fun intOrNull(o: JObject, k: String): Int? = if (o.has(k)) int(o, k) else null

    private fun bool(o: JObject, k: String): Boolean = (o[k] as? JBool)?.value ?: throw ConfigError("missing/invalid '$k'")

    private fun arr(o: JObject, k: String): List<JsonValue> = if (o.has(k)) (o[k] as? JArray)?.items ?: throw ConfigError("'$k' not an array") else emptyList()

    private fun at(v: JsonValue?, where: String): At {
        val o = v as? JObject ?: throw ConfigError("$where: not an object")
        keys(o, AT_KEYS, where)
        return At(intOrNull(o, "t"), (o["anchor"] as? JString)?.value, intOrNull(o, "offsetS") ?: 0)
    }

    private fun filter(o: JObject, where: String): Filter {
        val ev = str(o, "event")
        if (ev !in EVENT_NAMES) throw ConfigError("$where: unknown event '$ev'")
        return Filter(ev, (o["reason"] as? JString)?.value, if (o.has("ringNow")) bool(o, "ringNow") else null, (o["cause"] as? JString)?.value)
    }

    private fun parseCase(o: JObject): CaseModel {
        keys(o, CASE_KEYS, "case")
        val c = o["config"] as? JObject ?: throw ConfigError("missing config")
        keys(c, CONFIG_KEYS, "config")
        val params = c["params"]?.let { it as? JObject ?: throw ConfigError("params not an object") }
        params?.let { for (k in it.fields.keys) if (PARAM_SPEC_BY_NAME[k] == null) throw ConfigError("must-understand: unknown param '$k'") }
        val battery = arr(c, "battery").mapIndexed { i, v ->
            val b = v as JObject
            keys(b, setOf("t", "levelPct", "charging"), "battery[$i]")
            BatteryPoint(int(b, "t"), int(b, "levelPct"), bool(b, "charging"))
        }
        val actions = arr(c, "actions").mapIndexed { i, v ->
            val a = v as JObject
            keys(a, setOf("at", "action"), "actions[$i]")
            ActionSpec(at(a["at"], "actions[$i].at"), str(a, "action"))
        }
        val relaunch = c["relaunch"]?.let {
            val r = it as JObject
            keys(r, setOf("at", "fallbackStatus"), "relaunch")
            RelaunchSpec(at(r["at"], "relaunch.at"), str(r, "fallbackStatus"))
        }
        val osDismiss = c["osDismiss"]?.let {
            val d = it as JObject
            keys(d, setOf("offsetS"), "osDismiss")
            int(d, "offsetS")
        }
        val config = CaseConfig(
            mode = str(c, "mode"),
            thresholdM = intOrNull(c, "thresholdM"),
            thresholdMin = intOrNull(c, "thresholdMin"),
            preAlert = bool(c, "preAlert"),
            vehicleHint = (c["vehicleHint"] as? JString)?.value,
            params = params,
            battery = battery,
            actions = actions,
            kill = c["kill"]?.let { at(it, "kill") },
            relaunch = relaunch,
            osDismissOffsetS = osDismiss,
            osSim = if (c.has("osSim")) bool(c, "osSim") else true,
            osRingMaxS = intOrNull(c, "osRingMaxS"),
        )
        val expect = arr(o, "expect").mapIndexed { i, v ->
            val e = v as JObject
            keys(e, FILTER_KEYS + setOf("notBefore", "notAfter", "window", "ref"), "expect[$i]")
            e["window"]?.let { w ->
                val wo = w as JObject
                keys(wo, setOf("notBefore", "notAfter"), "expect[$i].window")
                wo["notBefore"]?.let { at(it, "expect[$i].window.notBefore") }
                wo["notAfter"]?.let { at(it, "expect[$i].window.notAfter") }
            }
            Expect(filter(e, "expect[$i]"), int(e, "notBefore"), int(e, "notAfter"))
        }
        val expectAfter = arr(o, "expectAfter").mapIndexed { i, v ->
            val e = v as JObject
            keys(e, FILTER_KEYS + setOf("after", "withinS", "ref"), "expectAfter[$i]")
            val w = (e["withinS"] as JArray).items.map { (it as JNumber).asLongExact()!!.toInt() }
            ExpectAfter(filter(e, "expectAfter[$i]"), at(e["after"], "expectAfter[$i].after"), w[0], w[1])
        }
        val expectFallback = o["expectFallback"]?.let {
            val e = it as JObject
            keys(e, setOf("asOfT", "notBefore", "notAfter", "window", "ref"), "expectFallback")
            e["window"]?.let { w ->
                val wo = w as JObject
                keys(wo, setOf("modeAt", "modeAtT", "killT", "estimateT", "asOfStraightM", "hintEstimateT", "toleranceS"), "expectFallback.window")
                wo["modeAt"]?.let { m -> at(m, "expectFallback.window.modeAt") }
            }
            ExpectFallback(int(e, "asOfT"), int(e, "notBefore"), int(e, "notAfter"))
        }
        val killSweep = o["killSweep"]?.let {
            val k = it as JObject
            keys(k, setOf("from", "everyS", "notAfter", "earlyFrom", "statsOnly"), "killSweep")
            KillSweepSpec(
                at(k["from"], "killSweep.from"), int(k, "everyS"), at(k["notAfter"], "killSweep.notAfter"),
                at(k["earlyFrom"], "killSweep.earlyFrom"), if (k.has("statsOnly")) bool(k, "statsOnly") else false,
            )
        }
        val summary = o["expectSummary"]?.let {
            val s = it as JObject
            keys(s, setOf("vehicleGuess"), "expectSummary")
            str(s, "vehicleGuess")
        }
        val forbid = arr(o, "forbid").map { (it as JString).value }
        val forbidMatch = arr(o, "forbidMatch").mapIndexed { i, v ->
            val f = v as JObject
            keys(f, FILTER_KEYS, "forbidMatch[$i]")
            filter(f, "forbidMatch[$i]")
        }
        val forbidAfter = arr(o, "forbidAfter").mapIndexed { i, v ->
            val f = v as JObject
            keys(f, FILTER_KEYS + setOf("after"), "forbidAfter[$i]")
            filter(f, "forbidAfter[$i]") to at(f["after"], "forbidAfter[$i].after")
        }
        val modes = arr(o, "samplingModes").map { (it as JString).value }.ifEmpty { listOf("all", "policy") }
        // T10.3 / T11.2 §3: V14 bool, V15 not with kill or killSweep, V16 needs an expected alarm with ringNow false.
        val allowFallbackFirst = if (o.has("allowFallbackFirst")) {
            (o["allowFallbackFirst"] as? JBool)?.value ?: throw ConfigError("allowFallbackFirst must be true or false")
        } else {
            false
        }
        if (allowFallbackFirst) {
            if (config.kill != null || killSweep != null) throw ConfigError("allowFallbackFirst cannot be used with config.kill or killSweep")
            if (expect.none { it.filter.event == "alarm" && it.filter.ringNow == false }) {
                throw ConfigError("allowFallbackFirst needs an expect entry for alarm with ringNow false")
            }
        }
        return CaseModel(
            id = str(o, "id"),
            testIds = arr(o, "testIds").map { (it as JString).value },
            config = config,
            samplingModes = modes,
            policyPhaseSweep = if (o.has("policyPhaseSweep")) bool(o, "policyPhaseSweep") else false,
            allowFallbackFirst = allowFallbackFirst,
            expect = expect,
            expectAfter = expectAfter,
            expectFallback = expectFallback,
            killSweep = killSweep,
            expectOutcome = (o["expectOutcome"] as? JString)?.value,
            expectSummaryVehicle = summary,
            forbid = forbid,
            forbidMatch = forbidMatch,
            forbidAfter = forbidAfter,
        )
    }
}
