package app.napstop.probe.analysis

import app.napstop.probe.EventLog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FlatJsonTest {

    @Test
    fun `U01 encode then decode round-trips special characters and Vietnamese on one line`() {
        val map = linkedMapOf<String, Any?>(
            "ev" to "fix",
            "acc" to 12.5,
            "spd" to null,
            "ok" to true,
            "s" to "a\"b\\c\nđ",
        )
        val line = FlatJson.encode(map)
        assertFalse("must be a single line", line.contains('\n'))
        assertEquals(map, FlatJson.decode(line))
    }

    @Test
    fun `integers decode as Long, fractions as Double, control chars escaped`() {
        val line = FlatJson.encode(mapOf("n" to 3, "et" to 123456789012L, "x" to -0.25, "c" to "\u0001\t"))
        assertTrue(line.contains("\\u0001"))
        val back = FlatJson.decode(line)
        assertEquals(3L, back["n"])
        assertEquals(123456789012L, back["et"])
        assertEquals(-0.25, back["x"])
        assertEquals("\u0001\t", back["c"])
    }

    @Test
    fun `non-finite doubles become null`() {
        assertEquals(mapOf("v" to null), FlatJson.decode(FlatJson.encode(mapOf("v" to Double.NaN))))
    }

    @Test
    fun `decodes unicode escapes and whitespace`() {
        assertEquals(mapOf("k" to "đ", "b" to false), FlatJson.decode("""{ "k" : "đ" , "b" : false }"""))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `nested values are rejected`() {
        FlatJson.decode("""{"a":{"b":1}}""")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `truncated line is rejected`() {
        FlatJson.decode("""{"ev":"fix","acc":12""")
    }

    @Test
    fun `U02 parse skips a corrupt last line without throwing`() {
        val good = FlatJson.encode(
            linkedMapOf("ev" to "fix", "t" to "2026-11-02T21:30:05.123+07:00", "et" to 5L, "run" to "r", "pid" to 1, "seq" to 1),
        )
        val cut = """{"ev":"fix","t":"2026-11-02T21:30:15.123+07:00","et":1"""
        val parsed = EventLog.parse(sequenceOf(good, "", cut))
        assertEquals(1, parsed.events.size)
        assertEquals(1, parsed.corruptLines)
        assertEquals("fix", parsed.events[0].ev)
        assertEquals(1L, parsed.events[0].seq)
    }

    @Test
    fun `parse counts lines without ev or valid t as corrupt`() {
        val parsed = ProbeEventParser.parse(sequenceOf("""{"t":"2026-11-02T21:30:05.123+07:00"}""", """{"ev":"x","t":"bad"}"""))
        assertEquals(0, parsed.events.size)
        assertEquals(2, parsed.corruptLines)
    }
}
