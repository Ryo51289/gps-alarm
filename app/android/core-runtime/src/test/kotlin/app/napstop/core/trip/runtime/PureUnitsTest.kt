package app.napstop.core.trip.runtime

import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSource
import app.napstop.core.trip.AccuracyLevel
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.ExpectReader
import app.napstop.core.trip.runtime.support.FakeScheduler
import app.napstop.core.trip.runtime.support.FakeTime
import app.napstop.core.trip.runtime.support.OpLog
import app.napstop.core.trip.runtime.support.TestData
import java.io.File
import java.nio.file.Files
import java.util.Locale
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Pure parts: L01–L05, L17, L19, L20, L23, L28, L40, L43. */
class PureUnitsTest {
    // ------------------------------------------------------------------ L01–L03 trip clock

    @Test
    fun l01_tripClockFollowsElapsedAndNeverGoesBack() {
        val time = FakeTime(wallBase = 1_000_000, elapsedBase = 50_000)
        val clock = TripClock(TripClock.anchorNow(time), time)
        assertEquals(1_000_000, clock.now())
        time.elapsedBase += 30_000
        time.wallBase -= 10_000 // wall clock set back
        assertEquals(1_030_000, clock.now())
        assertTrue(clock.now() >= 1_030_000)
        // A floor (restore) is never undercut.
        val floored = TripClock(ClockAnchor(0, time.elapsedMs(), 7), time, floorMs = 5_000_000)
        assertEquals(5_000_000, floored.now())
    }

    @Test
    fun l02_anchorValidity() {
        val time = FakeTime(bootCountValue = 8, elapsedBase = 10_000)
        assertFalse(TripClock.anchorValid(ClockAnchor(1, 5_000, 7), time))
        assertTrue(TripClock.anchorValid(ClockAnchor(1, 5_000, 8), time))
        val unreadable = FakeTime(bootCountValue = null, elapsedBase = 10_000)
        assertFalse(TripClock.anchorValid(ClockAnchor(1, 20_000, null), unreadable)) // elapsed went back: rebooted
        assertTrue(TripClock.anchorValid(ClockAnchor(1, 5_000, null), unreadable))
        val fresh = TripClock.anchorNow(time)
        assertEquals(time.wallMs(), fresh.wallMs)
        assertEquals(8, fresh.bootCount)
    }

    @Test
    fun l03_tripTimeToOsTimes() {
        val time = FakeTime(wallBase = 2_000_000, elapsedBase = 5_000)
        val clock = TripClock(ClockAnchor(1_000_000, 5_000, 7), time)
        assertEquals(1_000_000, clock.now())
        assertEquals(65_000, clock.toElapsed(1_060_000))
        assertEquals(2_060_000, clock.toWall(1_060_000))
        assertEquals(2_000_000, clock.toWall(990_000)) // in the past: now
        assertEquals(1_000_000 - 30_000, clock.toTrip(1_970_000))
        assertEquals(1_000_000, clock.toTrip(2_500_000)) // future wall time: now
    }

    // ------------------------------------------------------------------ L04, L05 mappers

    @Test
    fun l04_fixMapperAgesAndDrops() {
        val now = 10_000_000_000L
        val raw = RawFix(16.0, 108.0, 12f, null, now - 84_873L * 1_000_000L)
        val fix = FixMapper.map(raw, 5_000_000, now)!!
        assertEquals(5_000_000, fix.atMs)
        assertEquals(5_000_000 - 84_873, fix.fixAtMs)
        assertNull(fix.speedMps)
        assertEquals(12.0, fix.accuracyM)
        assertNull(FixMapper.map(raw.copy(accuracyM = null), 1, now))
        assertNull(FixMapper.map(raw.copy(accuracyM = 0f), 1, now))
        assertNull(FixMapper.map(raw.copy(accuracyM = Float.NaN), 1, now))
        // A fix stamped after "now" (clock skew) has age 0.
        assertEquals(1, FixMapper.map(raw.copy(elapsedRealtimeNanos = now + 5), 1, now)!!.fixAtMs)
    }

