package app.napstop.core.trip.harness

import java.io.File
import java.time.Instant
import javax.xml.stream.XMLInputFactory
import javax.xml.stream.XMLStreamConstants

/** One `trkpt` (README §2). [index] = 0-based position in document order (P05 `FIX` input), [t] = seconds from start. */
internal class TraceSample(val index: Int, val t: Int, val lat: Double, val lng: Double, val accuracyM: Double, val speedMps: Double?) {
    override fun toString(): String = "TraceSample(index=$index, t=$t)"
}

internal class GpxTrace(val startMs: Long, val samples: List<TraceSample>) {
    private val byT: Map<Int, TraceSample> = samples.associateBy { it.t }

    fun at(t: Int): TraceSample? = byT[t]
}

internal object Gpx {
    private const val NS = "https://napstop.app/xmlns/trace/1"

    /** StAX reader; checks t is a multiple of [intervalS] and strictly increasing. */
    fun read(file: File, intervalS: Int): GpxTrace {
        val factory = XMLInputFactory.newInstance()
        factory.setProperty(XMLInputFactory.SUPPORT_DTD, false)
        factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false)
        val raw = ArrayList<RawPt>()
        file.inputStream().use { input ->
            val r = factory.createXMLStreamReader(input, "UTF-8")
            var cur: RawPt? = null
            var field: String? = null
            val text = StringBuilder()
            while (r.hasNext()) {
                when (r.next()) {
                    XMLStreamConstants.START_ELEMENT -> {
                        val name = r.localName
                        if (name == "trkpt") {
                            cur = RawPt(r.getAttributeValue(null, "lat").toDouble(), r.getAttributeValue(null, "lon").toDouble())
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
        require(raw.isNotEmpty()) { "gpx: no trkpt in ${file.name}" }
        val startMs = raw[0].time ?: error("gpx: trkpt without time")
        val out = ArrayList<TraceSample>(raw.size)
        var prevT = -1
        for ((i, p) in raw.withIndex()) {
            val ms = (p.time ?: error("gpx: trkpt $i without time")) - startMs
            require(ms % 1000L == 0L) { "gpx: trkpt $i time not whole seconds" }
            val t = (ms / 1000L).toInt()
            require(t % intervalS == 0) { "gpx: trkpt $i t not a multiple of the interval" }
            require(t > prevT) { "gpx: trkpt $i time not strictly increasing" }
            prevT = t
            out += TraceSample(i, t, p.lat, p.lng, p.acc ?: error("gpx: trkpt $i without acc"), p.spd)
        }
        return GpxTrace(startMs, out)
    }

    private class RawPt(val lat: Double, val lng: Double) {
        var time: Long? = null
        var acc: Double? = null
        var spd: Double? = null
    }
}
