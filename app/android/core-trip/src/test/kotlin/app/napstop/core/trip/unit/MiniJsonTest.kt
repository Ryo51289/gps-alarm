package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.JArray
import app.napstop.core.trip.JNumber
import app.napstop.core.trip.JObject
import app.napstop.core.trip.JString
import app.napstop.core.trip.JsonParseException
import app.napstop.core.trip.MiniJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** MiniJson (T12 §7.1) + C15 depth limit. Helper for U02/U51/U67. */
class MiniJsonTest {
    private fun nested(depth: Int) = "[".repeat(depth) + "]".repeat(depth)

    @Test
    fun `U67 C15 nesting deeper than 64 is a syntax error and params fall back to defaults`() {
        MiniJson.parse(nested(64))
        assertThrows(JsonParseException::class.java) { MiniJson.parse(nested(65)) }
        val deepObj = "{\"a\":".repeat(64) + "1" + "}".repeat(64)
        MiniJson.parse(deepObj)
        assertThrows(JsonParseException::class.java) { MiniJson.parse("{\"x\":" + nested(64) + "}") }
        val r = EngineParamsFactory.parseOverrides("{\"gpsLostMinS\": 90, \"x\": " + nested(64) + "}")
        assertTrue(r.malformed)
        assertEquals(60, r.params.gpsLostMinS)
    }

    @Test
    fun `U67 parser rejects invalid JSON with a message without content`() {
        val bad = listOf(
            "\uFEFF{}", "{\"a\":1,}", "[1,]", "{/*c*/}", "NaN", "Infinity", "+1", "01", "1.", ".5", "0x10", "-",
            "\"\\ud800\"", "\"\\udc00\"", "\"\uD800\"", "\"\uDC00x\"", "\"\\uD800\\u0041\"", "\"\uD800\\u0041\"", "\"a\u0001\"", "1 2", "", "{\"a\" 1}", "tru", "\"\\x\"",
        )
        for (s in bad) {
            val e = assertThrows(JsonParseException::class.java, { MiniJson.parse(s) }, "should reject: $s")
            assertTrue(e.message!!.startsWith("json: ")) { e.message }
            assertTrue(e.message!!.matches(Regex("json: [a-z ]+ at \\d+"))) { e.message }
        }
    }

    @Test
    fun `U67 lexemes, escapes, duplicate keys keep first position and last value`() {
        val o = MiniJson.parse("{\"b\":1,\"a\":-0.0,\"b\":3e2,\"s\":\"\\u00e9\\ud83d\\ude00\\n\"}") as JObject
        assertEquals(listOf("b", "a", "s"), o.fields.keys.toList())
        assertEquals("3e2", (o["b"] as JNumber).lexeme)
        assertEquals(300.0, (o["b"] as JNumber).asDouble())
        assertEquals(null, (o["b"] as JNumber).asLongExact())
        assertEquals("\u00e9\ud83d\ude00\n", (o["s"] as JString).value)
        assertEquals("{\"b\":3e2,\"a\":-0.0,\"s\":\"\u00e9\ud83d\ude00\\u000a\"}", MiniJson.write(o))
        assertEquals(-12L, (MiniJson.parse("-12") as JNumber).asLongExact())
        assertFalse((MiniJson.parse("[]") as JArray).items.isNotEmpty())
    }

    @Test
    fun `U51 C15 lone surrogates are refused by the writer too and by start for tripId`() {
        val e = assertThrows(IllegalArgumentException::class.java) { MiniJson.write(JString("a\uD800")) }
        assertEquals("json: lone surrogate", e.message)
        assertThrows(IllegalArgumentException::class.java) { MiniJson.write(JString("\uDC00")) }
        assertEquals("\"😀\"", MiniJson.write(JString("😀")))
        val c = app.napstop.core.trip.support.cfg().copy(tripId = "trip\uD800")
        val se = assertThrows(IllegalArgumentException::class.java) {
            app.napstop.core.trip.TripEngine.start(c, app.napstop.core.trip.EngineParams(), app.napstop.core.trip.support.S)
        }
        assertEquals("tripId: invalid", se.message)
    }
}