    @Test
    fun l05_flpSpecPerTier() {
        val p = EngineParams()
        val sparse = FlpMapper.spec(SamplingPolicy(SamplingTier.SPARSE, 180, 90, AccuracyLevel.BALANCED), p)
        assertEquals(FlpRequestSpec(FlpPriority.BALANCED_POWER_ACCURACY, 180_000, 90_000, 0, 60_000), sparse)
        val medium = FlpMapper.spec(SamplingPolicy(SamplingTier.MEDIUM, 30, 15, AccuracyLevel.HIGH), p)
        assertEquals(FlpRequestSpec(FlpPriority.HIGH_ACCURACY, 30_000, 15_000, 0, 30_000), medium)
        val dense = FlpMapper.spec(SamplingPolicy(SamplingTier.DENSE, 5, 2, AccuracyLevel.HIGH), p)
        assertEquals(FlpRequestSpec(FlpPriority.HIGH_ACCURACY, 5_000, 2_000, 0, 5_000), dense)
        val maxSaving = FlpMapper.spec(SamplingPolicy(SamplingTier.SPARSE, 360, 180, AccuracyLevel.BALANCED), p)
        assertEquals(FlpRequestSpec(FlpPriority.BALANCED_POWER_ACCURACY, 360_000, 180_000, 0, 60_000), maxSaving)
    }

    // ------------------------------------------------------------------ L28 wake policy

    @Test
    fun l28_wakeMechanism() {
        val meta = TestData.meta()
        val view = EngineStates.drive(meta, 1_000_000, 30_000.0, 30).view
        val p = view.predictedAlarmAtMs!!
        assertEquals(TripPhase.TRACKING, view.phase)
        assertEquals(WakeMechanism.INEXACT_IDLE, WakePolicy.mechanism(view, p + 1_000, canScheduleExact = false, nearWakeUsesAlarmClock = true))
        assertEquals(WakeMechanism.ALARM_CLOCK, WakePolicy.mechanism(view, p + 1_000, canScheduleExact = true, nearWakeUsesAlarmClock = true))
        assertEquals(WakeMechanism.EXACT_IDLE, WakePolicy.mechanism(view, p + 1_000, canScheduleExact = true))
        assertEquals(WakeMechanism.EXACT_IDLE, WakePolicy.mechanism(view, p + 5_000, canScheduleExact = true, nearWakeUsesAlarmClock = true))
        assertFalse(RuntimeConstants.NEAR_WAKE_USES_ALARM_CLOCK)
    }

    // ------------------------------------------------------------------ L40 notice text

    private val vi =
        NoticeTemplates(
            "Đang theo dõi tới %1\$s", "Đang tìm vị trí…", "Còn %1\$s · khoảng %2\$s phút", "Còn %1\$s",
            "Đang ước tính · còn khoảng %1\$s", "Đang báo thức", "Báo lại lúc %1\$s", "nơi đến",
        )

    private fun notice(phase: TripPhase, d: Int?, eta: Int?, est: Boolean = false, until: Long? = null) =
        TrackingNotice("t1", "Ga Đông Hà", phase, d?.let { NoticeFormatter.roundedDistanceM(it.toDouble()) }, eta?.let { NoticeFormatter.minutes(it) * 60 }, est, until)

