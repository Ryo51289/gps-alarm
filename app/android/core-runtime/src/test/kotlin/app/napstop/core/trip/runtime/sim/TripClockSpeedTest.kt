package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.ClockAnchor
import app.napstop.core.trip.runtime.FallbackLedger
import app.napstop.core.trip.runtime.FixMapper
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.RuntimeCodec
import app.napstop.core.trip.runtime.StoreFormatException
import app.napstop.core.trip.runtime.StoredTrip
import app.napstop.core.trip.runtime.TripClock
import app.napstop.core.trip.runtime.support.EngineStates
import app.napstop.core.trip.runtime.support.FakeTime
import app.napstop.core.trip.runtime.support.TestData
import java.util.concurrent.Executors
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T18 §3: trip clock with a speed factor (SM01–SM03), codec of the new keys (SM04, SM05), FixMapper (SM09). */
class TripClockSpeedTest {
    @Test
    fun sm01_speedOneGivesTheT15ResultsToTheMillisecond() {
        // L01 numbers.
        val time = FakeTime(wallBase = 1_000_000, elapsedBase = 50_000)
        val clock = TripClock(TripClock.anchorNow(time), time)
        assertEquals(1.0, clock.speed)
        assertEquals(1_000_000, clock.now())
        time.elapsedBase += 30_000
        time.wallBase -= 10_000
        assertEquals(1_030_000, clock.now())
        val floored = TripClock(ClockAnchor(0, time.elapsedMs(), 7), time, floorMs = 5_000_000)
        assertEquals(5_000_000, floored.now())
        // L03 numbers.
        val t3 = FakeTime(wallBase = 2_000_000, elapsedBase = 5_000)
        val c3 = TripClock(ClockAnchor(1_000_000, 5_000, 7), t3)
        assertEquals(1_000_000, c3.now())
        assertEquals(65_000, c3.toElapsed(1_060_000))
        assertEquals(2_060_000, c3.toWall(1_060_000))
        assertEquals(2_000_000, c3.toWall(990_000))
        assertEquals(1_000_000 - 30_000, c3.toTrip(1_970_000))
        assertEquals(1_000_000, c3.toTrip(2_500_000))
        assertEquals(c3.now() + 5_000, c3.futureWallToTrip(t3.wallMs() + 5_000))
        assertEquals(c3.now(), c3.futureWallToTrip(t3.wallMs() - 5_000))
        assertEquals(60_000, c3.realDelayMs(1_060_000))
        assertEquals(0, c3.realDelayMs(900_000))
        // L02: anchorNow keeps speed 1.0, validity unchanged.
        assertEquals(1.0, TripClock.anchorNow(t3).speed)
        assertTrue(TripClock.anchorValid(ClockAnchor(1, 1_000, 7, speed = 60.0), t3))
    }

    @Test
    fun sm02_speed60ConvertsBothWays() {
        val time = FakeTime(wallBase = 1_000_000, elapsedBase = 50_000)
        val clock = TripClock(ClockAnchor(1_000_000, 50_000, 7, 60.0), time)
        time.elapsedBase += 1_000
        time.wallBase += 1_000
        val now = clock.now()
        assertEquals(1_060_000, now)
        assertEquals(time.elapsedMs() + 1_000, clock.toElapsed(now + 60_000))
        assertEquals(time.wallMs() + 1_000, clock.toWall(now + 60_000))
        assertEquals(now - 60_000, clock.toTrip(time.wallMs() - 1_000))
        assertEquals(1_000, clock.realDelayMs(now + 59_999)) // ceil
        assertEquals(now + 300_000, clock.futureWallToTrip(time.wallMs() + 5_000))
        assertEquals(1_000, clock.timeline.realDelayMs(now + 59_999))
    }

    @Test
    fun sm03_rebaseIsContinuousAndTheTimelineIsReadableFromAnotherThread() {
        val time = FakeTime(wallBase = 1_000_000, elapsedBase = 50_000)
        val clock = TripClock(ClockAnchor(1_000_000, 50_000, 7, 60.0), time)
        time.elapsedBase += 2_000
        val n = clock.now()
        assertEquals(1_120_000, n)
        clock.rebase(1.0)
        assertEquals(1.0, clock.speed)
        assertEquals(n, clock.now(), "continuous, never back")
        time.elapsedBase += 1_000
        assertEquals(n + 1_000, clock.now())
        val pool = Executors.newSingleThreadExecutor()
        try {
            assertEquals(n + 1_000, pool.submit<Long> { clock.timeline.tripNow() }.get())
        } finally {
            pool.shutdown()
        }
        assertThrows(IllegalArgumentException::class.java) { clock.rebase(0.0) }
        assertThrows(IllegalArgumentException::class.java) { clock.rebase(Double.NaN) }
    }

