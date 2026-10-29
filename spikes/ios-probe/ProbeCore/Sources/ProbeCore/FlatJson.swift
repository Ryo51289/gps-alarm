import Foundation

/// One value of a flat JSON object (S3 §6.6): no nested arrays or objects.
public enum JSONScalar: Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null

    /// Int value (Int64 → Int).
    public static func num(_ value: Int) -> JSONScalar { .int(Int64(value)) }

    /// Double value; nil or non-finite → null.
    public static func num(_ value: Double?) -> JSONScalar {
        guard let value, value.isFinite else { return .null }
        return .double(value)
    }

    /// String value; nil → null.
    public static func str(_ value: String?) -> JSONScalar {
        guard let value else { return .null }
        return .string(value)
    }

    /// Bool value; nil → null.
    public static func flag(_ value: Bool?) -> JSONScalar {
        guard let value else { return .null }
        return .bool(value)
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Integral numbers as Int64; a double with no fractional part is accepted too.
    public var intValue: Int64? {
        switch self {
        case .int(let v): return v
        case .double(let d):
            guard d.isFinite, d.rounded() == d, abs(d) < 9.0e18 else { return nil }
            return Int64(d)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let d): return d
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

extension JSONScalar: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONScalar: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONScalar: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONScalar: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

public enum FlatJsonError: Error, Equatable {
    case forbiddenKey(String)
    case malformed(String)
    case notFlat(String)
}

/// Minimal codec for the JSON Lines event log: one flat object per line.
public enum FlatJson {
    /// Common fields, written first in this order (S3 §6.6).
    public static let commonKeys: [String] = ["ev", "t", "up", "run", "pid", "seq", "launch"]

    /// Coordinate-like keys: the log must never hold a location (privacy rule D4, test U11).
    public static let forbiddenKeys: Set<String> = [
        "lat", "lng", "lon", "latitude", "longitude", "alt", "altitude", "coordinate",
    ]

    /// Keys in a fixed order: ev, t, up, run, pid, seq, launch, then the others alphabetically.
    /// Throws `forbiddenKey` for a coordinate-like key (case-insensitive).
    public static func encode(_ fields: [String: JSONScalar]) throws -> String {
        for key in fields.keys where forbiddenKeys.contains(key.lowercased()) {
            throw FlatJsonError.forbiddenKey(key)
        }
        var keys: [String] = commonKeys.filter { fields[$0] != nil }
        keys += fields.keys.filter { !commonKeys.contains($0) }.sorted()
        var out = "{"
        var first = true
        for key in keys {
            guard let value = fields[key] else { continue }
            if !first { out += "," }
            first = false
            appendString(&out, key)
            out += ":"
            appendValue(&out, value)
        }
        out += "}"
        return out
    }

    /// Parses one flat JSON object. Nested object/array → `notFlat`; anything else invalid → `malformed`.
    public static func decode(_ line: String) throws -> [String: JSONScalar] {
        var parser = Parser(Array(line.unicodeScalars))
        return try parser.parseObject()
    }

    private static func appendValue(_ out: inout String, _ value: JSONScalar) {
        switch value {
        case .string(let s): appendString(&out, s)
        case .int(let v): out += String(v)
        case .double(let d): out += d.isFinite ? "\(d)" : "null"
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    private static func appendString(_ out: inout String, _ s: String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                let v = scalar.value
                if v < 0x20 || v == 0x2028 || v == 0x2029 {
                    out += "\\u" + hexDigits4(v)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    private static func hexDigits4(_ v: UInt32) -> String {
        let digits = Array("0123456789abcdef")
        var s = ""
        for shift in stride(from: 12, through: 0, by: -4) {
            s.append(digits[Int((v >> UInt32(shift)) & 0xF)])
        }
        return s
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0

        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func parseObject() throws -> [String: JSONScalar] {
            skipWs()
            try expect("{")
            var out: [String: JSONScalar] = [:]
            skipWs()
            if try peek() == "}" {
                i += 1
            } else {
                while true {
                    skipWs()
                    let key = try parseString()
                    skipWs()
                    try expect(":")
                    skipWs()
                    out[key] = try parseValue()
                    skipWs()
                    let c = try next()
                    if c == "," { continue }
                    if c == "}" { break }
                    throw FlatJsonError.malformed("expected , or } at \(i)")
                }
            }
            skipWs()
            if i != s.count { throw FlatJsonError.malformed("trailing characters at \(i)") }
            return out
        }

        mutating func parseValue() throws -> JSONScalar {
            let c = try peek()
            switch c {
            case "\"": return .string(try parseString())
            case "t": try literal("true"); return .bool(true)
            case "f": try literal("false"); return .bool(false)
            case "n": try literal("null"); return .null
            case "{", "[": throw FlatJsonError.notFlat("nested value at \(i)")
            default:
                if c == "-" || (c >= "0" && c <= "9") { return try parseNumber() }
                throw FlatJsonError.malformed("unexpected character at \(i)")
            }
        }

        mutating func literal(_ word: String) throws {
            for w in word.unicodeScalars {
                guard i < s.count, s[i] == w else { throw FlatJsonError.malformed("expected \(word) at \(i)") }
                i += 1
            }
        }

        mutating func parseNumber() throws -> JSONScalar {
            let start = i
            if i < s.count, s[i] == "-" { i += 1 }
            while i < s.count {
                let c = s[i]
                if (c >= "0" && c <= "9") || c == "." || c == "e" || c == "E" || c == "+" || c == "-" {
                    i += 1
                } else {
                    break
                }
            }
            var text = ""
            text.unicodeScalars.append(contentsOf: s[start..<i])
            let isFraction = text.contains(".") || text.contains("e") || text.contains("E")
            if !isFraction, let v = Int64(text) { return .int(v) }
            if let d = Double(text), d.isFinite { return .double(d) }
            throw FlatJsonError.malformed("bad number \(text)")
        }

        mutating func parseString() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            while true {
                guard i < s.count else { throw FlatJsonError.malformed("unterminated string") }
                let c = s[i]
                i += 1
                if c == "\"" { return String(out) }
                if c != "\\" {
                    out.append(c)
                    continue
                }
                guard i < s.count else { throw FlatJsonError.malformed("bad escape") }
                let e = s[i]
                i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    var code = try hex4()
                    if code >= 0xD800, code <= 0xDBFF {
                        // Surrogate pair: 😀.
                        guard i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" else {
                            throw FlatJsonError.malformed("lone surrogate")
                        }
                        i += 2
                        let low = try hex4()
                        guard low >= 0xDC00, low <= 0xDFFF else { throw FlatJsonError.malformed("bad surrogate") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw FlatJsonError.malformed("bad code point") }
                    out.append(scalar)
                default:
                    throw FlatJsonError.malformed("bad escape at \(i)")
                }
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count else { throw FlatJsonError.malformed("bad unicode escape") }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = s[i].value
                let d: UInt32
                switch c {
                case 0x30...0x39: d = c - 0x30
                case 0x41...0x46: d = c - 0x41 + 10
                case 0x61...0x66: d = c - 0x61 + 10
                default: throw FlatJsonError.malformed("bad unicode escape")
                }
                v = v * 16 + d
                i += 1
            }
            return v
        }

        mutating func skipWs() {
            while i < s.count, s[i] == " " || s[i] == "\t" || s[i] == "\n" || s[i] == "\r" { i += 1 }
        }

        func peek() throws -> Unicode.Scalar {
            guard i < s.count else { throw FlatJsonError.malformed("unexpected end") }
            return s[i]
        }

        mutating func next() throws -> Unicode.Scalar {
            let c = try peek()
            i += 1
            return c
        }

        mutating func expect(_ c: Unicode.Scalar) throws {
            guard try next() == c else { throw FlatJsonError.malformed("expected \(c) at \(i)") }
        }
    }
}
