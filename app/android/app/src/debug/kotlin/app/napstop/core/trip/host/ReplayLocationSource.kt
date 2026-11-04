package app.napstop.core.trip.host

import android.os.SystemClock
import android.util.Xml
import app.napstop.core.trip.runtime.FixSink
import app.napstop.core.trip.runtime.FlpRequestSpec
import app.napstop.core.trip.runtime.LocationSource
import app.napstop.core.trip.runtime.RawFix
import java.io.File
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.xmlpull.v1.XmlPullParser

/**
 * Debug-only replay of a fixtures/traces GPX at 1× (spec T15 §5.14, protocols LM2, LM3, LM7, LM8): trace time is
 * stretched by 1/[speedScale] and speeds multiplied by [speedScale]. Delivery follows the request like the `policy`
 * harness mode (README §6): a sample goes out when at least `intervalMs` of trace time passed since the last one.
 * After trace second [dropAfterS] nothing is delivered (simulated GPS loss). Fixes are fresh (age 0).
 */
class ReplayLocationSource(
    private val samples: List<Sample>,
    private val speedScale: Double,
    private val dropAfterS: Int?,
    private val scope: CoroutineScope,
) : LocationSource {
    class Sample(val t: Int, val lat: Double, val lng: Double, val acc: Float, val spd: Float?)

    @Volatile
    private var spec: FlpRequestSpec? = null

    @Volatile
    private var sink: FixSink? = null
    private var job: Job? = null
    private val startElapsed = SystemClock.elapsedRealtime()
    private var lastDeliveredT: Int? = null

    override fun request(spec: FlpRequestSpec, sink: FixSink) {
        this.spec = spec
        this.sink = sink
        if (job == null) job = scope.launch { play() }
    }

    override fun stop() {
        spec = null
        sink = null
    }

    override suspend fun lastKnown(): RawFix? = null

    fun cancel() {
        job?.cancel()
        job = null
    }

    private suspend fun play() {
        for (s in samples) {
            if (dropAfterS != null && s.t > dropAfterS) return
            val dueElapsed = startElapsed + (s.t * 1000.0 / speedScale).toLong()
            val wait = dueElapsed - SystemClock.elapsedRealtime()
            if (wait > 0) delay(wait)
            val sp = spec ?: continue
            val last = lastDeliveredT
            if (last != null && (s.t - last) * 1000L < sp.intervalMs) continue
            lastDeliveredT = s.t
            sink?.onFix(RawFix(s.lat, s.lng, s.acc, s.spd?.let { (it * speedScale).toFloat() }, SystemClock.elapsedRealtimeNanos())) {}
        }
    }

    companion object {
        private const val NS = "https://napstop.app/xmlns/trace/1"

        /** GPX of fixtures/traces (README §2), no DTD. */
        fun readGpx(file: File): List<Sample> {
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
            val out = ArrayList<Sample>()
            file.inputStream().use { input ->
                parser.setInput(input, "UTF-8")
                var lat = 0.0
                var lng = 0.0
                var time: Long? = null
                var acc: Float? = null
                var spd: Float? = null
                var field: String? = null
                var start: Long? = null
                while (parser.next() != XmlPullParser.END_DOCUMENT) {
                    when (parser.eventType) {
                        XmlPullParser.START_TAG ->
                            when {
                                parser.name == "trkpt" -> {
                                    lat = parser.getAttributeValue(null, "lat").toDouble()
                                    lng = parser.getAttributeValue(null, "lon").toDouble()
                                    time = null
                                    acc = null
                                    spd = null
                                }
                                parser.name == "time" -> field = "time"
                                (parser.name == "acc" || parser.name == "spd") && parser.namespace == NS -> field = parser.name
                            }
                        XmlPullParser.TEXT ->
                            when (field) {
                                "time" -> time = Instant.parse(parser.text.trim()).toEpochMilli()
                                "acc" -> acc = parser.text.trim().toFloat()
                                "spd" -> spd = parser.text.trim().toFloat()
                            }
                        XmlPullParser.END_TAG -> {
                            if (parser.name == "trkpt" && time != null && acc != null) {
                                val s0 = start ?: time.also { start = it }
                                out += Sample(((time - s0) / 1000L).toInt(), lat, lng, acc, spd)
                            }
                            field = null
                        }
                    }
                }
            }
            return out
        }
    }
}
