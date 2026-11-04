package app.napstop.core.trip.runtime.support

import app.napstop.core.alarm.RingSettings
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.runtime.TripMeta
import java.io.File
import java.time.Instant
import javax.xml.stream.XMLInputFactory
import javax.xml.stream.XMLStreamConstants
import org.json.JSONObject

/** One `trkpt` of fixtures/traces (README §2); [t] = seconds from the start. */
class Sample(val t: Int, val lat: Double, val lng: Double, val accuracyM: Double, val speedMps: Double?) {
    override fun toString(): String = "Sample(t=$t)"
}

class Gpx(val startMs: Long, val samples: List<Sample>) {
    private val byT = samples.associateBy { it.t }

    fun at(t: Int): Sample? = byT[t]
}

/** GPX reader (README §2), StAX, no DTD / external entities. */
object GpxReader {
    private const val NS = "https://napstop.app/xmlns/trace/1"

    fun read(file: File): Gpx {
        val factory = XMLInputFactory.newInstance()
        factory.setProperty(XMLInputFactory.SUPPORT_DTD, false)
        factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false)
        class Pt(val lat: Double, val lng: Double) {
            var time: Long? = null
            var acc: Double? = null
            var spd: Double? = null
        }
        val raw = ArrayList<Pt>()
        file.inputStream().use { input ->
            val r = factory.createXMLStreamReader(input, "UTF-8")
            var cur: Pt? = null
            var field: String? = null
            val text = StringBuilder()
            while (r.hasNext()) {
                when (r.next()) {
                    XMLStreamConstants.START_ELEMENT -> {
                        val name = r.localName
                        if (name == "trkpt") {
                            cur = Pt(r.getAttributeValue(null, "lat").toDouble(), r.getAttributeValue(null, "lon").toDouble())
                        } else if (cur != null && (name == "time" || ((name == "acc" || name == "spd") && r.namespaceURI == NS))) {
                            field = name
                            text.setLength(0)
                        }
                    }
                    XMLStreamConstants.CHARACTERS, XMLStreamConstants.CDATA -> if (field != null) text.append(r.text)
                    XMLStreamConstants.END_ELEMENT -> {
                        val name = r.localName
                        if (field != null && name == field) {
                            val v = text.toString().trim()
                            when (field) {
                                "time" -> cur!!.time = Instant.parse(v).toEpochMilli()
                                "acc" -> cur!!.acc = v.toDouble()
                                "spd" -> cur!!.spd = v.toDouble()
                            }
                            field = null
                        } else if (name == "trkpt") {
                            raw += cur!!
                            cur = null
                        }
                    }
                }
            }
            r.close()
        }
        val start = raw.first().time!!
        return Gpx(start, raw.map { Sample(((it.time!! - start) / 1000L).toInt(), it.lat, it.lng, it.acc!!, it.spd) })
    }
}

/** The parts of expect.json the runtime trace tests use (README §3). */
class ExpectCase(
    val id: String,
    val status: String,
    val mode: String,
    val thresholdM: Int?,
    val thresholdMin: Int?,
    val preAlert: Boolean,
    val vehicleHint: String?,
    val excludedKeys: List<String>,
    val osRingMaxS: Int?,
    val expect: List<Window>,
    val forbid: List<String>,
    val expectOutcome: String?,
) {
    class Window(val event: String, val reason: String?, val ringNow: Boolean?, val cause: String?, val notBefore: Int, val notAfter: Int)
}

class TraceCase(
    val traceId: String,
    val vehicle: String,
    val intervalS: Int,
    val durationS: Int,
    val destLat: Double,
    val destLng: Double,
    val gpx: Gpx,
    val cases: List<ExpectCase>,
    /** truth.arrivalT: first tick at the destination waypoint (README §3). */
    val arrivalT: Int,
)

object ExpectReader {
    val fixturesDir: File get() = File(System.getProperty("napstop.fixturesDir") ?: error("napstop.fixturesDir not set"))

