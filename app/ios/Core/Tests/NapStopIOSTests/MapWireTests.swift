import Foundation
import Testing
@testable import NapStopIOS

/// T23.3 SW01–SW04: the Swift end of the map channel (docs/specs/T23.3.md §2, §4.1), same cases as the Dart side.
@Suite("MapWire")
struct MapWireTests {
    // MARK: fixtures/map_wire/cases.json

    /// JSON value with booleans kept apart from numbers (JSONDecoder is strict on both platforms).
    enum JSONValue: Decodable {
        case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                self = .null
            } else if let b = try? c.decode(Bool.self) {
                self = .bool(b)
            } else if let d = try? c.decode(Double.self) {
                self = .number(d)
            } else if let s = try? c.decode(String.self) {
                self = .string(s)
            } else if let a = try? c.decode([JSONValue].self) {
                self = .array(a)
            } else {
                self = .object(try c.decode([String: JSONValue].self))
            }
        }

        /// What `FlutterStandardMessageCodec` would hand over: NSNull for null, Swift values otherwise.
        var codecValue: Any {
            switch self {
            case .null: return NSNull()
            case .bool(let b): return b
            case .number(let d): return d
            case .string(let s): return s
            case .array(let a): return a.map(\.codecValue)
            case .object(let o): return o.mapValues(\.codecValue)
            }
        }

        subscript(_ key: String) -> JSONValue? {
            if case .object(let o) = self { return o[key] }
            return nil
        }

        var double: Double? {
            if case .number(let d) = self { return d }
            return nil
        }

        var boolValue: Bool? {
            if case .bool(let b) = self { return b }
            return nil
        }

        var list: [JSONValue] {
            if case .array(let a) = self { return a }
            return []
        }
    }

    struct Case {
        let name: String
        let input: JSONValue
        let valid: Bool
        /// T24.3: expected glyph of a `state` case (absent = nil).
        var glyph: MapPinGlyph? = nil
    }

    static let repoRoot: String = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("fixtures/map_wire/cases.json").path) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return "."
    }()

    static func cases(_ group: String) throws -> [Case] {
        let data = try Data(contentsOf: URL(fileURLWithPath: repoRoot + "/fixtures/map_wire/cases.json"))
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(root["version"]?.double == 1)
        return (root[group]?.list ?? []).map { c in
            Case(
                name: { if case .string(let s) = c["name"] { return s } else { return "?" } }(),
                input: c["input"] ?? .null, valid: c["valid"]?.boolValue ?? false,
                glyph: { if case .string(let s) = c["glyph"] { return MapPinGlyph(rawValue: s) } else { return nil } }())
        }
    }

    static func coordinate(_ v: JSONValue?) -> MapCoordinate? {
        guard let l = v?.list, l.count == 2, let lat = l[0].double, let lng = l[1].double else { return nil }
        return MapCoordinate(lat: lat, lng: lng)
    }

    static func bounds(_ v: JSONValue?) -> MapBoundsWire? {
        guard let v, let s = v["s"]?.double, let w = v["w"]?.double, let n = v["n"]?.double, let e = v["e"]?.double
        else { return nil }
        return MapBoundsWire(s: s, w: w, n: n, e: e)
    }

    static func expectedState(_ v: JSONValue, glyph: MapPinGlyph? = nil) -> MapStateWire {
        MapStateWire(
            pin: coordinate(v["pin"]), radiusM: v["radiusM"]?.double, pinDraggable: v["pinDraggable"]!.boolValue!,
            longPress: v["longPress"]!.boolValue!, showsUser: v["showsUser"]!.boolValue!, dark: v["dark"]!.boolValue!,
            glyph: glyph)
    }

    // MARK: SW01 state

    static var validState: [String: Any] {
        [
            "pin": [16.47, 107.59], "radiusM": 1000.0, "pinDraggable": true, "longPress": true, "showsUser": false,
            "dark": true,
        ]
    }

    @Test("SW01 a valid state")
    func validStateParses() {
        let s = MapWire.state(Self.validState)
        #expect(
            s == MapStateWire(
                pin: MapCoordinate(lat: 16.47, lng: 107.59), radiusM: 1000, pinDraggable: true, longPress: true,
                showsUser: false, dark: true))
        var none = Self.validState
        none["pin"] = NSNull()
        none["radiusM"] = NSNull()
        #expect(MapWire.state(none)?.pin == nil)
        #expect(MapWire.state(none)?.radiusM == nil)
        // Missing optional keys = null.
        none.removeValue(forKey: "pin")
        #expect(MapWire.state(none) != nil)
        // Integers are numbers too.
        var ints = Self.validState
        ints["radiusM"] = 1000
        ints["pin"] = [16, 107]
        #expect(MapWire.state(ints)?.radiusM == 1000)
        #expect(MapWire.state(ints)?.pin == MapCoordinate(lat: 16, lng: 107))
    }

    @Test("BS-S02 glyph: optional, unknown values ignored (T24.3)")
    func glyph() {
        var bus = Self.validState
        bus["glyph"] = "bus"
        #expect(MapWire.state(bus)?.glyph == .bus)
        #expect(MapWire.state(Self.validState)?.glyph == nil)
        var unknown = Self.validState
        unknown["glyph"] = "tram"
        #expect(MapWire.state(unknown) != nil)
        #expect(MapWire.state(unknown)?.glyph == nil)
        var null = Self.validState
        null["glyph"] = NSNull()
        #expect(MapWire.state(null)?.glyph == nil)
        var number = Self.validState
        number["glyph"] = 1
        #expect(MapWire.state(number)?.glyph == nil)
        #expect(MapStateWire.empty.glyph == nil)
    }

    @Test("SW01 an invalid state is nil")
    func invalidStateIsNil() {
        func with(_ key: String, _ value: Any?) -> [String: Any] {
            var m = Self.validState
            if let value { m[key] = value } else { m.removeValue(forKey: key) }
            return m
        }
        let bad: [(String, Any?)] = [
            ("pin", [Double.nan, 1.0]), ("pin", [91.0, 0.0]), ("pin", [1.0]), ("pin", "x"),
            ("radiusM", Double.nan), ("radiusM", Double.infinity), ("radiusM", 0.0), ("radiusM", 100_001.0),
            ("radiusM", "1000"), ("pinDraggable", "yes"), ("pinDraggable", NSNull()), ("dark", nil), ("longPress", nil),
        ]
        for (key, value) in bad {
            #expect(MapWire.state(with(key, value)) == nil, "\(key)")
        }
        #expect(MapWire.state("x") == nil)
        #expect(MapWire.state(nil) == nil)
        #expect(MapWire.state(NSNull()) == nil)
        #expect(MapWire.state([1, 2]) == nil)
    }

    @Test("SW01 coordinates")
    func coordinates() {
        #expect(MapWire.coordinate([16.47, 107.59]) == MapCoordinate(lat: 16.47, lng: 107.59))
        #expect(MapWire.coordinate([90.0, 180.0]) != nil)
        #expect(MapWire.coordinate([-90.0, -180.0]) != nil)
        let bad: [Any?] = [[Double.nan, 1.0], [1.0, Double.infinity], [91.0, 0.0], [0.0, 181.0], [1.0], "x", nil]
        for bad in bad {
            #expect(MapWire.coordinate(bad) == nil)
        }
        #expect(MapWire.pointArgs(MapCoordinate(lat: 1.5, lng: 2.5)) == [1.5, 2.5])
        #expect(MapCoordinate(lat: 16.47, lng: 107.59).description == "MapCoordinate")
        #expect(!String(describing: MapWire.state(Self.validState)!).contains("16"))
        #expect(MapWire.channelName(7) == "app.napstop/nap_map/7")
    }

    // MARK: SW02 frame

    static var validFrame: [String: Any] {
        [
            "bounds": ["s": 17.4, "w": 106.5, "n": 17.5, "e": 106.7], "pad": [191.0, 48.0, 48.0, 48.0],
            "animated": true, "includeUser": false,
        ]
    }

    @Test("SW02 frames")
    func frames() {
        let f = MapWire.frame(Self.validFrame)
        #expect(f?.bounds == MapBoundsWire(s: 17.4, w: 106.5, n: 17.5, e: 106.7))
        #expect(f?.pad == MapInsets(top: 191, left: 48, bottom: 48, right: 48))
        #expect(f?.animated == true)
        #expect(f?.includeUser == false)
        func with(_ key: String, _ value: Any) -> [String: Any] {
            var m = Self.validFrame
            m[key] = value
            return m
        }
        #expect(MapWire.frame(with("pad", [-1.0, 0.0, 0.0, 0.0])) == nil)
        #expect(MapWire.frame(with("pad", [0.0, 0.0, 4001.0, 0.0])) == nil)
        #expect(MapWire.frame(with("pad", [0.0, 0.0, Double.nan, 0.0])) == nil)
        #expect(MapWire.frame(with("pad", [0.0, 0.0, 0.0])) == nil)
        #expect(MapWire.frame(with("bounds", ["s": 17.6, "w": 106.5, "n": 17.5, "e": 106.7])) == nil)
        #expect(MapWire.frame(with("bounds", ["s": 17.4, "w": 106.8, "n": 17.5, "e": 106.7])) == nil)
        #expect(MapWire.frame(with("animated", "yes")) == nil)
        #expect(MapWire.frame("x") == nil)
    }

    // MARK: SW03 creation

    static var validCreation: [String: Any] {
        [
            "v": 1, "state": validState, "initial": ["s": 8.3, "w": 102.0, "n": 23.6, "e": 109.7],
            "centerBounds": ["s": 8.3, "w": 102.0, "n": 23.6, "e": 109.4], "maxDistanceM": 800_000.0,
            "accent": 4_280_903_660, "pinLabel": "Điểm đến",
        ]
    }

    @Test("SW03 creation params")
    func creation() {
        let c = MapWire.creation(Self.validCreation)
        #expect(c?.accentARGB == 4_280_903_660)
        #expect(c?.pinLabel == "Điểm đến")
        #expect(c?.maxDistanceM == 800_000)
        #expect(c?.centerBounds == MapBoundsWire(s: 8.3, w: 102.0, n: 23.6, e: 109.4))
        func with(_ key: String, _ value: Any?) -> [String: Any] {
            var m = Self.validCreation
            if let value { m[key] = value } else { m.removeValue(forKey: key) }
            return m
        }
        #expect(MapWire.creation(with("v", 2)) == nil)
        #expect(MapWire.creation(with("v", nil)) == nil)
        #expect(MapWire.creation(with("state", nil)) == nil)
        #expect(MapWire.creation(with("initial", nil)) == nil)
        #expect(MapWire.creation(with("accent", -1)) == nil)
        #expect(MapWire.creation(with("accent", 1.5)) == nil)
        #expect(MapWire.creation(with("maxDistanceM", 0.0)) == nil)
        #expect(MapWire.creation(with("pinLabel", nil)) == nil)
        #expect(MapWire.creation(with("centerBounds", NSNull()))?.centerBounds == nil)
        #expect(MapWire.creation(with("maxDistanceM", NSNull()))?.maxDistanceM == nil)
        #expect(MapWire.creation(nil) == nil)
        // D11 keys: optional, validated when present.
        #expect(MapWire.creation(Self.validCreation)?.eastLimit == nil)
        #expect(MapWire.creation(with("eastLimit", 110.9))?.eastLimit == 110.9)
        #expect(MapWire.creation(with("maxLngSpan", 8.8))?.maxLngSpan == 8.8)
        #expect(MapWire.creation(with("eastLimit", Double.nan)) == nil)
        #expect(MapWire.creation(with("eastLimit", 181.0)) == nil)
        #expect(MapWire.creation(with("maxLngSpan", 0.0)) == nil)
        #expect(MapWire.creation(with("maxLngSpan", Double.infinity)) == nil)
        // The fallback is itself a valid creation.
        #expect(MapCreationWire.fallback.state == .empty)
    }

    // MARK: MW06b camera guard (same table as the Dart centerEastLimit)

    static func spanValue(_ v: JSONValue?) -> Double {
        if case .string(let s) = v, s == "NaN" { return .nan }
        return v?.double ?? .nan
    }

    static func root() throws -> JSONValue {
        let data = try Data(contentsOf: URL(fileURLWithPath: repoRoot + "/fixtures/map_wire/cases.json"))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    @Test("MW06b centerEastLimit of fixtures/map_wire/cases.json")
    func guardEastLimit() throws {
        let table = try Self.root()["centerEastLimit"]
        let cap = try #require(table?["capEast"]?.double)
        let limit = try #require(table?["eastLimit"]?.double)
        #expect(cap == 109.4 && limit == 110.9)
        let cases = table?["cases"]?.list ?? []
        #expect(cases.count >= 7)
        for c in cases {
            let span = Self.spanValue(c["span"])
            let got = MapCameraGuard.centerEastLimit(visibleLngSpan: span, capEast: cap, eastLimit: limit)
            let want = try #require(c["expect"]?.double)
            #expect(abs(got - want) < 1e-9, "span \(span)")
        }
        #expect(MapCameraGuard.centerEastLimit(visibleLngSpan: .infinity, capEast: cap, eastLimit: limit) == cap)
    }

    @Test("MW06b targetLngSpan of fixtures/map_wire/cases.json (R2-1, R3-1)")
    func guardTargetSpan() throws {
        let cases = try Self.root()["targetLngSpan"]?.list ?? []
        #expect(cases.count >= 11)
        for c in cases {
            let name: String
            if case .string(let s) = c["name"] { name = s } else { name = "?" }
            let got = MapCameraGuard.targetLngSpan(
                rectLngSpan: Self.spanValue(c["rect"]), rectHeightLng: Self.spanValue(c["height"]),
                viewWidth: Self.spanValue(c["width"]), viewHeight: Self.spanValue(c["viewHeight"]),
                padTop: Self.spanValue(c["top"]), padLeft: Self.spanValue(c["left"]),
                padBottom: Self.spanValue(c["bottom"]), padRight: Self.spanValue(c["right"]))
            if let want = c["expect"]?.double {
                #expect(got != nil && abs(got! - want) < 1e-9, "\(name)")
            } else {
                #expect(got == nil, "\(name)")
            }
        }
        // R3-1: a box taller than wide in the landscape card is height-limited, and the boundary must follow the
        // larger (height-derived) span, not the width one.
        let card = try #require(
            MapCameraGuard.targetLngSpan(
                rectLngSpan: 1, rectHeightLng: 2, viewWidth: 358, viewHeight: 240, padTop: 48, padLeft: 48,
                padBottom: 48, padRight: 48))
        #expect(card > 1 * 358 / 262.0)
        #expect(MapCameraGuard.centerEastLimit(visibleLngSpan: card, capEast: 109.4, eastLimit: 110.9) < 108.5)
        // R2-1 scenario: zoomed out to 5° (boundary 108.4), framing a 1 km zone around Ga Nha Trang (109.18°E) in a
        // 390 pt view with 48 pt side paddings: the boundary for the target span goes back to 109.4.
        let zone = 2 * 1000 / (111_320 * cos(12.25 * Double.pi / 180))
        let target = try #require(
            MapCameraGuard.targetLngSpan(
                rectLngSpan: zone, rectHeightLng: zone, viewWidth: 390, viewHeight: 530, padTop: 191, padLeft: 48,
                padBottom: 48, padRight: 48))
        #expect(MapCameraGuard.centerEastLimit(visibleLngSpan: 5, capEast: 109.4, eastLimit: 110.9) < 109.18)
        #expect(MapCameraGuard.centerEastLimit(visibleLngSpan: target, capEast: 109.4, eastLimit: 110.9) == 109.4)
    }

    @Test("MW06b maxDistance of fixtures/map_wire/cases.json")
    func guardMaxDistance() throws {
        let cases = try Self.root()["maxDistance"]?.list ?? []
        #expect(cases.count >= 7)
        for c in cases {
            let got = MapCameraGuard.maxDistance(
                currentDistance: Self.spanValue(c["distance"]), currentLngSpan: Self.spanValue(c["span"]),
                maxLngSpan: Self.spanValue(c["maxSpan"]))
            if let want = c["expect"]?.double {
                #expect(got != nil && abs(got! - want) < 1e-6, "\(want)")
            } else {
                #expect(got == nil)
            }
        }
    }

    // MARK: SW04 parity

    @Test("SW04 points of fixtures/map_wire/cases.json")
    func parityPoints() throws {
        let cases = try Self.cases("point")
        #expect(!cases.isEmpty)
        for c in cases {
            let parsed = MapWire.coordinate(c.input.codecValue)
            #expect((parsed != nil) == c.valid, "\(c.name)")
            if let parsed { #expect(parsed == Self.coordinate(c.input), "\(c.name)") }
        }
    }

    @Test("SW04 states of fixtures/map_wire/cases.json")
    func parityStates() throws {
        let cases = try Self.cases("state")
        #expect(cases.contains { $0.valid } && cases.contains { !$0.valid })
        for c in cases {
            let parsed = MapWire.state(c.input.codecValue)
            #expect((parsed != nil) == c.valid, "\(c.name)")
            if let parsed { #expect(parsed == Self.expectedState(c.input, glyph: c.glyph), "\(c.name)") }
        }
    }

    @Test("SW04 frames of fixtures/map_wire/cases.json")
    func parityFrames() throws {
        let cases = try Self.cases("frame")
        #expect(cases.contains { $0.valid } && cases.contains { !$0.valid })
        for c in cases {
            let parsed = MapWire.frame(c.input.codecValue)
            #expect((parsed != nil) == c.valid, "\(c.name)")
            guard let parsed else { continue }
            let pad = c.input["pad"]!.list.map { $0.double! }
            #expect(parsed.bounds == Self.bounds(c.input["bounds"]), "\(c.name)")
            #expect(parsed.pad == MapInsets(top: pad[0], left: pad[1], bottom: pad[2], right: pad[3]), "\(c.name)")
            #expect(parsed.animated == c.input["animated"]?.boolValue, "\(c.name)")
            #expect(parsed.includeUser == c.input["includeUser"]?.boolValue, "\(c.name)")
        }
    }

    @Test("SW04 creation params of fixtures/map_wire/cases.json")
    func parityCreation() throws {
        let cases = try Self.cases("creation")
        #expect(cases.contains { $0.valid } && cases.contains { !$0.valid })
        for c in cases {
            let parsed = MapWire.creation(c.input.codecValue)
            #expect((parsed != nil) == c.valid, "\(c.name)")
            guard let parsed else { continue }
            #expect(parsed.state == Self.expectedState(c.input["state"]!), "\(c.name)")
            #expect(parsed.initial == Self.bounds(c.input["initial"]), "\(c.name)")
            #expect(parsed.centerBounds == Self.bounds(c.input["centerBounds"]), "\(c.name)")
            #expect(parsed.maxDistanceM == c.input["maxDistanceM"]?.double, "\(c.name)")
            #expect(Double(parsed.accentARGB) == c.input["accent"]?.double, "\(c.name)")
            #expect(parsed.eastLimit == c.input["eastLimit"]?.double, "\(c.name)")
            #expect(parsed.maxLngSpan == c.input["maxLngSpan"]?.double, "\(c.name)")
            if case .string(let label) = c.input["pinLabel"] { #expect(parsed.pinLabel == label, "\(c.name)") }
        }
    }
}
