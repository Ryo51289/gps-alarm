package app.napstop.probe.analysis

/**
 * Minimal JSON codec for flat objects: values are String, Number, Boolean or null only
 * (no nested arrays/objects). Used for the JSON Lines event log (S1 §5.7).
 *
 * Decoding returns integral numbers as [Long] and fractional numbers as [Double].
 */
object FlatJson {

    fun encode(map: Map<String, Any?>): String {
        val sb = StringBuilder(64 + map.size * 16)
        sb.append('{')
        var first = true
        for ((key, value) in map) {
            if (!first) sb.append(',')
            first = false
            appendString(sb, key)
            sb.append(':')
            appendValue(sb, value)
        }
        sb.append('}')
        return sb.toString()
    }

    /** Parses one flat JSON object. Throws [IllegalArgumentException] on malformed input. */
    fun decode(line: String): Map<String, Any?> = Parser(line).parseObject()

    private fun appendValue(sb: StringBuilder, value: Any?) {
        when (value) {
            null -> sb.append("null")
            is Boolean -> sb.append(value)
            is Int, is Long, is Short, is Byte -> sb.append(value)
            is Double -> if (value.isFinite()) sb.append(value) else sb.append("null")
            is Float -> if (value.isFinite()) sb.append(value.toDouble()) else sb.append("null")
            is Number -> sb.append(value.toString())
            else -> appendString(sb, value.toString())
        }
    }

    private fun appendString(sb: StringBuilder, s: String) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                else -> if (c < ' ' || c == ' ' || c == ' ') {
                    sb.append("\\u").append(c.code.toString(16).padStart(4, '0'))
                } else {
                    sb.append(c)
                }
            }
        }
        sb.append('"')
    }

    private class Parser(private val s: String) {
        private var i = 0

        fun parseObject(): Map<String, Any?> {
            skipWs()
            expect('{')
            val out = LinkedHashMap<String, Any?>()
            skipWs()
            if (peek() == '}') {
                i++
            } else {
                while (true) {
                    skipWs()
                    val key = parseString()
                    skipWs()
                    expect(':')
                    skipWs()
                    out[key] = parseValue()
                    skipWs()
                    when (next()) {
                        ',' -> continue
                        '}' -> break
                        else -> fail("expected , or }")
                    }
                }
            }
            skipWs()
            if (i != s.length) fail("trailing characters")
            return out
        }

        private fun parseValue(): Any? = when (val c = peek()) {
            '"' -> parseString()
            't' -> literal("true", true)
            'f' -> literal("false", false)
            'n' -> literal("null", null)
            '{', '[' -> fail("nested values are not supported")
            else -> if (c == '-' || c in '0'..'9') parseNumber() else fail("unexpected '$c'")
        }

        private fun literal(word: String, value: Any?): Any? {
            if (!s.startsWith(word, i)) fail("expected $word")
            i += word.length
            return value
        }

        private fun parseNumber(): Any {
            val start = i
            if (peek() == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] in ".eE+-")) i++
            val text = s.substring(start, i)
            val isFraction = text.any { it == '.' || it == 'e' || it == 'E' }
            return if (isFraction) {
                text.toDoubleOrNull() ?: fail("bad number $text")
            } else {
                text.toLongOrNull() ?: text.toDoubleOrNull() ?: fail("bad number $text")
            }
        }

        private fun parseString(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) fail("unterminated string")
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        if (i >= s.length) fail("bad escape")
                        when (val e = s[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'u' -> {
                                if (i + 4 > s.length) fail("bad unicode escape")
                                val code = s.substring(i, i + 4).toIntOrNull(16) ?: fail("bad unicode escape")
                                sb.append(code.toChar())
                                i += 4
                            }
                            else -> fail("bad escape \\$e")
                        }
                    }
                    else -> sb.append(c)
                }
            }
        }

        private fun skipWs() {
            while (i < s.length && s[i].isWhitespace()) i++
        }

        private fun peek(): Char = if (i < s.length) s[i] else fail("unexpected end")

        private fun next(): Char = if (i < s.length) s[i++] else fail("unexpected end")

        private fun expect(c: Char) {
            if (next() != c) fail("expected '$c'")
        }

        private fun fail(msg: String): Nothing = throw IllegalArgumentException("$msg at $i")
    }
}
