package app.napstop.core.trip

/** JSON tree that keeps number lexemes and object key order (T12 §7.1). */
internal sealed interface JsonValue

/** Insertion-ordered object; a duplicate key overwrites the value but keeps the first position. */
internal class JObject(val fields: LinkedHashMap<String, JsonValue> = LinkedHashMap()) : JsonValue {
    operator fun get(key: String): JsonValue? = fields[key]

    fun has(key: String): Boolean = fields.containsKey(key)

    override fun equals(other: Any?): Boolean = other is JObject && other.fields == fields

    override fun hashCode(): Int = fields.hashCode()

    override fun toString(): String = "JObject(<redacted>)"
}

internal class JArray(val items: List<JsonValue>) : JsonValue {
    override fun equals(other: Any?): Boolean = other is JArray && other.items == items

    override fun hashCode(): Int = items.hashCode()

    override fun toString(): String = "JArray(<redacted>)"
}

/** Number with its original lexeme (validated RFC 8259 grammar). */
internal class JNumber(val lexeme: String) : JsonValue {
    fun asDouble(): Double = lexeme.toDouble()

    /** Only integer lexemes (no '.', no exponent) that fit a Long; otherwise null. */
    fun asLongExact(): Long? {
        if (lexeme.indexOf('.') >= 0 || lexeme.indexOf('e') >= 0 || lexeme.indexOf('E') >= 0) return null
        return lexeme.toLongOrNull()
    }

    override fun equals(other: Any?): Boolean = other is JNumber && other.lexeme == lexeme

    override fun hashCode(): Int = lexeme.hashCode()

    override fun toString(): String = "JNumber(<redacted>)"
}

internal class JString(val value: String) : JsonValue {
    override fun equals(other: Any?): Boolean = other is JString && other.value == value

    override fun hashCode(): Int = value.hashCode()

    override fun toString(): String = "JString(<redacted>)"
}

internal class JBool(val value: Boolean) : JsonValue {
    override fun equals(other: Any?): Boolean = other is JBool && other.value == value

    override fun hashCode(): Int = value.hashCode()

    override fun toString(): String = "JBool($value)"
}

internal object JNull : JsonValue {
    override fun toString(): String = "JNull"
}

/** Message format "json: <rule> at <offset>"; never quotes input content. */
internal class JsonParseException(message: String) : RuntimeException(message)

internal object MiniJson {
    /** C15: nesting deeper than this (arrays + objects) is a syntax error, identical to T13. */
    const val MAX_DEPTH = 64

    fun parse(text: String): JsonValue {
        val p = Parser(text)
        p.skipWs()
        val v = p.value(0)
        p.skipWs()
        if (p.pos != text.length) p.fail("trailing content")
        return v
    }

    fun write(v: JsonValue): String {
        val sb = StringBuilder()
        write(v, sb)
        return sb.toString()
    }

    fun write(v: JsonValue, sb: StringBuilder) {
        when (v) {
            is JObject -> {
                sb.append('{')
                var first = true
                for ((k, x) in v.fields) {
                    if (!first) sb.append(',')
                    first = false
                    writeString(k, sb)
                    sb.append(':')
                    write(x, sb)
                }
                sb.append('}')
            }
            is JArray -> {
                sb.append('[')
                for (i in v.items.indices) {
                    if (i > 0) sb.append(',')
                    write(v.items[i], sb)
                }
                sb.append(']')
            }
            is JNumber -> sb.append(v.lexeme)
            is JString -> writeString(v.value, sb)
            is JBool -> sb.append(if (v.value) "true" else "false")
            JNull -> sb.append("null")
        }
    }

    fun writeString(s: String, sb: StringBuilder) {
        // C15: the parser rejects unpaired surrogates, so the writer refuses them too (encode/decode symmetric).
        require(isWellFormedUtf16(s)) { "json: lone surrogate" }
        sb.append('"')
        for (c in s) {
            when {
                c == '"' -> sb.append("\\\"")
                c == '\\' -> sb.append("\\\\")
                c.code < 0x20 -> {
                    sb.append("\\u00")
                    sb.append(HEX[c.code shr 4])
                    sb.append(HEX[c.code and 0xF])
                }
                else -> sb.append(c)
            }
        }
        sb.append('"')
    }

    private const val HEX = "0123456789abcdef"

    private class Parser(val s: String) {
        var pos = 0

        fun fail(rule: String): Nothing = throw JsonParseException("json: $rule at $pos")

        fun skipWs() {
            while (pos < s.length) {
                val c = s[pos]
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') pos++ else break
            }
        }

        fun value(depth: Int): JsonValue {
            if (pos >= s.length) fail("unexpected end")
            return when (val c = s[pos]) {
                '{' -> obj(depth + 1)
                '[' -> arr(depth + 1)
                '"' -> JString(string())
                't' -> literal("true", JBool(true))
                'f' -> literal("false", JBool(false))
                'n' -> literal("null", JNull)
                else -> if (c == '-' || (c in '0'..'9')) number() else fail("unexpected character")
            }
        }

        fun literal(word: String, v: JsonValue): JsonValue {
            if (!s.startsWith(word, pos)) fail("invalid literal")
            pos += word.length
            return v
        }

