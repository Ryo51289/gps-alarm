// Wire format v1 of the address search channel `app.napstop/address_search` (docs/specs/T23.5.md §3, §5.1).
// Foundation only, no `#if os(iOS)`: parsed and tested on Linux (`test-wsl.sh`), same cases as the Dart side
// (`fixtures/address_search_wire/cases.json`). Values come from `FlutterStandardMessageCodec` on iOS, or from native
// Swift values in tests. An invalid message gives nil: the caller answers `failed`, never throws, never logs.
// PRIVACY: nothing here logs, and no `description` prints the typed text or a coordinate.
import Foundation

public struct AddressCompleteRequest: Equatable, Sendable, CustomStringConvertible {
    public let gen: Int64
    public let query: String
    public let region: MapBoundsWire

    public init(gen: Int64, query: String, region: MapBoundsWire) {
        self.gen = gen
        self.query = query
        self.region = region
    }

    public var description: String { "AddressCompleteRequest" }
}

public struct AddressResolveRequest: Equatable, Sendable, CustomStringConvertible {
    public let gen: Int64
    public let index: Int

    public init(gen: Int64, index: Int) {
        self.gen = gen
        self.index = index
    }

    public var description: String { "AddressResolveRequest" }
}

/// One entry of the `diagFake` source (NAPSTOP_DIAG integration tests).
public struct AddressFakeItem: Equatable, Sendable, CustomStringConvertible {
    public let t: String
    public let s: String
    public let lat: Double
    public let lng: Double
    public let country: String?

    public init(t: String, s: String, lat: Double, lng: Double, country: String?) {
        self.t = t
        self.s = s
        self.lat = lat
        self.lng = lng
        self.country = country
    }

    public var description: String { "AddressFakeItem" }
}

public enum AddressSearchWire {
    public static let channel = "app.napstop/address_search"
    public static let version = 1
    public static let maxQueryRunes = 64
    public static let maxItems = 15
    public static let mkErrorDomain = "MKErrorDomain"
    public static let urlErrorDomain = "NSURLErrorDomain"
    /// `MKError.Code.loadingThrottled` / `.placemarkNotFound`; the XCTest AS-X01 checks them against MapKit on CI.
    public static let mkLoadingThrottled = 3
    public static let mkPlacemarkNotFound = 4

    public static func completeRequest(_ any: Any?) -> AddressCompleteRequest? {
        guard let m = MapWire.dict(any), isVersion(m["v"]), let gen = integer(m["gen"]),
            let query = m["query"] as? String, query.unicodeScalars.count <= maxQueryRunes,
            let region = MapWire.bounds(m["region"])
        else { return nil }
        return AddressCompleteRequest(gen: gen, query: query, region: region)
    }

    public static func resolveRequest(_ any: Any?) -> AddressResolveRequest? {
        guard let m = MapWire.dict(any), isVersion(m["v"]), let gen = integer(m["gen"]),
            let index = integer(m["index"]), index >= 0, index <= Int64(Int32.max)
        else { return nil }
        return AddressResolveRequest(gen: gen, index: Int(index))
    }

    /// `items` only with status "ok", cut to `maxItems`.
    public static func completeReply(gen: Int64, status: String, items: [(title: String, subtitle: String)])
        -> [String: Any]
    {
        var reply: [String: Any] = ["gen": gen, "status": status]
        if status == "ok" {
            reply["items"] = items.prefix(maxItems).map { ["t": $0.title, "s": $0.subtitle] }
        }
        return reply
    }

    public static func resolveOk(lat: Double, lng: Double, country: String?) -> [String: Any] {
        ["status": "ok", "lat": lat, "lng": lng, "country": country.map { $0 as Any } ?? NSNull()]
    }

    public static func status(_ s: String) -> [String: Any] { ["status": s] }

    /// §3 error table: throttled, notFound, network, failed.
    public static func errorStatus(domain: String, code: Int, underlyingDomain: String?) -> String {
        if domain == mkErrorDomain {
            if code == mkLoadingThrottled { return "throttled" }
            if code == mkPlacemarkNotFound { return "notFound" }
        }
        if domain == urlErrorDomain || underlyingDomain == urlErrorDomain { return "network" }
        return "failed"
    }

    /// `diagFake` arguments: `{"items": [{"t","s","lat","lng","country"}]}`; null or invalid gives nil.
    public static func fakeItems(_ any: Any?) -> [AddressFakeItem]? {
        guard let m = MapWire.dict(any), let list = MapWire.array(m["items"]) else { return nil }
        var out: [AddressFakeItem] = []
        for entry in list {
            guard let e = MapWire.dict(entry), let t = e["t"] as? String, let s = e["s"] as? String,
                let lat = MapWire.number(e["lat"]), let lng = MapWire.number(e["lng"]), MapWire.validLatLng(lat, lng)
            else { return nil }
            out.append(AddressFakeItem(t: t, s: s, lat: lat, lng: lng, country: e["country"] as? String))
        }
        return out
    }

    // MARK: - helpers

    private static func isVersion(_ v: Any?) -> Bool { MapWire.number(v) == Double(version) }

    /// A whole number that fits an Int64 exactly.
    private static func integer(_ v: Any?) -> Int64? {
        guard let d = MapWire.number(v), d.isFinite, d == d.rounded(), abs(d) < 9_007_199_254_740_992 else { return nil }
        return Int64(d)
    }
}
