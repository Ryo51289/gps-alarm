package app.napstop.core.alarm

import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** T28 K04: the optional `localeTag` of RING_START (`:ring` never reads the language file, D9). */
class RingStartLocaleTest {
    private val c = AlarmConstants()

    @Test
    fun k04_codecRoundTripsTheTag() {
        val en = AlarmData.start().copy(localeTag = "en")
        assertEquals(en, RingStartCodec.fromMap(RingStartCodec.toMap(en)))
        val device = AlarmData.start()
        assertNull(device.localeTag)
        assertEquals(device, RingStartCodec.fromMap(RingStartCodec.toMap(device)))
    }

    @Test
    fun k04_aBundleOfTheOlderCodecStillDecodes() {
        val old = RingStartCodec.toMap(AlarmData.start().copy(localeTag = "vi")) - "localeTag"
        val s = RingStartCodec.fromMap(old)
        assertEquals(AlarmData.start(), s)
        assertNull(s!!.localeTag)
        // Not a string: device language, the ring itself still decodes (a label never blocks an alarm).
        assertEquals(AlarmData.start(), RingStartCodec.fromMap(RingStartCodec.toMap(AlarmData.start()) + ("localeTag" to 3)))
    }

    @Test
    fun k04_theTagIsNotInToString() {
        assertFalse(AlarmData.start().copy(localeTag = "en").toString().contains("localeTag"))
    }

    @Test
    fun k04_coreSendsTheCurrentTagWithEveryStart() {
        var tag: String? = "en"
        val transport = FakeTransport()
        val core =
            AlarmControllerCore(
                transport, MemoryFacts(), FakeRingClock(), { AlarmData.ringConfig(it) }, { _, _ -> }, { }, c, { },
                { Locale.ENGLISH }, { tag },
            )
        core.ringNow(AlarmData.request())
        assertEquals("en", transport.started.last().localeTag)
        core.clearTrip(AlarmData.TRIP)
        tag = null
        core.ringNow(AlarmData.request(tripId = "t2"))
        assertNull(transport.started.last().localeTag)
        // A failing reader never blocks the ring.
        val failing =
            AlarmControllerCore(
                FakeTransport(), MemoryFacts(), FakeRingClock(), { AlarmData.ringConfig(it) }, { _, _ -> }, { }, c, { },
                { Locale.ENGLISH }, { throw IllegalStateException("io") },
            )
        failing.ringNow(AlarmData.request())
    }
}
