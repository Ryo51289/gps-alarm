package app.napstop.core.bridge.stub

import app.napstop.core.bridge.AlarmMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.BridgeTestData.expectFlutterError
import app.napstop.core.bridge.SimulationMsg
import app.napstop.core.bridge.TripEndedMsg
import app.napstop.core.bridge.TripPhaseMsg
import app.napstop.core.bridge.TripStateUpdateMsg
import app.napstop.core.bridge.TripUpdateMsg
import java.io.File
import java.io.IOException
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Runnable
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** K14-K20 (spec T14 §5.2, §5.3) + review T14 M1-M4. */
@OptIn(ExperimentalCoroutinesApi::class)
class StubTripBackendTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val t0 = 1_700_000_000_000L
    private var nowMs = t0
    private val warnings = mutableListOf<String>()
    private val sim60 = SimulationMsg(StubScenario.NORMAL.asset, 60.0)

    private fun TestScope.backend(
        dir: File = tmp.root,
        scope: CoroutineScope = backgroundScope,
        clock: () -> Long = { nowMs },
        io: CoroutineDispatcher = StandardTestDispatcher(testScheduler),
    ) = StubTripBackend(
        store = StubStore(dir, warn = { warnings += it }),
        clock = clock,
        scope = scope,
        io = io,
        warn = { warnings += it },
    )

    /** Wraps [delegate]; while [held], dispatched blocks wait until [release]. */
    private class GatedDispatcher(private val delegate: CoroutineDispatcher) : CoroutineDispatcher() {
        var held = false
        private val queued = ArrayDeque<Pair<CoroutineContext, Runnable>>()
        val queuedCount get() = queued.size

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            if (held) queued.addLast(context to block) else delegate.dispatch(context, block)
        }

        fun release() {
            held = false
            while (queued.isNotEmpty()) {
                val (context, block) = queued.removeFirst()
                delegate.dispatch(context, block)
            }
        }
    }

    private val activeFile get() = File(tmp.root, StubStore.ACTIVE_FILE)

    @Test
    fun k14_currentTripIsReadFromTheSnapshotAfterProcessDeath() =
        runTest {
            // T14.1: engineParamsJson survives byte for byte (Properties escapes = : # \ and newlines).
            val params = "{\"smartTargetS\": 300.0, \"k\": \"a=b:c #d\\\\e\\n\"}\n"
            val cfg = config(destinationName = "Ga Đông Hà — Quảng Trị", engineParamsJson = params)
            backend().startTrip(cfg, 16.8163, 107.1003, sim60)
            assertTrue(activeFile.exists())
            val text = activeFile.readText()
            assertFalse("no coordinates on disk", text.contains("16.8163") || text.contains("107.1003"))

            // "New process": a fresh backend on the same directory, 15 s later (= 900 s virtual).
            nowMs = t0 + 15_000
            val revived = backend()
            val trip = revived.currentTrip()
            assertNotNull(trip)
            trip!!
            assertEquals(cfg, trip.config)
            assertEquals(params, trip.config.engineParamsJson)
            assertEquals(sim60, trip.simulation)
            assertEquals("t1", trip.state.tripId)
            assertEquals(TripPhaseMsg.ALARMING, trip.state.phase)
            assertEquals(nowMs, trip.state.atMs)

            val received = mutableListOf<TripUpdateMsg>()
            val handle = revived.addListener { received += it }
            runCurrent()
            assertEquals(1, received.size)
            assertTrue(received.single() is TripStateUpdateMsg)
            handle.remove()
        }

    @Test
    fun k15_corruptOrUnknownSnapshotIsDropped() =
        runTest {
            activeFile.writeText("version=1\nphase=WHAT\n")
            assertNull(backend().currentTrip())
            assertFalse(activeFile.exists())

            activeFile.writeBytes(byteArrayOf(0, 1, 2, 3, 92, 117))
            assertNull(backend().currentTrip())
            assertFalse(activeFile.exists())

            backend().startTrip(config(), 16.8, 107.1, sim60)
            activeFile.writeText(activeFile.readText().replace("version=1", "version=2"))
            assertNull(backend().currentTrip())
            assertFalse(activeFile.exists())
            assertEquals(3, warnings.size)
            assertTrue(warnings.none { it.contains("t1") })
        }

    @Test
    fun k16_secondStartIsTripActive() =
        runTest {
            val b = backend()
            b.startTrip(config("t1"), 16.8, 107.1, null)
            val e = expectFlutterError { b.startTrip(config("t2"), 16.8, 107.1, null) }
            assertEquals("trip-active", e.code)
            b.stopTrip("t1")
            b.startTrip(config("t2"), 16.8, 107.1, null)
            assertEquals("t2", b.currentTrip()!!.config.tripId)
            // No simulation: NORMAL at 1x, and currentTrip() says so (review M4), also after process death.
            assertNull(b.currentTrip()!!.simulation)
            assertNull(backend().currentTrip()!!.simulation)
        }

    @Test
    fun k17_commandsForAnotherTripAreNoOps() =
        runTest {
            val b = backend()
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000 // alarming
            val before = b.currentTrip()!!
            b.dismiss("t2")
            b.snooze("t2")
            b.setBatteryChoice("t2", BatteryChoiceMsg.MAX_SAVING)
            b.stopTrip("t2")
            val after = b.currentTrip()!!
            assertEquals(before, after)
            assertEquals(TripPhaseMsg.ALARMING, after.state.phase)
            assertNull(after.state.batteryChoice)
            assertTrue(b.pendingFinishedTrips().isEmpty())
        }

    @Test
    fun k18_finishedQueueIsDurableAndAckable() =
        runTest {
            val b = backend()
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs += 1_000
            b.stopTrip("t1")
            nowMs += 1_000
            b.startTrip(config("t2"), 16.8, 107.1, sim60)
            nowMs += 15_000
            b.snooze("t2")
            nowMs += 100
            b.dismiss("t2")
            assertNull(b.currentTrip())

            val pending = backend().pendingFinishedTrips()
            assertEquals(listOf("t1", "t2"), pending.map { it.tripId })
            assertTrue(pending[0].endedAtMs < pending[1].endedAtMs)
            assertEquals(1L, pending[1].snoozeCount)

            backend().ackFinishedTrips(listOf("t1", "x", "../active_trip"))
            assertEquals(listOf("t2"), backend().pendingFinishedTrips().map { it.tripId })
        }

    @Test
    fun k18_expiredTripIsRecordedOnTheNextCall() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            assertEquals(TripPhaseMsg.ALARMING, backend().currentTrip()!!.state.phase)
            // Process dead for longer than an hour of virtual time after the alarm.
            nowMs += 61_000
            val pending = backend().pendingFinishedTrips()
            assertEquals("t1", pending.single().tripId)
            assertFalse(activeFile.exists())
            assertNull(backend().currentTrip())
        }

    @Test
    fun k19_listenerReplayThenOneUpdatePerTick() =
        runTest {
            val b = backend(clock = { t0 + testScheduler.currentTime })
            val received = mutableListOf<TripUpdateMsg>()

            // No trip: attaching sends nothing.
            b.addListener { received += it }.remove()
            val idle = b.addListener { received += it }
            advanceTimeBy(3_000)
            runCurrent()
            assertTrue(received.isEmpty())
            idle.remove()

            b.startTrip(config(), 16.8, 107.1, null)
            val handle = b.addListener { received += it }
            runCurrent()
            assertEquals(1, received.size)
            assertTrue(received.single() is TripStateUpdateMsg)

            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(4, received.size)
            assertTrue(received.all { it is TripStateUpdateMsg })

            handle.remove()
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(4, received.size)
        }

    @Test
    fun k19_startingWithAListenerStartsTicking() =
        runTest {
            val b = backend(clock = { t0 + testScheduler.currentTime })
            val received = mutableListOf<TripUpdateMsg>()
            val handle = b.addListener { received += it }
            runCurrent()
            b.startTrip(config(), 16.8, 107.1, sim60)
            assertEquals(1, received.size) // the start step
            advanceTimeBy(20_000)
            runCurrent()
            assertTrue(received.any { it is AlarmMsg })
            handle.remove()
        }

    @Test
    fun k19_tickingStopsAfterTheTripEnds() =
        runTest {
            val b = backend(clock = { t0 + testScheduler.currentTime })
            val received = mutableListOf<TripUpdateMsg>()
            b.startTrip(config(), 16.8, 107.1, sim60)
            b.addListener { received += it }
            runCurrent()
            b.stopTrip("t1")
            assertTrue(received.last() is TripEndedMsg)
            val count = received.size
            advanceTimeBy(5_000)
            runCurrent()
            assertEquals(count, received.size)
        }

    @Test
    fun k20_unknownSimulationAsset() =
        runTest {
            val e = expectFlutterError { backend().startTrip(config(), 16.8, 107.1, SimulationMsg("assets/x.gpx", 60.0)) }
            assertEquals("simulation-unavailable", e.code)
            assertFalse(e.message.orEmpty().contains("assets/x.gpx"))
            assertNull(backend().currentTrip())
        }

    @Test
    fun m1_removingOneListenerKeepsTheOtherReceiving() =
        runTest {
            val b = backend(clock = { t0 + testScheduler.currentTime })
            b.startTrip(config(), 16.8, 107.1, null)
            val first = mutableListOf<TripUpdateMsg>()
            val second = mutableListOf<TripUpdateMsg>()
            val firstHandle = b.addListener { first += it }
            runCurrent()
            val secondHandle = b.addListener { second += it }
            runCurrent()
            // The replay Step of the new listener goes to every listener.
            assertEquals(2, first.size)
            assertEquals(1, second.size)

            firstHandle.remove()
            firstHandle.remove() // idempotent: must not remove the other listener
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(2, first.size)
            assertEquals(4, second.size)
            assertTrue(second.all { it is TripStateUpdateMsg })

            secondHandle.remove()
            advanceTimeBy(3_000)
            runCurrent()
            assertEquals(4, second.size)
        }

    @Test
    fun m2_listenerRemovedDuringTheWriteStillCommitsTheStep() =
        runTest {
            val gate = GatedDispatcher(StandardTestDispatcher(testScheduler))
            val b = backend(io = gate)
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            assertEquals(TripPhaseMsg.ALARMING, b.currentTrip()!!.state.phase)
            // Unanswered for more than an hour of virtual time: the next Step ends the trip.
            nowMs += 61_000
            val endedAt = nowMs

            gate.held = true
            val received = mutableListOf<TripUpdateMsg>()
            val handle = b.addListener { received += it }
            runCurrent()
            assertEquals("replay Step waits in its disk write", 1, gate.queuedCount)
            handle.remove() // Dart stops listening: the replay coroutine is cancelled mid-write
            runCurrent()
            gate.release()
            runCurrent()

            assertTrue(received.isEmpty())
            assertFalse(activeFile.exists())
            // Memory agrees with disk: the trip is over, the Step is not computed again
            // (which would rewrite the record with a later endedAtMs).
            nowMs += 5_000
            assertNull(b.currentTrip())
            assertEquals(endedAt, b.pendingFinishedTrips().single().endedAtMs)
            assertEquals(endedAt, backend().pendingFinishedTrips().single().endedAtMs)
        }

    @Test
    fun m3_failingWritesInTheTickLoopAreLoggedAndRetried() =
        runTest {
            val dir = File(tmp.root, "stub")
            val b = backend(dir = dir, clock = { t0 + testScheduler.currentTime })
            b.startTrip(config(), 16.8, 107.1, sim60)
            val received = mutableListOf<TripUpdateMsg>()
            b.addListener { received += it }
            runCurrent()

            // Disk "full": every write throws IOException from now on.
            assertTrue(dir.deleteRecursively())
            dir.writeText("not a directory")
            advanceTimeBy(20_000)
            runCurrent()
            assertTrue(warnings.isNotEmpty())
            assertTrue(warnings.all { it == "stub step failed (IOException)" })
            assertTrue("nothing failed is sent", received.none { it is AlarmMsg })

            // Disk usable again: the next tick commits the Step, the alarm is sent once.
            assertTrue(dir.delete())
            assertTrue(dir.mkdirs())
            advanceTimeBy(2_000)
            runCurrent()
            assertEquals(1, received.count { it is AlarmMsg })
            assertTrue(File(dir, StubStore.ACTIVE_FILE).exists())
        }

    @Test
    fun m3_failingWriteInAnApiCallCommitsNothing() =
        runTest {
            val dir = File(tmp.root, "stub")
            val b = backend(dir = dir)
            b.startTrip(config(), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            val before = b.currentTrip()!!
            assertTrue(dir.deleteRecursively())
            dir.writeText("not a directory")
            try {
                b.dismiss("t1")
                fail("expected IOException")
            } catch (e: IOException) {
                // TripHostApiImpl maps it to `internal`.
            }
            assertEquals(before, b.currentTrip())
        }
}
