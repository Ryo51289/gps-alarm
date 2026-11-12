// Wire format v1 of the MapKit platform view (docs/specs/T23.3.md §2, D5). Foundation only, no `#if os(iOS)`: parsed and
// tested on Linux (`test-wsl.sh`), same cases as the Dart side (`fixtures/map_wire/cases.json`).
// Values come from `FlutterStandardMessageCodec` (NSNumber, NSString, NSArray, NSDictionary, NSNull) on iOS, or from
// native Swift values in tests. An invalid message gives nil: the caller ignores it, never throws, never logs.
// PRIVACY: nothing here logs, and no `description` prints a coordinate.
import Foundation

public struct MapCoordinate: Equatable, Sendable, CustomStringConvertible {
    public let lat: Double
    public let lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    public var description: String { "MapCoordinate" }
}

public struct MapBoundsWire: Equatable, Sendable, CustomStringConvertible {
    public let s: Double
    public let w: Double
    public let n: Double
    public let e: Double

    public init(s: Double, w: Double, n: Double, e: Double) {
        self.s = s
        self.w = w
        self.n = n
        self.e = e
    }

    public var description: String { "MapBoundsWire" }
}

public struct MapInsets: Equatable, Sendable {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// Symbol drawn inside the pin (T24.3 §6.6): optional `glyph` key of `<State>`.
public enum MapPinGlyph: String, Sendable {
    /// A roadside bus stop: SF Symbol `bus.fill`.
    case bus
}

public struct MapStateWire: Equatable, Sendable, CustomStringConvertible {
    public let pin: MapCoordinate?
    /// Alarm zone; nil = no circle.
    public let radiusM: Double?
    public let pinDraggable: Bool
    public let longPress: Bool
    public let showsUser: Bool
    public let dark: Bool
    /// T24.3: symbol inside the pin; nil = the plain pin (key absent, null or unknown).
    public let glyph: MapPinGlyph?

    public init(
        pin: MapCoordinate?, radiusM: Double?, pinDraggable: Bool, longPress: Bool, showsUser: Bool, dark: Bool,
        glyph: MapPinGlyph? = nil
    ) {
        self.pin = pin
        self.radiusM = radiusM
        self.pinDraggable = pinDraggable
        self.longPress = longPress
        self.showsUser = showsUser
        self.dark = dark
        self.glyph = glyph
    }

    /// Nothing chosen: the safe default when the creation params are invalid.
    public static let empty = MapStateWire(
        pin: nil, radiusM: nil, pinDraggable: false, longPress: false, showsUser: false, dark: false)

    public var description: String { "MapStateWire(pin: \(pin == nil ? "none" : "set"))" }
}

public struct MapFrameWire: Equatable, Sendable {
    public let bounds: MapBoundsWire
    public let pad: MapInsets
    public let animated: Bool
    public let includeUser: Bool

    public init(bounds: MapBoundsWire, pad: MapInsets, animated: Bool, includeUser: Bool) {
        self.bounds = bounds
        self.pad = pad
        self.animated = animated
        self.includeUser = includeUser
    }
}

public struct MapCreationWire: Equatable, Sendable {
    public let state: MapStateWire
    public let initial: MapBoundsWire
    public let centerBounds: MapBoundsWire?
    public let maxDistanceM: Double?
    /// D11: the visible east edge never passes this longitude (layer 2); nil = off.
    public let eastLimit: Double?
    /// D11 layer 1: widest visible longitude span; nil = keep maxDistanceM fixed.
    public let maxLngSpan: Double?
    public let accentARGB: UInt32
    public let pinLabel: String

    public init(
        state: MapStateWire, initial: MapBoundsWire, centerBounds: MapBoundsWire?, maxDistanceM: Double?,
        eastLimit: Double? = nil, maxLngSpan: Double? = nil, accentARGB: UInt32, pinLabel: String
    ) {
        self.state = state
        self.initial = initial
        self.centerBounds = centerBounds
        self.maxDistanceM = maxDistanceM
        self.eastLimit = eastLimit
        self.maxLngSpan = maxLngSpan
        self.accentARGB = accentARGB
        self.pinLabel = pinLabel
    }

    /// Vietnam, nothing chosen, no camera limit: used when the creation params are invalid, so the view never crashes.
    public static let fallback = MapCreationWire(
        state: .empty, initial: MapBoundsWire(s: 8.3, w: 102.0, n: 23.6, e: 109.7), centerBounds: nil,
        maxDistanceM: nil, accentARGB: 0xFF2B_4FEC, pinLabel: "")
}

public enum MapWire {
    public static let version = 1
    public static let viewType = "app.napstop/nap_map"
    public static let maxRadiusM = 100_000.0
    public static let maxPaddingPt = 4000.0

    public static func channelName(_ viewId: Int64) -> String { "\(viewType)/\(viewId)" }

    /// §2: finite, lat in [-90, 90], lng in [-180, 180].
    public static func validLatLng(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && (-90...90).contains(lat) && (-180...180).contains(lng)
    }

    /// `[lat, lng]` with valid numbers.
    public static func coordinate(_ any: Any?) -> MapCoordinate? {
        guard let list = array(any), list.count == 2, let lat = number(list[0]), let lng = number(list[1]),
            validLatLng(lat, lng)
        else { return nil }
        return MapCoordinate(lat: lat, lng: lng)
    }