    @Test
    fun l40_noticeFormatter() {
        val viL = Locale.forLanguageTag("vi")
        val en = Locale.ENGLISH
        assertEquals("850 m", NoticeFormatter.distance(850.4, viL))
        assertEquals("1,2 km", NoticeFormatter.distance(1249.0, viL))
        assertEquals("1.2 km", NoticeFormatter.distance(1249.0, en))
        assertEquals("12,3 km", NoticeFormatter.distance(12345.0, viL))
        assertEquals("1 km", NoticeFormatter.distance(995.0, viL))
        assertEquals(1, NoticeFormatter.minutes(59))
        assertEquals(10, NoticeFormatter.minutes(600))
        assertEquals(1, NoticeFormatter.minutes(0))
        val fmt = { _: Long -> "07:05" }
        assertEquals("Còn 850 m · khoảng 1 phút", NoticeFormatter.body(notice(TripPhase.TRACKING, 850, 59), vi, viL, fmt))
        assertEquals("Còn 1,2 km · khoảng 10 phút", NoticeFormatter.body(notice(TripPhase.TRACKING, 1249, 600), vi, viL, fmt))
        assertEquals("Còn 12,3 km", NoticeFormatter.body(notice(TripPhase.TRACKING, 12345, null), vi, viL, fmt))
        assertEquals("Đang ước tính · còn khoảng 1,2 km", NoticeFormatter.body(notice(TripPhase.TRACKING, 1249, 600, est = true), vi, viL, fmt))
        assertEquals("Báo lại lúc 07:05", NoticeFormatter.body(notice(TripPhase.SNOOZED, null, null, until = 1L), vi, viL, fmt))
        assertEquals("Đang tìm vị trí…", NoticeFormatter.body(notice(TripPhase.ACQUIRING, null, null), vi, viL, fmt))
        assertEquals("Đang báo thức", NoticeFormatter.body(notice(TripPhase.ALARMING, 100, 5), vi, viL, fmt))
        assertEquals("Đang theo dõi tới Ga Đông Hà", NoticeFormatter.title("Ga Đông Hà", vi))
        assertEquals("Đang theo dõi tới nơi đến", NoticeFormatter.title(null, vi))
        // Notices equal exactly when the text is equal (throttling compares notices).
        assertEquals(notice(TripPhase.TRACKING, 1249, 600), notice(TripPhase.TRACKING, 1211, 590))
    }

    // ------------------------------------------------------------------ L17 store

    @Test
    fun l17_storedTripRoundTripAndCorruptFiles() {
        val meta = TestData.meta().copy(engineParamsJson = "{\"x\": \"a=b:c #d !e\\n\"}")
        val step = EngineStates.drive(meta, 1_000_000, 30_000.0, 30)
        val t = EngineStates.stored(meta, step, ClockAnchor(1_000_000, 50_000, 7), 1_234)
        val back = RuntimeCodec.decodeTrip(RuntimeCodec.encodeTrip(t))
        assertEquals(TripEngine.encodeSnapshot(t.engine), TripEngine.encodeSnapshot(back.engine))
        assertEquals(t.meta, back.meta)
        assertEquals(t.anchor, back.anchor)
        assertEquals(1_234, back.savedAtWallMs)
        val dir = Files.createTempDirectory("t15store").toFile()
        val warnings = ArrayList<String>()
        val store = FileRuntimeStore(dir, warnings::add)
        store.writeActive(t)
        assertEquals(TripEngine.encodeSnapshot(t.engine), TripEngine.encodeSnapshot(store.readActive()!!.engine))
        val file = File(dir, FileRuntimeStore.ACTIVE_FILE)
        file.writeText(file.readText().replace("runtimeVersion=1", "runtimeVersion=2"))
        assertNull(store.readActive())
        assertFalse(file.exists(), "unknown version deleted")
        store.writeActive(t)
        file.writeText(file.readText().replace("\"snapshotVersion\"", "\"snapshotVersionX\""))
        assertNull(store.readActive())
        assertFalse(file.exists(), "corrupt engine snapshot deleted")
        assertTrue(warnings.all { it.startsWith("snapshot invalid (") }, "$warnings")
        // Ledger, ring config, finished.
        val l = FallbackLedger(1, "t1", 7, FallbackSlotRec(1, 6, 99, 98), null, FiredRec(5, 90, null, 91))
        store.writeLedger(l)
        assertEquals(l, store.readLedger())
        val rc = RingConfig("t1", "Ga = Đông Hà", TestData.settings, 1, 1)
        store.writeRingConfig(rc)
        assertEquals(rc, store.readRingConfig())
        dir.deleteRecursively()
    }

    // ------------------------------------------------------------------ L19 finished record

