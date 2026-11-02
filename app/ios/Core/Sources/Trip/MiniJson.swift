// Strict RFC 8259 JSON parser/writer (T12 §7.1, T13 §6.1). Numbers keep their lexeme. Duplicate keys: the later value
// replaces the earlier one at the first position (T12 K2/C12). Nesting deeper than 64 is a syntax error (T12 C15).

enum JsonValue: Sendable, Equatable {
    case object([(String, JsonValue)])
    case array([JsonValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: JsonValue, rhs: JsonValue) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            for i in 0..<a.count where a[i].0 != b[i].0 || a[i].1 != b[i].1 { return false }
            return true
        case let (.array(a), .array(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    /// Value of `key` in an object (nil if absent or not an object).
    subscript(key: String) -> JsonValue? {
        guard case let .object(pairs) = self else { return nil }
        for (k, v) in pairs where k == key { return v }
        return nil
    }

    var isNull: Bool { if case .null = self { return true } else { return false } }

    /// Correctly rounded value of a number lexeme; nil if not a number or not finite.
    func asDouble() -> Double? {
        guard case let .number(lexeme) = self, let d = Double(lexeme), d.isFinite else { return nil }
        return d
    }

    /// Integer lexeme only (no '.', no exponent) that fits Int64.
    func asLongExact() -> Int64? {
        guard case let .number(lexeme) = self else { return nil }
        for c in lexeme.utf8 where c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
            return nil
        }
        return Int64(lexeme)
    }

    func asIntExact() -> Int? {
        guard let v = asLongExact(), v >= Int64(Int32.min), v <= Int64(Int32.max) else { return nil }
        return Int(v)
    }

    var stringValue: String? { if case let .string(s) = self { return s } else { return nil } }
    var boolValue: Bool? { if case let .bool(b) = self { return b } else { return nil } }
    var arrayValue: [JsonValue]? { if case let .array(a) = self { return a } else { return nil } }
    var objectValue: [(String, JsonValue)]? { if case let .object(o) = self { return o } else { return nil } }
}

struct JsonError: Error, Sendable, Equatable, CustomStringConvertible {
    let rule: String
    let offset: Int
    var description: String { "json: \(rule) at \(offset)" }
}

enum MiniJson {
    static let maxDepth = 64

    static func parse(_ text: String) throws(JsonError) -> JsonValue {
        var p = Parser(bytes: Array(text.utf8))
        p.skipWs()
        let v = try p.value(depth: 0)
        p.skipWs()
        guard p.pos == p.bytes.count else { throw JsonError(rule: "trailing content", offset: p.pos) }
        return v
    }

    static func write(_ v: JsonValue) -> String {
        var out = ""
        write(v, into: &out)
        return out
    }

    static func write(_ v: JsonValue, into out: inout String) {
        switch v {
        case let .object(pairs):
            out += "{"
            var first = true
            for (k, x) in pairs {
                if !first { out += "," }
                first = false
                writeString(k, into: &out)
                out += ":"
                write(x, into: &out)
            }
            out += "}"
        case let .array(xs):
            out += "["
            var first = true
            for x in xs {
                if !first { out += "," }
                first = false
                write(x, into: &out)
            }
            out += "]"
        case let .string(s): writeString(s, into: &out)
        case let .number(lexeme): out += lexeme
        case let .bool(b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0..<0x20:
                let hex = String(u.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }

    private struct Parser {
        let bytes: [UInt8]
        var pos = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipWs() {
            while pos < bytes.count {
                let c = bytes[pos]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { pos += 1 } else { break }
            }
        }

        /// Offset in UTF-16 code units, like the Kotlin parser (which indexes a JVM String).
        func fail(_ rule: String) -> JsonError {
            let end = pos < bytes.count ? pos : bytes.count
            return JsonError(rule: rule, offset: String(decoding: bytes[0..<end], as: UTF8.self).utf16.count)
        }

        mutating func value(depth: Int) throws(JsonError) -> JsonValue {
            guard pos < bytes.count else { throw fail("unexpected end") }
            let c = bytes[pos]
            switch c {
            case UInt8(ascii: "{"):
                guard depth < MiniJson.maxDepth else { throw fail("too deep") }
                return try object(depth: depth + 1)
            case UInt8(ascii: "["):
                guard depth < MiniJson.maxDepth else { throw fail("too deep") }
                return try array(depth: depth + 1)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
            default: throw fail("unexpected character")
            }
        }

        mutating func literal(_ word: String) throws(JsonError) {
            let w = Array(word.utf8)
            guard pos + w.count <= bytes.count, Array(bytes[pos..<(pos + w.count)]) == w else { throw fail("invalid literal") }
            pos += w.count
        }

        mutating func object(depth: Int) throws(JsonError) -> JsonValue {
            pos += 1
            var pairs: [(String, JsonValue)] = []
            skipWs()
            if pos < bytes.count && bytes[pos] == UInt8(ascii: "}") { pos += 1; return .object(pairs) }
            while true {
                skipWs()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: "\"") else { throw fail("expected key") }
                let key = try string()
                skipWs()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: ":") else { throw fail("expected colon") }
                pos += 1
                skipWs()
                let v = try value(depth: depth)
                if let i = pairs.firstIndex(where: { $0.0 == key }) { pairs[i].1 = v } else { pairs.append((key, v)) }
                skipWs()
                guard pos < bytes.count else { throw fail("unexpected end") }
                if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
                if bytes[pos] == UInt8(ascii: "}") { pos += 1; return .object(pairs) }
                throw fail("expected comma or brace")
            }
        }

        mutating func array(depth: Int) throws(JsonError) -> JsonValue {
            pos += 1
            var xs: [JsonValue] = []
            skipWs()
            if pos < bytes.count && bytes[pos] == UInt8(ascii: "]") { pos += 1; return .array(xs) }
            while true {
                skipWs()
                xs.append(try value(depth: depth))
                skipWs()
                guard pos < bytes.count else { throw fail("unexpected end") }
                if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
                if bytes[pos] == UInt8(ascii: "]") { pos += 1; return .array(xs) }
                throw fail("expected comma or bracket")
            }
        }

        func isDigit(_ i: Int) -> Bool { i < bytes.count && bytes[i] >= 0x30 && bytes[i] <= 0x39 }

        mutating func number() throws(JsonError) -> String {
            let start = pos
            if bytes[pos] == UInt8(ascii: "-") { pos += 1 }
            guard isDigit(pos) else { throw fail("invalid number") }
            if bytes[pos] == UInt8(ascii: "0") {
                pos += 1
                if isDigit(pos) { throw fail("leading zero") }
            } else {
                while isDigit(pos) { pos += 1 }
            }
            if pos < bytes.count && bytes[pos] == UInt8(ascii: ".") {
                pos += 1
                guard isDigit(pos) else { throw fail("invalid number") }
                while isDigit(pos) { pos += 1 }
            }
            if pos < bytes.count && (bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E")) {
                pos += 1
                if pos < bytes.count && (bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-")) { pos += 1 }
                guard isDigit(pos) else { throw fail("invalid number") }
                while isDigit(pos) { pos += 1 }
            }
            return String(decoding: bytes[start..<pos], as: UTF8.self)
        }

        /// Four hex digits at `at`; `pos` is not moved, so a failure reports the same position as the Kotlin parser.
        func hex4(_ at: Int) throws(JsonError) -> UInt32 {
            guard at + 4 <= bytes.count else { throw fail("invalid unicode escape") }
            var v: UInt32 = 0
            for i in at..<(at + 4) {
                let c = bytes[i]
                let d: UInt32
                switch c {
                case 0x30...0x39: d = UInt32(c - 0x30)
                case 0x41...0x46: d = UInt32(c - 0x41 + 10)
                case 0x61...0x66: d = UInt32(c - 0x61 + 10)
                default: throw fail("invalid unicode escape")
                }
                v = v * 16 + d
            }
            return v
        }

        /// Mirrors the Kotlin `string()` step by step (rule names and error positions, T12 C15).
        mutating func string() throws(JsonError) -> String {
            pos += 1
            var scalars = String.UnicodeScalarView()
            var runStart = pos
            func flush(_ s: inout String.UnicodeScalarView, _ from: Int, _ to: Int, _ bytes: [UInt8]) {
                if to > from { s.append(contentsOf: String(decoding: bytes[from..<to], as: UTF8.self).unicodeScalars) }
            }
            while true {
                guard pos < bytes.count else { throw fail("unterminated string") }
                let c = bytes[pos]
                if c == UInt8(ascii: "\"") {
                    flush(&scalars, runStart, pos, bytes)
                    pos += 1
                    return String(scalars)
                }
                if c == UInt8(ascii: "\\") {
                    flush(&scalars, runStart, pos, bytes)
                    pos += 1
                    guard pos < bytes.count else { throw fail("unterminated string") }
                    switch bytes[pos] {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        let hi = try hex4(pos + 1)
                        pos += 4
                        if hi >= 0xD800 && hi <= 0xDBFF {
                            guard pos + 2 < bytes.count, bytes[pos + 1] == UInt8(ascii: "\\"),
                                  bytes[pos + 2] == UInt8(ascii: "u") else { throw fail("lone surrogate") }
                            let lo = try hex4(pos + 3)
                            guard lo >= 0xDC00 && lo <= 0xDFFF else { throw fail("lone surrogate") }
                            let cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                            guard let u = Unicode.Scalar(cp) else { throw fail("lone surrogate") }
                            scalars.append(u)
                            pos += 6
                        } else if hi >= 0xDC00 && hi <= 0xDFFF {
                            throw fail("lone surrogate")
                        } else {
                            guard let u = Unicode.Scalar(hi) else { throw fail("lone surrogate") }
                            scalars.append(u)
                        }
                    default: throw fail("invalid escape")
                    }
                    pos += 1
                    runStart = pos
                    continue
                }
                if c < 0x20 { throw fail("control character in string") }
                pos += 1
            }
        }
    }
}
