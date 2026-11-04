package app.napstop.core.alarm

import app.napstop.core.alarm.AlarmData.request
import app.napstop.core.trip.AlarmReason
import java.io.File
import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T16 A27–A39: AlarmControllerCore with a fake transport / book / clock and a fake `:ring` running the real machine. */
class AlarmControllerCoreTest {
    private val c = AlarmConstants()

    private inner class Rig(confirm: Boolean = true) {
        val clock = FakeRingClock()
        val facts = MemoryFacts()
        val transport = FakeTransport()
        val lost = ArrayList<Pair<String, Long>>()
        val watched = ArrayList<String>()
        val warnings = ArrayList<String>()
        val ring = FakeRing(facts, clock, c)
        val core =
            AlarmControllerCore(
                transport, facts, clock, { AlarmData.ringConfig(it) }, { t, at -> lost += t to at }, { watched += it }, c,
                { warnings += it }, { Locale.forLanguageTag("vi-VN") },
            )

        init {
            if (confirm) transport.onStart = { ring.pending += it }
        }

        /** The fake :ring handles what it got (RING_START + commands). */
        fun ringRuns() {
            ring.process(transport)
        }
    }

    @Test
    fun a27_ringNowIsRingingAtOnceThenNeedsConfirmation() {
        val r = Rig(confirm = false)
        r.core.ringNow(request())
        assertEquals(1, r.transport.started.size)
        assertTrue(r.transport.started[0].launchUi)
        assertEquals(listOf(AlarmData.TRIP), r.transport.cancelledPreAlerts)
        val f = r.core.ringFacts(AlarmData.TRIP)
        assertTrue(f.ringingNow)
        assertEquals(RingSource.ENGINE, f.ringingSource)
        assertTrue(r.watched.isNotEmpty())
        r.clock.advance(3_500)
        assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        assertEquals(60, r.transport.started[0].snoozeS)
    }

