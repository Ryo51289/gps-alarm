import Foundation
import XCTest
@testable import ProbeCore

final class FlatJsonTests: XCTestCase {
    // U1
    func testRoundTripKeepsValuesAndKeyOrder() throws {
        let fields: [String: JSONScalar] = [
            "zeta": "trích \"dẫn\" \\ gạch\nxuống dòng\ttab — Tiếng Việt có dấu: Đà Nẵng, Huế 😀",
            "seq": 42,
            "ev": "fix",
            "acc": 4.75,
            "t": "2026-10-29T21:35:12.345+07:00",
            "launch": "ab12cd34",
            "pid": 321,
            "ok": true,
            "spd": .null,
            "run": "20261029-213500-S3-1-AK",
            "up": 1234.5,
            "big": .int(9_000_000_000),
            "neg": -7,
            "ctl": .string("a\u{01}b\u{2028}c"),
        ]
        let line = try FlatJson.encode(fields)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertFalse(line.contains("\r"))
        XCTAssertTrue(line.hasPrefix("{\"ev\":\"fix\",\"t\":\"2026-10-29T21:35:12.345+07:00\",\"up\":1234.5,\"run\":"))
        let order = ["\"ev\"", "\"t\"", "\"up\"", "\"run\"", "\"pid\"", "\"seq\"", "\"launch\"", "\"acc\"", "\"big\"",
                     "\"ctl\"", "\"neg\"", "\"ok\"", "\"spd\"", "\"zeta\""]
        var last = line.startIndex
        for key in order {
            guard let r = line.range(of: key, range: last..<line.endIndex) else {
                return XCTFail("key \(key) missing or out of order in \(line)")
            }
            last = r.upperBound
        }
        let back = try FlatJson.decode(line)
        XCTAssertEqual(back, fields)
    }

    func testDecodeAcceptsWhitespaceEscapesAndSurrogates() throws {
        let map = try FlatJson.decode(" { \"a\" : \"x\\u00e9\\ud83d\\ude00\\/\" , \"b\" : 1e3 , \"c\" : -2 } ")
        XCTAssertEqual(map["a"], .string("xé😀/"))
        XCTAssertEqual(map["b"], .double(1000))
        XCTAssertEqual(map["c"], .int(-2))
    }

    // U2
    func testNestedValuesAreRejected() {
        XCTAssertThrowsError(try FlatJson.decode("{\"a\":{\"b\":1}}")) { error in
            guard case FlatJsonError.notFlat = error else { return XCTFail("expected notFlat, got \(error)") }
        }
        XCTAssertThrowsError(try FlatJson.decode("{\"a\":[1,2]}")) { error in
            guard case FlatJsonError.notFlat = error else { return XCTFail("expected notFlat, got \(error)") }
        }
    }

    func testMalformedLinesAreRejected() {
        for bad in ["", "{", "{\"a\":1", "{\"a\":1}x", "{\"a\":tru}", "{\"a\":\"x}", "[1]", "{\"a\":01x}"] {
            XCTAssertThrowsError(try FlatJson.decode(bad), "should reject: \(bad)")
        }
    }

    // U11
    func testCoordinateKeysAreRefused() {
        for key in FlatJson.forbiddenKeys.sorted() + ["Lat", "LONGITUDE"] {
            XCTAssertThrowsError(try FlatJson.encode(["ev": "fix", key: 21.0])) { error in
                XCTAssertEqual(error as? FlatJsonError, .forbiddenKey(key))
            }
        }
        XCTAssertEqual(
            FlatJson.forbiddenKeys,
            ["lat", "lng", "lon", "latitude", "longitude", "alt", "altitude", "coordinate"]
        )
    }

    func testNonFiniteDoubleIsNull() throws {
        XCTAssertEqual(try FlatJson.encode(["x": .double(.infinity)]), "{\"x\":null}")
        XCTAssertEqual(JSONScalar.num(Double.nan), .null)
        XCTAssertEqual(JSONScalar.num(nil as Double?), .null)
        XCTAssertEqual(JSONScalar.str(nil), .null)
        XCTAssertEqual(JSONScalar.flag(false), .bool(false))
    }
}

final class FormattingTests: XCTestCase {
    func testIsoFormatAndParseRoundTrip() throws {
        // 2026-10-29T14:35:12.345Z
        let date = Date(timeIntervalSince1970: 1_793_284_512.345)
        let s = IsoTime.format(date, offsetSeconds: 7 * 3600)
        XCTAssertEqual(s, "2026-10-29T21:35:12.345+07:00")
        let back = try XCTUnwrap(IsoTime.parse(s))
        XCTAssertEqual(IsoTime.epochMs(back), IsoTime.epochMs(date))
        XCTAssertEqual(IsoTime.format(date, offsetSeconds: -(3 * 3600 + 1800)), "2026-10-29T11:05:12.345-03:30")
        XCTAssertEqual(IsoTime.compact(date, offsetSeconds: 7 * 3600), "20261029-213512")
        XCTAssertEqual(IsoTime.clock(date, offsetSeconds: 7 * 3600), "21:35:12")
    }

    func testIsoParseVariants() throws {
        let z = try XCTUnwrap(IsoTime.parse("2026-10-29T14:35:12Z"))
        XCTAssertEqual(IsoTime.epochMs(z), 1_793_284_512_000)
        let compactOffset = try XCTUnwrap(IsoTime.parse("2026-10-29T21:35:12.5+0700"))
        XCTAssertEqual(IsoTime.epochMs(compactOffset), 1_793_284_512_500)
        let leap = try XCTUnwrap(IsoTime.parse("2024-02-29T00:00:00.000+00:00"))
        XCTAssertEqual(IsoTime.format(leap, offsetSeconds: 0), "2024-02-29T00:00:00.000+00:00")
        let preEpoch = try XCTUnwrap(IsoTime.parse("1969-12-31T23:59:59.999Z"))
        XCTAssertEqual(IsoTime.epochMs(preEpoch), -1)
        XCTAssertNil(IsoTime.parse("2026-10-29 14:35"))
        XCTAssertNil(IsoTime.parse("2026-13-01T00:00:00Z"))
        XCTAssertNil(IsoTime.parse("2026-10-29T14:35:12"))
    }

    func testFourCC() {
        XCTAssertEqual(FourCC.string(0x21_69_6E_74), "!int")   // cannotInterruptOthers
        XCTAssertEqual(FourCC.string(0x21_70_6C_61), "!pla")   // cannotStartPlaying
        XCTAssertNil(FourCC.string(0))
        XCTAssertNil(FourCC.string(-50))
        XCTAssertNil(FourCC.string(12))
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.vi(45), "45 s")
        XCTAssertEqual(DurationText.vi(125), "2 ph 05 s")
        XCTAssertEqual(DurationText.vi(3725), "1 g 02 ph")
    }
}
