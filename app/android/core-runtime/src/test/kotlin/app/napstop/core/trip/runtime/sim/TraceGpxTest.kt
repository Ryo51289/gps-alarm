package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.GpxReader
import java.io.ByteArrayInputStream
import java.io.File
import org.json.JSONObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import org.junit.jupiter.api.assertThrows

/** SM06: the SAX reader of the bundled traces on every fixture GPX, and its error rules. */
class TraceGpxTest {
    private val dir: File get() = ExpectReader.fixturesDir

    private fun gpxIds(): List<String> =
        dir.listFiles { f -> f.name.endsWith(".gpx") }!!.map { it.name.removeSuffix(".gpx") }.filter { File(dir, "$it.expect.json").isFile }.sorted()

    @TestFactory
    fun sm06_everyFixtureGpxParsesLikeItsExpectJson(): List<DynamicTest> =
        gpxIds().map { id ->
            DynamicTest.dynamicTest(id) {
                val json = JSONObject(File(dir, "$id.expect.json").readText(Charsets.UTF_8))
                val trace = json.getJSONObject("trace")
                val samples = File(dir, "$id.gpx").inputStream().use { TraceGpx.parse(it) }
                assertEquals(trace.getInt("sampleCount"), samples.size, "$id sampleCount")
                assertEquals(0, samples.first().t)
                assertEquals(trace.getInt("durationS"), samples.last().t, "$id durationS")
                assertTrue(samples.zipWithNext().all { (a, b) -> b.t > a.t }, "$id t increasing")
                val gaps = json.getJSONObject("truth").optJSONArray("gpsGaps")
                if (gaps != null) {
                    for (i in 0 until gaps.length()) {
                        val g = gaps.getJSONObject(i)
                        val from = g.getInt("fromT")
                        val to = g.getInt("toT")
                        assertTrue(samples.none { it.t in from until to }, "$id: sample inside gap [$from, $to)")
                    }
                }
                // Same values as the StAX reader of the T15 trace tests.
                val ref = GpxReader.read(File(dir, "$id.gpx"))
                assertEquals(ref.samples.map { it.t }, samples.map { it.t })
                for ((a, b) in ref.samples.zip(samples)) {
                    assertEquals(a.lat, b.lat)
                    assertEquals(a.lng, b.lng)
                    assertEquals(a.accuracyM.toFloat(), b.accM)
                    assertEquals(a.speedMps?.toFloat(), b.spdMps)
                }
            }
        }

    @Test
    fun sm06_trainLongstopNospdHasNoSpeedWhileStopped() {
        val samples = File(dir, "train_longstop_nospd.gpx").inputStream().use { TraceGpx.parse(it) }
        assertTrue(samples.any { it.spdMps == null }, "some ticks without speed")
        assertTrue(samples.any { it.spdMps != null })
    }

    private val head =
        """<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:napstop="https://napstop.app/xmlns/trace/1">
  <metadata><time>2026-03-14T02:00:00Z</time></metadata>
  <trk><trkseg>
"""
    private val tail = "  </trkseg></trk>\n</gpx>\n"

    private fun pt(lat: String = "16.0549823", time: String = "2026-03-14T02:00:00Z", acc: String? = "8.1", spd: String? = "0.17") =
        "<trkpt lat=\"$lat\" lon=\"108.1733614\"><time>$time</time><extensions>" +
            (acc?.let { "<napstop:acc>$it</napstop:acc>" } ?: "") + (spd?.let { "<napstop:spd>$it</napstop:spd>" } ?: "") +
            "</extensions></trkpt>\n"

    private fun parse(xml: String) = TraceGpx.parse(ByteArrayInputStream(xml.toByteArray(Charsets.UTF_8)))

    private fun assertRule(xml: String, rule: String) {
        val e = assertThrows<TraceFormatException> { parse(xml) }
        assertEquals(rule, e.message)
        assertFalse(e.message!!.any { it.isDigit() }, "no value in the message: ${e.message}")
    }

    @Test
    fun sm06_brokenGpxIsATraceFormatExceptionNamingTheRuleOnly() {
        val ok = parse(head + pt() + pt(time = "2026-03-14T02:00:05Z", spd = null) + "</trkseg><trkseg>" + pt(time = "2026-03-14T02:01:00Z") + tail)
        assertEquals(listOf(0, 5, 60), ok.map { it.t })
        assertEquals(null, ok[1].spdMps)
        // Metadata time is not a sample time.
        assertEquals(3, ok.size)
        val full = head + pt() + pt(time = "2026-03-14T02:00:05Z") + tail
        assertRule(full.substring(0, full.length / 2 + 40), "xml malformed")
        assertRule(head + pt(acc = null) + tail, "acc missing")
        assertRule(head + pt(acc = "0") + tail, "acc invalid")
        assertRule(head + pt(acc = "NaN") + tail, "acc invalid")
        assertRule(head + pt(spd = "-1") + tail, "spd invalid")
        assertRule(head + pt() + pt() + tail, "time not increasing")
        assertRule(head + pt() + pt(time = "2026-03-14T01:59:00Z") + tail, "time not increasing")
        assertRule(head + pt(time = "yesterday") + tail, "time invalid")
        assertRule(head + pt(lat = "91.5") + tail, "lat out of range")
        assertRule(head + tail, "no trkpt")
    }
}