    @Test
    fun a28_deniedStartFallsBackToTheNotification() {
        val r = Rig()
        r.transport.startError = RingStartDenied("ForegroundServiceStartNotAllowedException")
        r.core.ringNow(request())
        assertEquals(1, r.transport.backups.size)
        val rec = r.facts.records[AlarmData.TRIP]!!
        assertEquals(RingMode.BACKUP, rec.mode)
        assertTrue(rec.ringing)
        assertTrue(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        r.transport.backupShowing[AlarmData.TRIP] = false
        assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        assertTrue(r.warnings.any { it.contains("ForegroundServiceStartNotAllowedException") })
    }

    @Test
    fun a29_nothingCanRingThrows() {
        for (fallback in listOf(false, true)) {
            val r = Rig()
            r.transport.startError = IllegalStateException("x")
            r.transport.backupOk = false
            val e = assertThrows(RingStartException::class.java) { if (fallback) r.core.ringFallback(request()) else r.core.ringNow(request()) }
            assertEquals("IllegalStateException", e.errorClass)
            assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        }
    }

    @Test
    fun a30_a33_oneRingPerTrip() {
        val r = Rig()
        r.core.ringNow(request())
        r.ringRuns()
        assertTrue(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        r.core.ringNow(request(reason = AlarmReason.PASSED_CLOSEST))
        assertEquals(1, r.transport.started.size)
        assertTrue(r.transport.commands.last() is RingCommand.Update)
        r.ringRuns()
        assertEquals(1, r.ring.sounds)
    }

    @Test
    fun a31_fallbackSourceIsSeenWhileStartingAndAfter() {
        val r = Rig()
        r.core.ringFallback(request(source = RingSource.FALLBACK, reason = null))
        assertEquals(RingSource.FALLBACK, r.core.ringFacts(AlarmData.TRIP).ringingSource)
        r.ringRuns()
        r.clock.advance(1_000)
        val f = r.core.ringFacts(AlarmData.TRIP)
        assertTrue(f.ringingNow)
        assertEquals(RingSource.FALLBACK, f.ringingSource)
    }

    @Test
    fun a32_afterASnoozeANewRingStarts() {
        val r = Rig()
        r.core.ringFallback(request(source = RingSource.FALLBACK, reason = null))
        r.ringRuns()
        r.ring.input(RingInput.UserSnooze(r.clock.wall))
        val f = r.core.ringFacts(AlarmData.TRIP)
        assertFalse(f.ringingNow)
        assertEquals(r.clock.wall, f.pendingSnoozeAtWallMs)
        assertEquals(RingEnd.SNOOZED, r.facts.records[AlarmData.TRIP]!!.endedBy)
        r.core.stopRinging(AlarmData.TRIP, StopCause.SNOOZED)
        assertNull(r.core.ringFacts(AlarmData.TRIP).pendingSnoozeAtWallMs)
        r.clock.advance(60_000)
        r.core.ringNow(request(reason = AlarmReason.SNOOZE_END, snoozeAllowed = false))
        assertEquals(2, r.transport.started.size)
        r.ringRuns()
        assertEquals(2, r.ring.sounds)
        assertTrue(r.core.ringFacts(AlarmData.TRIP).ringingNow)
    }

    @Test
    fun a34_stopBeforeTheRingStartArrives() {
        val r = Rig()
        r.core.ringNow(request())
        r.core.stopRinging(AlarmData.TRIP, StopCause.TRIP_ENDED)
        val rec = r.facts.records[AlarmData.TRIP]!!
        assertTrue(rec.stopSeq!! >= r.transport.started[0].ringSeq)
        assertTrue(r.transport.commands.last() is RingCommand.Stop)
        val sent = r.transport.commands.size
        r.ringRuns() // :ring gets STOP then the late RING_START
        assertEquals(0, r.ring.sounds)
        assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        r.core.stopRinging(AlarmData.TRIP, StopCause.TRIP_ENDED)
        assertEquals(sent, r.transport.commands.size)
    }

    @Test
    fun a35_overshootOnlyWhileRinging() {
        val r = Rig()
        r.core.overshoot(AlarmData.TRIP, 1_500)
        assertTrue(r.transport.commands.isEmpty())
        r.core.ringNow(request())
        r.ringRuns()
        r.core.overshoot(AlarmData.TRIP, 1_500)
        assertEquals(RingCommand.Overshoot(AlarmData.TRIP, 1_500), r.transport.commands.last())
    }

    @Test
    fun a36_preAlertAndClearTrip() {
        val r = Rig()
        val p = PreAlertRequest(AlarmData.TRIP, 3_000, 600, "Ga", byDistance = true)
        r.core.preAlert(p)
        assertEquals(listOf(p), r.transport.preAlerts)
        r.core.ringNow(request())
        r.core.clearTrip(AlarmData.TRIP)
        assertTrue(AlarmData.TRIP in r.transport.cancelledBackups)
        assertTrue(r.transport.cancelledPreAlerts.count { it == AlarmData.TRIP } >= 2)
        assertNull(r.facts.records[AlarmData.TRIP])
        assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow) // STARTING marker gone too
    }

    @Test
    fun a37_watchdogRestartsThenBackupThenSilence() {
        val r = Rig()
        r.core.ringNow(request())
        r.ringRuns()
        val started = r.facts.records[AlarmData.TRIP]!!.startedAtWallMs
        // Heartbeats for 20 s, then :ring dies.
        repeat(10) {
            r.clock.advance(2_000)
            r.ring.heartbeat()
            assertTrue(r.core.watchTick(AlarmData.TRIP))
        }
        r.ring.kill()
        r.transport.onStart = null // restarts never confirm
        var restarts = 0
        var backupAt: Long? = null
        repeat(20) {
            r.clock.advance(2_000)
            val before = r.transport.started.size
            r.core.watchTick(AlarmData.TRIP)
            if (r.transport.started.size > before) {
                restarts++
                assertEquals(started, r.transport.started.last().resumeStartedAtWallMs)
            }
            if (backupAt == null && r.transport.backups.isNotEmpty()) backupAt = r.clock.wall
        }
        assertEquals(2, restarts)
        assertNotNull(backupAt)
        assertEquals(RingMode.BACKUP, r.facts.records[AlarmData.TRIP]!!.mode)
        assertEquals(started, r.facts.records[AlarmData.TRIP]!!.startedAtWallMs)
        // The user swipes the backup notification away.
        r.transport.backupShowing[AlarmData.TRIP] = false
        r.clock.advance(2_000)
        assertFalse(r.core.watchTick(AlarmData.TRIP))
        assertEquals(listOf(AlarmData.TRIP to r.clock.wall), r.lost)
        assertEquals(RingEnd.LOST, r.facts.records[AlarmData.TRIP]!!.endedBy)
        assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow)
    }

