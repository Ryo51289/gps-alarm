package app.napstop.core.trip.runtime.sim

import java.io.InputStream
import java.time.Instant
import java.time.format.DateTimeParseException
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler

/**
 * Reader of the bundled GPX traces (fixtures/traces/README.md §2, T18 §4): SAX, namespace-aware [A-SAX], every
 * trk/trkseg/trkpt in document order. Same code for the JVM tests (fixtures/traces) and the app (assets/sim). Errors
 * name the rule only: never a value or a coordinate.
 */
object TraceGpx {
    const val NS = "https://napstop.app/xmlns/trace/1"

    /** Throws [TraceFormatException]; IO errors of [input] pass through as IOException. */
    fun parse(input: InputStream): List<TraceSample> {
        val factory = SAXParserFactory.newInstance()
        factory.isNamespaceAware = true
        // Our own asset, no DTD: never resolve external entities (features unknown to a parser are ignored).
        for ((feature, on) in FEATURES) {
            try {
                factory.setFeature(feature, on)
            } catch (e: Exception) {
                // Not supported by this parser (Android's Expat): it has no external entity loading anyway.
            }
        }
        val handler = Handler()
        try {
            factory.newSAXParser().parse(input, handler)
        } catch (e: TraceFormatException) {
            throw e
        } catch (e: SAXException) {
            (e.exception as? TraceFormatException)?.let { throw it }
            throw TraceFormatException("xml malformed")
        }
        if (handler.points.isEmpty()) throw TraceFormatException("no trkpt")
        val t0 = handler.points[0].timeMs
        return handler.points.map { p ->
            TraceSample(((p.timeMs - t0) / 1000L).toInt(), p.lat, p.lng, p.acc, p.spd)
        }
    }

    private val FEATURES =
        listOf(
            "http://xml.org/sax/features/external-general-entities" to false,
            "http://xml.org/sax/features/external-parameter-entities" to false,
            "http://apache.org/xml/features/nonvalidating/load-external-dtd" to false,
        )

    private class Point(val lat: Double, val lng: Double, val timeMs: Long, val acc: Float, val spd: Float?)

    private class Handler : DefaultHandler() {
        val points = ArrayList<Point>()
        private var inPoint = false
        private var lat = 0.0
        private var lng = 0.0
        private var time: Long? = null
        private var acc: Float? = null
        private var spd: Float? = null
        private var field: String? = null
        private val text = StringBuilder()

        override fun startElement(uri: String?, localName: String?, qName: String?, attributes: Attributes) {
            val name = localName?.takeIf { it.isNotEmpty() } ?: qName ?: return
            if (name == "trkpt" && uri != NS) {
                if (inPoint) throw TraceFormatException("trkpt nested")
                inPoint = true
                lat = coord(attributes.getValue("lat"), 90.0, "lat")
                lng = coord(attributes.getValue("lon"), 180.0, "lon")
                time = null
                acc = null
                spd = null
                return
            }
            if (!inPoint) return
            field =
                when {
                    name == "time" && uri != NS -> "time"
                    (name == "acc" || name == "spd") && uri == NS -> name
                    else -> null
                }
            text.setLength(0)
        }

        override fun characters(ch: CharArray, start: Int, length: Int) {
            if (field != null) text.appendRange(ch, start, start + length)
        }

        override fun endElement(uri: String?, localName: String?, qName: String?) {
            val name = localName?.takeIf { it.isNotEmpty() } ?: qName ?: return
            val f = field
            if (f != null && name == f) {
                val v = text.toString().trim()
                when (f) {
                    "time" ->
                        time =
                            try {
                                Instant.parse(v).toEpochMilli()
                            } catch (e: DateTimeParseException) {
                                throw TraceFormatException("time invalid")
                            }
                    "acc" -> acc = v.toFloatOrNull()?.takeIf { it.isFinite() && it > 0f } ?: throw TraceFormatException("acc invalid")
                    "spd" -> spd = v.toFloatOrNull()?.takeIf { it.isFinite() && it >= 0f } ?: throw TraceFormatException("spd invalid")
                }
                field = null
                return
            }
            if (name == "trkpt" && uri != NS && inPoint) {
                val t = time ?: throw TraceFormatException("time missing")
                val a = acc ?: throw TraceFormatException("acc missing")
                val prev = points.lastOrNull()
                if (prev != null && t <= prev.timeMs) throw TraceFormatException("time not increasing")
                points += Point(lat, lng, t, a, spd)
                inPoint = false
            }
        }

        private fun coord(raw: String?, limit: Double, what: String): Double {
            val v = raw?.trim()?.toDoubleOrNull() ?: throw TraceFormatException("$what missing")
            if (!v.isFinite() || v < -limit || v > limit) throw TraceFormatException("$what out of range")
            return v
        }
    }
}
