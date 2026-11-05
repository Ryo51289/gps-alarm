package app.napstop.core.trip.runtime

import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FixFeed
import app.napstop.core.trip.runtime.support.TraceRun
import app.napstop.core.trip.runtime.support.World
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * T17 ITR30p (read-only for Android): the first Alarm (reason + trip ms from the trace start) of every L30 case, the
 * table the Swift runtime (`TripRuntimeTests`) must match. Same case filter and driver as `TraceRuntimeTest.l30`.
 * `fixtures/runtime/first-alarms.json` missing → written, then this test fails once ("run again"). An intended
 * behaviour change: delete the file and run twice.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RuntimeFirstAlarmExportTest {
    private fun goldenFile(): File = File(ExpectReader.fixturesDir.parentFile, "runtime/first-alarms.json")

    private fun row(traceId: String, caseId: String, reason: String?, atMsRel: Long?): JSONObject =
        JSONObject().apply {
            put("trace", traceId)
            put("case", caseId)
            put("reason", reason ?: JSONObject.NULL)
            put("atMsRel", atMsRel ?: JSONObject.NULL)
        }

    private fun computeRows(): List<JSONObject> {
        val rows = ArrayList<JSONObject>()
        for (id in ExpectReader.BASE_TRACES) {
            val trace = ExpectReader.read(id)
            for (c in trace.cases.filter { it.status == "final" && it.excludedKeys.isEmpty() }) {
                var out: JSONObject? = null
                runTest {
                    val world = World(this, startWall = trace.gpx.startMs)
                    world.listen()
                    val meta = ExpectReader.meta(trace, c)
                    assertEquals(StartOutcome.Started, world.now { world.runtime.start(meta, trace.destLat, trace.destLng) })
                    val run = TraceRun(world, FixFeed(trace.gpx, trace.intervalS), meta.tripId, silenceAfterMs = c.osRingMaxS?.let { it * 1000L })
                    run.run(trace.durationS, stopAtFirstAlarm = true)
                    val first = world.firstAlarm()
                    out = row(trace.traceId, c.id, first?.reason?.name, first?.let { it.atMs - trace.gpx.startMs })
                    world.now { world.runtime.userAction(meta.tripId, app.napstop.core.trip.UserActionKind.STOP_TRIP) }
                }
                rows += out!!
            }
        }
        return rows
    }

    @Test
    fun firstAlarmsMatchTheSharedTable() {
        val rows = computeRows()
        val text = JSONArray(rows).toString(2).replace("\r\n", "\n") + "\n"
        val f = goldenFile()
        if (!f.exists()) {
            f.parentFile.mkdirs()
            f.writeText(text, Charsets.UTF_8)
            error("first-alarms.json written to ${f.absolutePath}: run again")
        }
        val golden = JSONArray(f.readText(Charsets.UTF_8))
        assertEquals(golden.length(), rows.size, "row count")
        for (i in rows.indices) {
            assertEquals(golden.getJSONObject(i).toString(), rows[i].toString(), "row $i")
        }
    }
}
