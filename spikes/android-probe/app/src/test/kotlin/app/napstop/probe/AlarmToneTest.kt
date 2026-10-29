package app.napstop.probe

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

class AlarmToneTest {

    @Test
    fun `wav header and shape match S2 section 5_2`() {
        val bytes = AlarmTone.build()
        assertEquals(44 + 44_100 * 2, bytes.size)
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals("RIFF", String(bytes, 0, 4, Charsets.US_ASCII))
        assertEquals("WAVE", String(bytes, 8, 4, Charsets.US_ASCII))
        assertEquals(1, b.getShort(20).toInt()) // PCM
        assertEquals(1, b.getShort(22).toInt()) // mono
        assertEquals(44_100, b.getInt(24))
        assertEquals(16, b.getShort(34).toInt())
        assertEquals(44_100 * 2, b.getInt(40))

        val samples = (0 until 44_100).map { b.getShort(44 + it * 2).toInt() }
        val peak = samples.take(22_050).maxOf { abs(it) }
        assertTrue("peak $peak", peak in 26_000..26_215) // 0.8 FS = 26 214
        assertEquals(0, samples[0]) // fade-in
        assertTrue(samples.drop(22_050).all { it == 0 }) // 500 ms silence
    }
}