        fun obj(depth: Int): JsonValue {
            if (depth > MAX_DEPTH) fail("too deep")
            pos++ // {
            val fields = LinkedHashMap<String, JsonValue>()
            skipWs()
            if (pos < s.length && s[pos] == '}') {
                pos++
                return JObject(fields)
            }
            while (true) {
                skipWs()
                if (pos >= s.length || s[pos] != '"') fail("expected key")
                val key = string()
                skipWs()
                if (pos >= s.length || s[pos] != ':') fail("expected colon")
                pos++
                skipWs()
                fields[key] = value(depth)
                skipWs()
                if (pos >= s.length) fail("unexpected end")
                when (s[pos]) {
                    ',' -> pos++
                    '}' -> {
                        pos++
                        return JObject(fields)
                    }
                    else -> fail("expected comma or brace")
                }
            }
        }

        fun arr(depth: Int): JsonValue {
            if (depth > MAX_DEPTH) fail("too deep")
            pos++ // [
            val items = ArrayList<JsonValue>()
            skipWs()
            if (pos < s.length && s[pos] == ']') {
                pos++
                return JArray(items)
            }
            while (true) {
                skipWs()
                items.add(value(depth))
                skipWs()
                if (pos >= s.length) fail("unexpected end")
                when (s[pos]) {
                    ',' -> pos++
                    ']' -> {
                        pos++
                        return JArray(items)
                    }
                    else -> fail("expected comma or bracket")
                }
            }
        }

        fun string(): String {
            pos++ // opening quote
            val sb = StringBuilder()
            while (true) {
                if (pos >= s.length) fail("unterminated string")
                val c = s[pos]
                when {
                    c == '"' -> {
                        pos++
                        return sb.toString()
                    }
                    c == '\\' -> {
                        pos++
                        if (pos >= s.length) fail("unterminated string")
                        when (s[pos]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                val hi = hex4(pos + 1)
                                pos += 4
                                if (hi in 0xD800..0xDBFF) {
                                    if (pos + 2 < s.length && s[pos + 1] == '\\' && s[pos + 2] == 'u') {
                                        val lo = hex4(pos + 3)
                                        if (lo !in 0xDC00..0xDFFF) fail("lone surrogate")
                                        sb.append(hi.toChar())
                                        sb.append(lo.toChar())
                                        pos += 6
                                    } else {
                                        fail("lone surrogate")
                                    }
                                } else if (hi in 0xDC00..0xDFFF) {
                                    fail("lone surrogate")
                                } else {
                                    sb.append(hi.toChar())
                                }
                            }
                            else -> fail("invalid escape")
                        }
                        pos++
                    }
                    c.code < 0x20 -> fail("control character in string")
                    c.isHighSurrogate() -> {
                        if (pos + 1 >= s.length || !s[pos + 1].isLowSurrogate()) fail("lone surrogate")
                        sb.append(c)
                        sb.append(s[pos + 1])
                        pos += 2
                    }
                    c.isLowSurrogate() -> fail("lone surrogate")
                    else -> {
                        sb.append(c)
                        pos++
                    }
                }
            }
        }

        fun hex4(at: Int): Int {
            if (at + 4 > s.length) fail("invalid unicode escape")
            var v = 0
            for (i in at until at + 4) {
                val c = s[i]
                val d = when (c) {
                    in '0'..'9' -> c - '0'
                    in 'a'..'f' -> c - 'a' + 10
                    in 'A'..'F' -> c - 'A' + 10
                    else -> fail("invalid unicode escape")
                }
                v = v * 16 + d
            }
            return v
        }

        fun number(): JsonValue {
            val start = pos
            if (s[pos] == '-') pos++
            if (pos >= s.length) fail("invalid number")
            if (s[pos] == '0') {
                pos++
                if (pos < s.length && s[pos] in '0'..'9') fail("leading zero")
            } else if (s[pos] in '1'..'9') {
                while (pos < s.length && s[pos] in '0'..'9') pos++
            } else {
                fail("invalid number")
            }
            if (pos < s.length && s[pos] == '.') {
                pos++
                if (pos >= s.length || s[pos] !in '0'..'9') fail("invalid number")
                while (pos < s.length && s[pos] in '0'..'9') pos++
            }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++
                if (pos >= s.length || s[pos] !in '0'..'9') fail("invalid number")
                while (pos < s.length && s[pos] in '0'..'9') pos++
            }
            return JNumber(s.substring(start, pos))
        }
    }
}

/** True when every surrogate is part of a high+low pair. */
internal fun isWellFormedUtf16(s: String): Boolean {
    var i = 0
    while (i < s.length) {
        val c = s[i]
        if (c.isHighSurrogate()) {
            if (i + 1 >= s.length || !s[i + 1].isLowSurrogate()) return false
            i += 2
            continue
        }
        if (c.isLowSurrogate()) return false
        i++
    }
    return true
}

// Small builders used by SnapshotCodec and the test harness.
internal fun jObj(vararg pairs: Pair<String, JsonValue>): JObject {
    val m = LinkedHashMap<String, JsonValue>()
    for ((k, v) in pairs) m[k] = v
    return JObject(m)
}

internal fun jNum(x: Long): JsonValue = JNumber(x.toString())

internal fun jNum(x: Int): JsonValue = JNumber(x.toString())

/** Double as `Double.toString()` (round-trips on the JVM, T12 §7.3). Must be finite. */
internal fun jDbl(x: Double): JsonValue = JNumber(x.toString())

internal fun jStr(x: String): JsonValue = JString(x)

internal fun jBool(x: Boolean): JsonValue = JBool(x)