    @Test
    fun a38_ringStartCodec() {
        val s = AlarmData.start(resume = 123L)
        assertEquals(s, RingStartCodec.fromMap(RingStartCodec.toMap(s)))
        val noSettings = AlarmData.start(request(settings = null, reason = null, distanceM = null, destinationName = null))
        assertEquals(noSettings, RingStartCodec.fromMap(RingStartCodec.toMap(noSettings)))
        // Values as they come back from a Bundle (Int / Long mixed) still decode.
        val m = RingStartCodec.toMap(s).toMutableMap()
        m["snoozeS"] = 60L
        assertEquals(s, RingStartCodec.fromMap(m))
        for (bad in listOf("tripId", "ringSeq", "source", "snoozeAllowed", "atWallMs", "launchUi", "snoozeS")) {
            assertNull(RingStartCodec.fromMap(RingStartCodec.toMap(s) - bad), bad)
        }
        assertNull(RingStartCodec.fromMap(RingStartCodec.toMap(s) + ("source" to "OTHER")))
        assertNull(RingStartCodec.fromMap(RingStartCodec.toMap(s) + ("reason" to "LOUD")))
        assertNull(RingStartCodec.fromMap(RingStartCodec.toMap(s) + ("tripId" to "a/b")))
        assertNull(RingStartCodec.fromMap(RingStartCodec.toMap(s) + ("s.volume" to "x")))
    }

    @Test
    fun a39_privacy() {
        val s = AlarmData.start()
        val content = RingCopy.content(s.request, 1_200, 60, Locale.ENGLISH)
        val texts = listOf(s.toString(), content.toString(), AlarmData.record().toString(), AlarmData.ringConfig().toString(), s.request.toString())
        for (t in texts) {
            assertFalse(t.contains(AlarmData.DEST), t)
            assertFalse(t.contains("Đồng Hới"), t)
            assertFalse(t.contains("1200") || t.contains("1,2") || t.contains("1.2"), t)
        }
        // Source scan: no println in core/alarm; :ring code imports nothing of the main runtime / Flutter / Firebase.
        val main = File(System.getProperty("napstop.mainSrcDir"), "app/napstop/core/alarm")
        for (f in main.walkTopDown().filter { it.isFile && it.extension == "kt" }) {
            val src = f.readText()
            assertFalse(src.contains("println("), f.name)
            assertFalse(src.contains("printStackTrace"), f.name)
        }
        val ringDir = File(System.getProperty("napstop.mainSrcDir")).resolve("../../../../app/src/main/kotlin/app/napstop/core/alarm/ring").canonicalFile
        val files = ringDir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue(files.size >= 10, "ring sources found: ${files.size} in $ringDir")
        for (f in files) {
            val src = f.readText()
            for (banned in listOf("RuntimeHost", "import io.flutter", "import com.google.firebase", "println(")) {
                assertFalse(src.contains(banned), "${f.name} contains $banned")
            }
        }
    }

    @Test
    fun pendingDismissBlocksANewRing() {
        val r = Rig()
        r.facts.records[AlarmData.TRIP] = AlarmData.record(ringing = false, pendingDismiss = r.clock.wall)
        r.core.ringNow(request())
        assertTrue(r.transport.started.isEmpty())
        assertTrue(r.transport.backups.isEmpty())
    }

    @Test
    fun backupDeletedSilencesOnce() {
        val r = Rig()
        r.transport.startError = RingStartDenied("x")
        r.core.ringNow(request())
        r.core.onBackupDeleted(AlarmData.TRIP)
        r.core.onBackupDeleted(AlarmData.TRIP)
        assertEquals(1, r.lost.size)
        assertEquals(RingEnd.SILENCED, r.facts.records[AlarmData.TRIP]!!.endedBy)
    }

    @Test
    fun liveRingsForTheAppHook() {
        val r = Rig()
        assertTrue(r.core.liveRings().isEmpty())
        r.core.ringNow(request())
        r.ringRuns()
        assertEquals(listOf(AlarmData.TRIP), r.core.liveRings())
    }