    fun read(traceId: String): TraceCase {
        val json = JSONObject(File(fixturesDir, "$traceId.expect.json").readText(Charsets.UTF_8))
        require(json.getInt("schemaVersion") == 1) { "schemaVersion" }
        val trace = json.getJSONObject("trace")
        val dest = json.getJSONObject("destination")
        val cases = ArrayList<ExpectCase>()
        val arr = json.getJSONArray("cases")
        for (i in 0 until arr.length()) {
            val c = arr.getJSONObject(i)
            val cfg = c.getJSONObject("config")
            val excluded =
                listOf("kill", "relaunch", "osDismiss", "params", "battery", "actions").filter { cfg.has(it) } +
                    listOf("killSweep").filter { c.has(it) }
            val windows = ArrayList<ExpectCase.Window>()
            val ex = c.getJSONArray("expect")
            for (j in 0 until ex.length()) {
                val e = ex.getJSONObject(j)
                windows +=
                    ExpectCase.Window(
                        e.getString("event"),
                        e.optString("reason").ifEmpty { null },
                        if (e.has("ringNow")) e.getBoolean("ringNow") else null,
                        e.optString("cause").ifEmpty { null },
                        e.getInt("notBefore"),
                        e.getInt("notAfter"),
                    )
            }
            val forbid = c.getJSONArray("forbid").let { f -> (0 until f.length()).map { f.getString(it) } }
            cases +=
                ExpectCase(
                    id = c.getString("id"),
                    status = c.getString("status"),
                    mode = cfg.getString("mode"),
                    thresholdM = if (cfg.has("thresholdM")) cfg.getInt("thresholdM") else null,
                    thresholdMin = if (cfg.has("thresholdMin")) cfg.getInt("thresholdMin") else null,
                    preAlert = cfg.getBoolean("preAlert"),
                    vehicleHint = cfg.optString("vehicleHint").ifEmpty { null },
                    excludedKeys = excluded,
                    osRingMaxS = if (cfg.has("osRingMaxS")) cfg.getInt("osRingMaxS") else null,
                    expect = windows,
                    forbid = forbid,
                    expectOutcome = c.optString("expectOutcome").ifEmpty { null },
                )
        }
        return TraceCase(
            traceId = trace.getString("id"),
            vehicle = trace.getString("vehicle"),
            intervalS = trace.getInt("sampleIntervalS"),
            durationS = trace.getInt("durationS"),
            destLat = dest.getDouble("lat"),
            destLng = dest.getDouble("lng"),
            gpx = GpxReader.read(File(fixturesDir, trace.getString("gpx"))),
            cases = cases,
            arrivalT = json.getJSONObject("truth").getInt("arrivalT"),
        )
    }

    val BASE_TRACES = listOf("train_hn_dh", "coach_md_tb", "bus_hn_brt01", "coach_dn_langco_tunnel", "coach_gb_phuly_overshoot", "bus_hn_brt01_noisy")

    fun meta(trace: TraceCase, c: ExpectCase, tripId: String = "${trace.traceId}-${c.id}".replace(Regex("[^A-Za-z0-9_-]"), "_").take(64)): TripMeta =
        TripMeta(
            tripId = tripId,
            destinationName = "Đích thử",
            mode =
                when (c.mode) {
                    "distance" -> AlarmMode.DISTANCE
                    "time" -> AlarmMode.TIME
                    else -> AlarmMode.SMART
                },
            distanceThresholdM = c.thresholdM,
            timeThresholdMin = c.thresholdMin,
            preAlertEnabled = c.preAlert,
            vehicleHint =
                when (c.vehicleHint ?: trace.vehicle) {
                    "train" -> VehicleKind.TRAIN
                    "coach" -> VehicleKind.COACH
                    "bus" -> VehicleKind.BUS
                    else -> VehicleKind.UNKNOWN
                },
            alarm = TestData.settings,
            engineParamsJson = null,
        )
}

object TestData {
    val settings = RingSettings("default", 0.8, true, "medium", false, false, "swipe")

    fun meta(tripId: String = "t1", mode: AlarmMode = AlarmMode.DISTANCE, distanceM: Int? = 1000, timeMin: Int? = null) =
        TripMeta(tripId, "Ga Đông Hà", mode, distanceM, timeMin, false, VehicleKind.TRAIN, settings, null)
}