    @Test
    fun l19_finishedRecordFromEndedStateEqualsTheSummary() {
        var compared = 0
        for (id in ExpectReader.BASE_TRACES) {
            val trace = ExpectReader.read(id)
            for (c in trace.cases.filter { it.excludedKeys.isEmpty() }) {
                val meta = ExpectReader.meta(trace, c)
                val cfg = app.napstop.core.trip.TripConfig(meta.tripId, trace.destLat, trace.destLng, meta.mode, meta.distanceThresholdM, meta.timeThresholdMin, meta.preAlertEnabled, meta.vehicleHint)
                for (endAction in listOf(UserActionKind.STOP_TRIP, UserActionKind.DISMISS)) {
                    var step = TripEngine.start(cfg, EngineParams(), trace.gpx.startMs)
                    for (s in trace.gpx.samples) {
                        val t = trace.gpx.startMs + s.t * 1000L
                        step = TripEngine.reduce(step.state, LocationFix(t, t, s.lat, s.lng, s.accuracyM, s.speedMps))
                    }
                    val end = TripEngine.reduce(step.state, UserAction(step.state.nowMs + 1000, endAction))
                    val ended = end.events.filterIsInstance<TripEnded>().single()
                    assertEquals(FinishedRecordBuilder.fromEvent(meta.tripId, ended), FinishedRecordBuilder.fromEnded(end.state), "$id/${c.id}/$endAction")
                    compared++
                }
            }
        }
        assertTrue(compared >= 24)
        assertNull(FinishedRecordBuilder.fromEnded(EngineStates.drive(TestData.meta(), 1, 30_000.0, 3).state))
    }

    // ------------------------------------------------------------------ L20 restore planner

    @Test
    fun l20_restorePlannerTable() {
        val meta = TestData.meta()
        val base = EngineStates.drive(meta, 1_000_000, 30_000.0, 30).state
        val now = base.nowMs + 60_000
        val fbFuture = base.copy(fallback = FallbackState(now + 600_000, base.nowMs, FallbackStatus.CONFIRMED, base.nowMs, false, false))
        val fbPast = base.copy(fallback = FallbackState(now - 1_000, base.nowMs, FallbackStatus.CONFIRMED, base.nowMs, false, false))
        val noFb = base.copy(fallback = FallbackState.CLEARED)
        val toTrip = { w: Long -> w - 1_000L } // wall = trip + 1 s
        val empty = FallbackLedger.EMPTY.copy(activeTripId = meta.tripId)
        fun plan(s: app.napstop.core.trip.EngineState, l: FallbackLedger = empty, f: RingFacts = RingFacts.NONE, c: RestoreCause = RestoreCause.PROCESS_START) =
            RestorePlanner.plan(s, l, f, c, now, toTrip)
        // (a)
        val dismissed = plan(fbFuture, f = RingFacts(false, null, 5_000_000, 5_060_000, null))
        assertEquals(FallbackRestoreStatus.DISMISSED, dismissed.status)
        assertEquals(4_999_000, dismissed.firedAtMs)
        assertEquals(5_059_000, dismissed.dismissedAtMs)
        // (b)
        val firedLater = empty.copy(lastFired = FiredRec(3, 9, base.nowMs + 10_000, base.nowMs + 11_000))
        assertEquals(FallbackRestoreStatus.RANG, plan(fbFuture, firedLater).status)
        assertEquals(base.nowMs + 10_000, plan(fbFuture, firedLater).firedAtMs)
        // (b) with a record written before the runtime loaded: wall time is used.
        val firedNoTrip = empty.copy(lastFired = FiredRec(3, 9, null, base.nowMs + 11_000))
        assertEquals(RestoreInfoOf(FallbackRestoreStatus.RANG, base.nowMs + 10_000), plan(fbFuture, firedNoTrip).let { RestoreInfoOf(it.status, it.firedAtMs) })
        // (c)
        val firedBefore = empty.copy(lastFired = FiredRec(3, 9, base.nowMs - 10, base.nowMs))
        assertEquals(FallbackRestoreStatus.PENDING, plan(fbFuture, firedBefore).status)
        assertEquals(FallbackRestoreStatus.MISSING, plan(fbPast, firedBefore).status)
        // (d), (e)
        assertEquals(FallbackRestoreStatus.MISSING, plan(fbFuture, c = RestoreCause.BOOT).status)
        assertEquals(FallbackRestoreStatus.MISSING, plan(fbFuture, c = RestoreCause.PACKAGE_REPLACED).status)
        // (f), (g), (h)
        assertEquals(FallbackRestoreStatus.MISSING, plan(fbPast).status)
        assertEquals(FallbackRestoreStatus.PENDING, plan(fbFuture).status)
        assertEquals(FallbackRestoreStatus.PENDING, plan(noFb).status)
    }

