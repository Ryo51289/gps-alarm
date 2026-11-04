package app.napstop.core.bridge

import app.napstop.core.bridge.BridgeTestData.config
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** T15 L12 (test report T14 F1, review T14 R2-3): a throwing listener never blocks another or fails a call. */
@OptIn(ExperimentalCoroutinesApi::class)
class ListenerHubTest {
    private val warnings = mutableListOf<String>()

    private fun step(): List<TripUpdateMsg> {
        val state = MsgMapperTest.sampleState()
        return listOf(
            TripStateUpdateMsg(state),
            AlarmMsg("t1", 1, AlarmReasonMsg.DISTANCE, true, true, 900, 60, 50),
            TripEndedMsg(2, FinishedTripMsg("t1", TripOutcomeMsg.ON_TIME, EndReasonMsg.DISMISSED, 2, 0, 1, AlarmReasonMsg.DISTANCE, 2, 0, 10, VehicleKindMsg.TRAIN)),
        )
    }

    @Test
    fun l12_eachListenerGetsEveryUpdateAndThrowsAreIsolated() {
        val hub = ListenerHub { warnings += it }
        val one = mutableListOf<TripUpdateMsg>()
        val three = mutableListOf<TripUpdateMsg>()
        hub.add({ one += it })
        hub.add({ throw IllegalStateException("16.8163,107.1003 Ga Đông Hà") })
        hub.add({ three += it })
        val updates = step()
        hub.publish(updates)
        assertEquals(updates, one)
        assertEquals(updates, three)
        assertEquals(List(3) { "listener failed (IllegalStateException)" }, warnings)
    }

    @Test
    fun handlesAreIdempotentAndPerListener() {
        val hub = ListenerHub { warnings += it }
        var removed = 0
        val got = mutableListOf<TripUpdateMsg>()
        val f: (TripUpdateMsg) -> Unit = { got += it }
        val h1 = hub.add(f) { removed++ }
        hub.add(f)
        h1.remove()
        h1.remove()
        assertEquals(1, removed)
        assertEquals(1, hub.size)
        hub.publish(step())
        assertEquals(3, got.size)
    }

    @Test
    fun l12_dismissThroughTheRealBackendSucceedsWithAThrowingListener() =
        runTest {
            val fakes = RuntimeFakes(this)
            val hub = ListenerHub { warnings += it }
            val backend = RealTripBackend(fakes.runtime, hub)
            val one = mutableListOf<TripUpdateMsg>()
            val three = mutableListOf<TripUpdateMsg>()
            backend.addListener { one += it }
            backend.addListener { throw IllegalStateException() }
            backend.addListener { three += it }
            backend.startTrip(config("t1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.0, 108.0, null)
            assertTrue("TripStateUpdateMsg before startTrip returned", one.first() is TripStateUpdateMsg)
            var m = 1_300.0
            while (one.none { it is AlarmMsg } && m > 0) {
                fakes.fix(m)
                runCurrent()
                advanceTimeBy(5_000)
                m -= 75.0
            }
            assertTrue(one.any { it is AlarmMsg && it.ringNow })
            var ok = false
            launch {
                backend.dismiss("t1")
                ok = true
            }
            runCurrent()
            assertTrue("dismiss returned normally", ok)
            assertTrue(one.last() is TripEndedMsg)
            assertEquals(one, three)
            assertTrue(warnings.isNotEmpty() && warnings.all { it == "listener failed (IllegalStateException)" })
            assertEquals(TripOutcomeMsg.ON_TIME, backend.pendingFinishedTrips().single().outcome)
            // Every Step starts with its state.
            var expectState = true
            for (u in one) {
                if (expectState) assertTrue(u is TripStateUpdateMsg)
                expectState = false
                if (u is TripStateUpdateMsg) expectState = false
            }
        }
}