    @Test
    fun sm04_snapshotKeysOfARealTripAreUnchangedAndASimulatedOneRoundTrips() {
        val meta = TestData.meta()
        val anchor = ClockAnchor(1_700_000_000_000L, 1_000_000L, 7)
        val step = EngineStates.drive(meta, anchor.wallMs, 5_000.0, 3)
        val real = EngineStates.stored(meta, step, anchor)
        val realProps = RuntimeCodec.encodeTrip(real)
        assertTrue(realProps.stringPropertyNames().none { it == "anchor.speed" || it.startsWith("meta.sim.") }, "${realProps.stringPropertyNames()}")
        assertEquals(
            setOf("runtimeVersion", "anchor.wallMs", "anchor.elapsedMs", "anchor.bootCount", "savedAtWallMs", "engine"),
            realProps.stringPropertyNames().filterNot { it.startsWith("meta.") }.toSet(),
        )
        val back = RuntimeCodec.decodeTrip(realProps)
        assertEquals(real.meta, back.meta)
        assertEquals(real.anchor, back.anchor)

        val simMeta = meta.copy(simulation = SimSpec("train_hn_dh", 60.0))
        val sim = StoredTrip(StoredTrip.VERSION, simMeta, anchor.copy(speed = 60.0), step.state, anchor.wallMs)
        val p = RuntimeCodec.encodeTrip(sim)
        assertEquals("train_hn_dh", p.getProperty("meta.sim.traceId"))
        assertEquals("60.0", p.getProperty("anchor.speed"))
        val simBack = RuntimeCodec.decodeTrip(p)
        assertEquals(simMeta, simBack.meta)
        assertEquals(60.0, simBack.anchor.speed)
        for (bad in listOf("0", "NaN", "-1", "Infinity", "x")) {
            val q = RuntimeCodec.encodeTrip(sim).apply { setProperty("anchor.speed", bad) }
            val e = assertThrows(StoreFormatException::class.java) { RuntimeCodec.decodeTrip(q) }
            assertEquals("anchor.speed invalid", e.message)
        }
        val noSpeed = RuntimeCodec.encodeTrip(sim).apply { remove("meta.sim.speedFactor") }
        assertThrows(StoreFormatException::class.java) { RuntimeCodec.decodeTrip(noSpeed) }
        assertFalse(simMeta.toString().contains(meta.destinationName))
        assertTrue(simMeta.toString().contains("simulated=true"))
        assertTrue(meta.toString().contains("simulated=false"))
    }

    @Test
    fun sm05_ledgerActiveSimulatedRoundTripsAndIsOmittedWhenFalse() {
        val l = FallbackLedger.EMPTY.copy(activeTripId = "t1", activeSimulated = true)
        val p = RuntimeCodec.encodeLedger(l)
        assertEquals("true", p.getProperty("activeSimulated"))
        assertEquals(l, RuntimeCodec.decodeLedger(p))
        assertNull(RuntimeCodec.encodeLedger(l.copy(activeSimulated = false)).getProperty("activeSimulated"))
        assertFalse(RuntimeCodec.decodeLedger(RuntimeCodec.encodeLedger(FallbackLedger.EMPTY)).activeSimulated)
    }

    @Test
    fun sm09_fixMapperUsesTheSimulatedFixTime() {
        val nowNanos = 10_000_000_000L
        val raw = RawFix(16.0, 108.0, 8f, 10f, nowNanos - 3_000_000_000L)
        assertEquals(4_000, FixMapper.map(raw.copy(simFixAtMs = 4_000), 5_000, nowNanos)!!.fixAtMs)
        assertEquals(5_000, FixMapper.map(raw.copy(simFixAtMs = 6_000), 5_000, nowNanos)!!.fixAtMs, "never after now")
        assertEquals(2_000, FixMapper.map(raw, 5_000, nowNanos)!!.fixAtMs, "FLP: now - age (L04)")
        assertFalse(raw.copy(simFixAtMs = 1).toString().contains("16.0"))
    }
}