    private data class RestoreInfoOf(val status: FallbackRestoreStatus, val firedAtMs: Long?)

    // ------------------------------------------------------------------ L23 fallback slots

    @Test
    fun l23_newSlotFirstThenCancelOldAndKeepOldOnFailure() =
        runBlocking {
            val log = OpLog()
            val os = FakeScheduler(log)
            val warnings = ArrayList<String>()
            val saved = ArrayList<FallbackLedger>()
            val s = FallbackScheduler(os, warnings::add)
            val l0 = FallbackLedger(1, "t1", 5, FallbackSlotRec(0, 4, 1_000, 1), null, null)
            os.slots[0] = FakeScheduler.Fallback(0, "t1", 4, 1_000, 1_000, true)
            val r1 = s.schedule(l0, "t1", 2_000, 2_000, 10) { saved += it }
            assertTrue(r1.ok)
            assertEquals(listOf("setFallback(1,2000)", "cancelFallback(0)"), log.ops)
            assertEquals(1, r1.ledger.current!!.slot)
            assertEquals(5, r1.ledger.current!!.generation)
            assertEquals(6, r1.ledger.nextGeneration)
            assertNull(r1.ledger.stale)
            // The ledger was saved with both slots before the cancel (process death in between keeps a record).
            assertEquals(0, saved.first().stale!!.slot)
            log.ops.clear()
            os.throwOnSetFallback = { IllegalStateException("x") }
            val r2 = s.schedule(r1.ledger, "t1", 3_000, 3_000, 20) { saved += it }
            assertFalse(r2.ok)
            assertTrue(log.ops.isEmpty(), "nothing cancelled: ${log.ops}")
            assertEquals(r1.ledger, r2.ledger)
            assertTrue(os.slots.containsKey(1))
            assertEquals(listOf("fallback set failed (IllegalStateException)"), warnings)
            // Without the exact permission: set (inexact) but ok = false.
            os.throwOnSetFallback = null
            os.canExact = false
            val r3 = s.schedule(r1.ledger, "t1", 3_000, 3_000, 20) {}
            assertFalse(r3.ok)
            assertEquals(0, r3.ledger.current!!.slot)
        }

    // ------------------------------------------------------------------ L43 privacy

    @Test
    fun l43_toStringsRedactAndNoPrintln() {
        val meta = TestData.meta()
        val lat = 16.8163123
        val strings =
            listOf(
                RawFix(lat, 107.1003456, 5f, 3f, 1).toString(),
                EngineStates.stored(meta, EngineStates.drive(meta, 1, 30_000.0, 3), ClockAnchor(1, 2, 3)).toString(),
                meta.toString(),
                RingRequest("t1", RingSource.ENGINE, null, true, 1234, 60, 50, "Ga Đông Hà", TestData.settings, 1).toString(),
                app.napstop.core.alarm.PreAlertRequest("t1", 4321, 60, "Ga Đông Hà").toString(),
                TrackingNotice("t1", "Ga Đông Hà", TripPhase.TRACKING, 1234, 60, false, null).toString(),
                RingConfig("t1", "Ga Đông Hà", TestData.settings, 0, 1).toString(),
            )
        for (s in strings) {
            assertFalse(s.contains("16.81") || s.contains("107.10") || s.contains("Đông Hà") || s.contains("1234") || s.contains("4321"), s)
        }
        val src = File(System.getProperty("napstop.mainSrcDir"))
        val offenders = src.walkTopDown().filter { it.isFile && it.extension == "kt" }.filter { f ->
            f.readLines().any { l -> !l.trimStart().startsWith("//") && (l.contains("println(") || Regex("\\bprint\\(").containsMatchIn(l)) }
        }.toList()
        assertTrue(offenders.isEmpty(), "println in main sources: $offenders")
        assertEquals(AlarmMode.DISTANCE, meta.mode)
    }
}
