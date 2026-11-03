package app.napstop.core.bridge.permission

import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.FlutterError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** K08: BackgroundCheckLogic (spec T21 §5). */
class BackgroundCheckLogicTest {
    private val record = BackgroundCheckRecord(1_000L, 31_000L, null, null, true)

    private fun assertOutOfRange(delayMs: Long) {
        try {
            BackgroundCheckLogic.validate(delayMs)
            fail("$delayMs accepted")
        } catch (e: FlutterError) {
            assertEquals(BridgeErrors.INVALID_CONFIG, e.code)
            assertEquals("delayMs: out of range", e.message)
        }
    }

    @Test
    fun k08Validate() {
        assertOutOfRange(4_999)
        BackgroundCheckLogic.validate(5_000)
        BackgroundCheckLogic.validate(30_000)
        BackgroundCheckLogic.validate(120_000)
        assertOutOfRange(120_001)
        assertOutOfRange(-1)
    }

    @Test
    fun k08UseExact() {
        assertTrue(BackgroundCheckLogic.useExact(30, null))
        assertTrue(BackgroundCheckLogic.useExact(31, true))
        assertFalse(BackgroundCheckLogic.useExact(31, false))
        assertFalse(BackgroundCheckLogic.useExact(34, null))
    }

    @Test
    fun k08EncodeDecodeRoundTrip() {
        assertEquals(record, BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(record)))
        val fired = record.copy(firedAtMs = 32_000L, screenOnAtFire = false)
        assertEquals(fired, BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(fired)))
        // SharedPreferences.getAll() has no entry for a null value.
        val withoutNulls = BackgroundCheckLogic.encode(record).filterValues { it != null }
        assertEquals(record, BackgroundCheckLogic.decode(withoutNulls))
    }

    @Test
    fun k08BrokenMapsDecodeToNull() {
        assertNull(BackgroundCheckLogic.decode(emptyMap<String, Any?>()))
        assertNull(BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(record) - "dueAtMs"))
        assertNull(BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(record) + ("scheduledAtMs" to "1000")))
        assertNull(BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(record) + ("firedAtMs" to 3)))
        assertNull(BackgroundCheckLogic.decode(BackgroundCheckLogic.encode(record) + ("screenOnAtFire" to "no")))
    }

    @Test
    fun k08OnFired() {
        assertEquals(
            record.copy(firedAtMs = 32_500L, screenOnAtFire = true),
            BackgroundCheckLogic.onFired(record, 1_000L, 32_500L, interactive = true),
        )
        assertEquals(
            record.copy(firedAtMs = 32_500L, screenOnAtFire = false),
            BackgroundCheckLogic.onFired(record, 1_000L, 32_500L, interactive = false),
        )
        // Another check.
        assertNull(BackgroundCheckLogic.onFired(record, 999L, 32_500L, interactive = false))
        // Already fired.
        assertNull(BackgroundCheckLogic.onFired(record.copy(firedAtMs = 31_100L), 1_000L, 32_500L, interactive = false))
        // No record (cancelled).
        assertNull(BackgroundCheckLogic.onFired(null, 1_000L, 32_500L, interactive = false))
    }

    @Test
    fun k08ToMsg() {
        val msg = record.copy(firedAtMs = 31_200L, screenOnAtFire = false).toMsg()
        assertEquals(1_000L, msg.scheduledAtMs)
        assertEquals(31_000L, msg.dueAtMs)
        assertEquals(31_200L, msg.firedAtMs)
        assertEquals(false, msg.screenOnAtFire)
        assertTrue(msg.exact)
    }
}
