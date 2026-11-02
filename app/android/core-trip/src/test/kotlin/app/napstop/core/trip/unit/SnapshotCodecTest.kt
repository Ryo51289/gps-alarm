package app.napstop.core.trip.unit

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSource
import app.napstop.core.trip.AlarmState
import app.napstop.core.trip.BatteryState
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.EndedState
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.SnapshotFormatException
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripOutcome
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.policy
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.util.Random

class SnapshotCodecTest {
    private fun bits(x: Double) = java.lang.Double.doubleToRawLongBits(x)

    /** Field-by-field equality with Doubles compared by raw bits (data class equals uses Double.equals, also bitwise). */
    private fun assertBitEqual(a: EngineState, b: EngineState) {
        assertEquals(a, b)
        assertEquals(a.cvGuard.map { bits(it) }, b.cvGuard.map { bits(it) })
        assertEquals(a.last3.map { bits(it) }, b.last3.map { bits(it) })
        assertEquals(a.recent.map { bits(it.d) to bits(it.lat) }, b.recent.map { bits(it.d) to bits(it.lat) })
        assertEquals(TripEngine.encodeSnapshot(a), TripEngine.encodeSnapshot(b))
    }

    private fun randomState(rng: Random, i: Int): EngineState {
        fun d() = (rng.nextDouble() - 0.3) * Math.pow(10.0, (rng.nextInt(12) - 4).toDouble())
        fun fix() = FixRec(S + rng.nextInt(1_000_000), d() / 1e6, 106.0 + d() / 1e7, rng.nextDouble() * 100 + 1, d(), if (rng.nextBoolean()) d() else null)
        val guardSizes = listOf(0, 1, 2, 5)
        val p = EngineParamsFactory.fromOverrides(if (i % 3 == 0) "{\"lostSpeedGuardUpdates\": 5, \"accRelMax\": 0.1234}" else null)
        return trackingState(p = p, d = rng.nextDouble() * 100000).copy(
            nowMs = S + rng.nextInt(100_000_000), last = fix(), stopAnchor = if (rng.nextBoolean()) fix() else null,
            recent = List(rng.nextInt(4)) { fix() }, rejects = List(rng.nextInt(4)) { fix() }, dSmooth = d(), dStartM = d(), minD = d(),
            last3 = List(rng.nextInt(4)) { d() }, ground = if (rng.nextBoolean()) d() else null, closing = d(), movingTimeS = d(),
            movingSamples = rng.nextInt(1000), movingDistM = d(), stopStartMs = if (rng.nextBoolean()) S + 5 else null, slow = rng.nextBoolean(),
            cvGuard = List(guardSizes[i % 4]) { d() }, policy = policy(SamplingTier.entries[rng.nextInt(3)]), gps = GpsStatus.entries[rng.nextInt(3)],
            phase = TripPhase.entries[rng.nextInt(6)],
            alarm = AlarmState(S + 1, AlarmReason.entries[rng.nextInt(13)], AlarmSource.FALLBACK, S + 2, AlarmReason.TIME, true, 1, S + 60_000, null),
            overshootAtMs = if (rng.nextBoolean()) S + 9 else null, overshootPastM = rng.nextInt(2000),
            fallback = FallbackState(S + 99, S + 3, FallbackStatus.entries[rng.nextInt(4)], null, rng.nextBoolean(), rng.nextBoolean()),
            battery = BatteryState(rng.nextInt(101), rng.nextBoolean(), S, 50, true, false, UserActionKind.BATTERY_ALARM_EARLIER, 12),
            ended = if (rng.nextBoolean()) EndedState(TripOutcome.MISSED, EndReason.ALARM_UNANSWERED, S + 7) else null,
            droppedFixes = rng.nextInt(50),
        )
    }

    @Test
    fun `U51 twenty deterministic random states round-trip bit-exactly, version 2 fails, unknown key ignored`() {
        val rng = Random(51)
        repeat(20) { i ->
            val s = randomState(rng, i)
            assertBitEqual(s, TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s)))
        }
        val json = TripEngine.encodeSnapshot(randomState(rng, 0))
        val e = assertThrows(SnapshotFormatException::class.java) { TripEngine.decodeSnapshot(json.replace("\"snapshotVersion\":1", "\"snapshotVersion\":2")) }
        assertEquals("snapshot: unsupported version", e.message)
        val withExtra = json.replace("\"snapshotVersion\":1,", "\"snapshotVersion\":1,\"futureKey\":{\"x\":[1,2]},")
        assertEquals(TripEngine.decodeSnapshot(json), TripEngine.decodeSnapshot(withExtra))
    }

    @Test
    fun `U69 awkward doubles round-trip bit-exactly`() {
        val xs = listOf(0.1, 1.0 / 3, 2.0 / 3 * 1e-300, 123456.789, 5e-324, 1.7976931348623157e308, -0.0, 1e23)
        val s = trackingState().copy(cvGuard = xs, last3 = xs.take(3), dSmooth = xs[2], ground = xs[4], closing = xs[5], movingDistM = xs[6])
        assertBitEqual(s, TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s)))
    }

    @Test
    fun `U51 missing key, bad version or type gives SnapshotFormatException without content`() {
        val json = TripEngine.encodeSnapshot(trackingState())
        val bad = listOf(
            json.replace("\"nowMs\":", "\"nowMsX\":"), json.replace("\"snapshotVersion\":1", "\"snapshotVersion\":0"),
            json.replace("\"snapshotVersion\":1", "\"snapshotVersion\":\"x\""), json.replace("\"slow\":false", "\"slow\":0"),
            json.replace("\"phase\":\"TRACKING\"", "\"phase\":\"FLYING\""), "{}", "[]", "not json",
            json.replace("\"nowMs\":$S", "\"nowMs\":1.5"),
        )
        for (b in bad) {
            val e = assertThrows(SnapshotFormatException::class.java, { TripEngine.decodeSnapshot(b) }, b.take(80))
            assertFalse(e.message!!.contains("TRACKING") || e.message!!.contains("106"), e.message)
        }
    }
}