    public static func bounds(_ any: Any?) -> MapBoundsWire? {
        guard let m = dict(any), let s = number(m["s"]), let w = number(m["w"]), let n = number(m["n"]),
            let e = number(m["e"]), validLatLng(s, w), validLatLng(n, e), s <= n, w <= e
        else { return nil }
        return MapBoundsWire(s: s, w: w, n: n, e: e)
    }

    public static func state(_ any: Any?) -> MapStateWire? {
        guard let m = dict(any) else { return nil }
        var pin: MapCoordinate?
        if !isNull(m["pin"]) {
            guard let p = coordinate(m["pin"]) else { return nil }
            pin = p
        }
        var radius: Double?
        if !isNull(m["radiusM"]) {
            guard let r = number(m["radiusM"]), r.isFinite, r > 0, r <= maxRadiusM else { return nil }
            radius = r
        }
        guard let draggable = bool(m["pinDraggable"]), let longPress = bool(m["longPress"]),
            let showsUser = bool(m["showsUser"]), let dark = bool(m["dark"])
        else { return nil }
        // T24.3: optional; anything but a known name is ignored, never invalid (older and newer Dart both work).
        let glyph = string(m["glyph"]).flatMap(MapPinGlyph.init(rawValue:))
        return MapStateWire(
            pin: pin, radiusM: radius, pinDraggable: draggable, longPress: longPress, showsUser: showsUser, dark: dark,
            glyph: glyph)
    }

    public static func frame(_ any: Any?) -> MapFrameWire? {
        guard let m = dict(any), let b = bounds(m["bounds"]), let padList = array(m["pad"]), padList.count == 4,
            let animated = bool(m["animated"]), let includeUser = bool(m["includeUser"])
        else { return nil }
        var pad: [Double] = []
        for v in padList {
            guard let d = number(v), d.isFinite, d >= 0, d <= maxPaddingPt else { return nil }
            pad.append(d)
        }
        return MapFrameWire(
            bounds: b, pad: MapInsets(top: pad[0], left: pad[1], bottom: pad[2], right: pad[3]), animated: animated,
            includeUser: includeUser)
    }

    /// `"v" == 1`, every field valid.
    public static func creation(_ any: Any?) -> MapCreationWire? {
        guard let m = dict(any), let v = number(m["v"]), v == Double(version), let st = state(m["state"]),
            let initial = bounds(m["initial"]), let accent = number(m["accent"]), accent.isFinite,
            accent == accent.rounded(), accent >= 0, accent <= Double(UInt32.max), let label = m["pinLabel"] as? String
        else { return nil }
        var center: MapBoundsWire?
        if !isNull(m["centerBounds"]) {
            guard let c = bounds(m["centerBounds"]) else { return nil }
            center = c
        }
        var maxDistance: Double?
        if !isNull(m["maxDistanceM"]) {
            guard let d = number(m["maxDistanceM"]), d.isFinite, d > 0 else { return nil }
            maxDistance = d
        }
        var eastLimit: Double?
        if !isNull(m["eastLimit"]) {
            guard let e = number(m["eastLimit"]), e.isFinite, (-180...180).contains(e) else { return nil }
            eastLimit = e
        }
        var maxSpan: Double?
        if !isNull(m["maxLngSpan"]) {
            guard let s = number(m["maxLngSpan"]), s.isFinite, s > 0, s <= 360 else { return nil }
            maxSpan = s
        }
        return MapCreationWire(
            state: st, initial: initial, centerBounds: center, maxDistanceM: maxDistance, eastLimit: eastLimit,
            maxLngSpan: maxSpan, accentARGB: UInt32(accent), pinLabel: label)
    }

    /// Native → Dart point (`longPress`, `pinDragEnd`).
    public static func pointArgs(_ c: MapCoordinate) -> [Double] { [c.lat, c.lng] }

    /// `diagState` bounds.
    public static func boundsArgs(_ b: MapBoundsWire) -> [String: Double] { ["s": b.s, "w": b.w, "n": b.n, "e": b.e] }

    // MARK: - value helpers (codec types on iOS, native Swift values in tests)

    static func isNull(_ v: Any?) -> Bool {
        guard let v else { return true }
        return v is NSNull
    }

    static func number(_ v: Any?) -> Double? {
        guard !isNull(v), let v else { return nil }
        if v is String || v is NSString { return nil }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let i = v as? Int64 { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    static func string(_ v: Any?) -> String? {
        guard !isNull(v), let v else { return nil }
        if let s = v as? String { return s }
        if let s = v as? NSString { return s as String }
        return nil
    }

    static func bool(_ v: Any?) -> Bool? {
        guard !isNull(v), let v else { return nil }
        if v is String || v is NSString { return nil }
        return v as? Bool
    }

    static func array(_ v: Any?) -> [Any]? {
        guard !isNull(v), let v else { return nil }
        if v is String || v is NSString { return nil }
        return v as? [Any]
    }

    static func dict(_ v: Any?) -> [String: Any]? {
        guard !isNull(v), let v else { return nil }
        return v as? [String: Any]
    }
}