    /**
     * Review T16 #1, the reviewer's repro: the book of a snoozed ring from the previous boot (ringSeq = stopSeq far above
     * this boot's elapsedRealtimeNanos, bootCount 1) must not make the next ring silent.
     */
    @Test
    fun aRebootDuringASnoozeStillRings() {
        val r = Rig()
        r.facts.records[AlarmData.TRIP] =
            AlarmData.record(ringSeq = 900_000_000_000_000L, stopSeq = 900_000_000_000_000L, ringing = false, endedBy = RingEnd.SNOOZED, bootCount = 1)
        r.core.ringNow(request(reason = AlarmReason.SNOOZE_END, snoozeAllowed = false))
        assertEquals(1, r.transport.started.size)
        assertTrue(r.core.ringFacts(AlarmData.TRIP).ringingNow, "STARTING counts")
        r.ringRuns()
        assertEquals(1, r.ring.sounds)
        val rec = r.facts.records[AlarmData.TRIP]!!
        assertTrue(rec.ringing)
        assertEquals(7, rec.bootCount)
        assertTrue(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        // A stop in this boot then works as usual.
        r.core.stopRinging(AlarmData.TRIP, StopCause.TRIP_ENDED)
        r.ringRuns()
        assertFalse(r.core.ringFacts(AlarmData.TRIP).ringingNow)
        assertEquals(7, r.facts.records[AlarmData.TRIP]!!.bootCount)
    }

    @Test
    fun aStopBeforeTheRingOnAnUnknownBootWritesTheBootCount() {
        val r = Rig()
        r.core.stopRinging(AlarmData.TRIP, StopCause.TRIP_ENDED)
        assertEquals(7, r.facts.records[AlarmData.TRIP]!!.bootCount)
    }
}


/**
 * A `:ring` process in memory: the real [RingSessionMachine] over the shared [MemoryFacts]; WriteFacts goes through
 * [RingFactsMerge] as on Android. [sounds] counts StartAudio (one per new ring).
 */
class FakeRing(private val facts: MemoryFacts, private val clock: RingClock, private val c: AlarmConstants) {
    var state = RingState()
    val pending = ArrayList<RingStart>()
    var sounds = 0
    val events = ArrayList<RingFx.SendEvent>()
    private var handledCommands = 0

    fun process(t: FakeTransport) {
        val cmds = t.commands.drop(handledCommands)
        handledCommands = t.commands.size
        for (cmd in cmds) {
            when (cmd) {
                is RingCommand.Update -> input(RingInput.Update(cmd.start))
                is RingCommand.Overshoot -> input(RingInput.Overshoot(cmd.tripId, cmd.pastM))
                is RingCommand.Stop -> input(RingInput.Stop(cmd.tripId, cmd.cause, cmd.stopSeq))
                is RingCommand.Snooze -> input(RingInput.UserSnooze(cmd.atWallMs))
            }
        }
        processStarts()
    }

    /** RING_STARTs that arrived (service start). */
    fun processStarts() {
        val starts = pending.toList()
        pending.clear()
        for (s in starts) input(RingInput.Start(s, false, facts.records[s.request.tripId], clock.wallMs(), clock.elapsedMs(), clock.bootCount()))
    }

    fun input(i: RingInput) {
        val (next, fx) = RingSessionMachine.reduce(state, i, c, Locale.ENGLISH)
        state = next
        for (f in fx) {
            when (f) {
                is RingFx.WriteFacts -> facts.update(f.record.tripId) { RingFactsMerge.merge(it, f.record, RingBoot.nanosBound(clock.elapsedMs())).first }
                is RingFx.WriteStopSeq ->
                    facts.update(f.tripId) { raw ->
                        RingBoot.sanitize(raw, clock.bootCount(), RingBoot.nanosBound(clock.elapsedMs()))
                            ?.let { it.copy(stopSeq = maxOf(f.stopSeq, it.stopSeq ?: Long.MIN_VALUE), bootCount = it.bootCount ?: clock.bootCount()) }
                    }
                is RingFx.StartAudio -> sounds++
                is RingFx.SendEvent -> events += f
                RingFx.StopService -> state = RingState(stopSeqs = state.stopSeqs, pendingOvershoot = state.pendingOvershoot)
                else -> Unit
            }
        }
    }

    fun heartbeat() {
        val trip = state.tripId ?: return
        facts.update(trip) { it?.copy(heartbeatElapsedMs = clock.elapsedMs(), heartbeatWallMs = clock.wallMs()) }
    }

    fun kill() {
        state = RingState()
    }
}
