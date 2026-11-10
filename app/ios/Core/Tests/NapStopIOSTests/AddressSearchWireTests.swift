import Foundation
import Testing
@testable import NapStopIOS

/// T23.5 AS-S01..AS-S05: the Swift end of the address search channel (docs/specs/T23.5.md §3, §5.1), same cases as
/// the Dart side (`fixtures/address_search_wire/cases.json`).
@Suite("AddressSearchWire")
struct AddressSearchWireTests {
    typealias JSONValue = MapWireTests.JSONValue

    static func fixture() throws -> JSONValue {
        let data = try Data(
            contentsOf: URL(fileURLWithPath: MapWireTests.repoRoot + "/fixtures/address_search_wire/cases.json"))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func name(_ c: JSONValue) -> String {
        if case .string(let s)? = c["name"] { return s }
        return "?"
    }

    @Test("AS-S01 complete requests of cases.json")
    func completeRequests() throws {
        let root = try Self.fixture()
        for c in root["completeRequest"]?.list ?? [] {
            let input = c["input"]?.codecValue
            let parsed = AddressSearchWire.completeRequest(input)
            if c["valid"]?.boolValue == true {
                let r = try #require(parsed, Comment(rawValue: Self.name(c)))
                #expect(r.gen == Int64(c["input"]?["gen"]?.double ?? -1))
                #expect(r.region == MapBoundsWire(s: 8.3, w: 102.0, n: 23.6, e: 109.7))
            } else {
                #expect(parsed == nil, Comment(rawValue: Self.name(c)))
            }
        }
    }

    @Test("AS-S01 resolve requests of cases.json")
    func resolveRequests() throws {
        let root = try Self.fixture()
        for c in root["resolveRequest"]?.list ?? [] {
            let parsed = AddressSearchWire.resolveRequest(c["input"]?.codecValue)
            if c["valid"]?.boolValue == true {
                let r = try #require(parsed, Comment(rawValue: Self.name(c)))
                #expect(r.gen == 7 && r.index == 2)
            } else {
                #expect(parsed == nil, Comment(rawValue: Self.name(c)))
            }
        }
    }

    @Test("AS-S01 query of 64 runes is accepted, 65 is not")
    func queryLength() {
        func request(_ q: String) -> [String: Any] {
            ["v": 1, "gen": 1, "query": q, "region": ["s": 8.3, "w": 102.0, "n": 23.6, "e": 109.7]]
        }
        #expect(AddressSearchWire.completeRequest(request(String(repeating: "a", count: 64))) != nil)
        #expect(AddressSearchWire.completeRequest(request(String(repeating: "a", count: 65))) == nil)
        #expect(AddressSearchWire.completeRequest(request(String(repeating: "\u{1F600}", count: 65))) == nil)
        #expect(AddressSearchWire.completeRequest(request("")) != nil)
    }

    @Test("AS-S02 completeReply cuts at 15 and keeps order and keys")
    func completeReplyCut() throws {
        let items = (0..<20).map { (title: "T\($0)", subtitle: "S\($0)") }
        let reply = AddressSearchWire.completeReply(gen: 9, status: "ok", items: items)
        #expect(reply["gen"] as? Int64 == 9)
        #expect(reply["status"] as? String == "ok")
        let list = try #require(reply["items"] as? [[String: String]])
        #expect(list.count == 15)
        #expect(list.first == ["t": "T0", "s": "S0"])
        #expect(list.last == ["t": "T14", "s": "S14"])
        let failed = AddressSearchWire.completeReply(gen: 9, status: "throttled", items: items)
        #expect(failed["items"] == nil)
    }

    @Test("AS-S03 errorStatus table of cases.json")
    func errorStatusTable() throws {
        let root = try Self.fixture()
        let rows = root["errorStatus"]?.list ?? []
        #expect(rows.count == 5)
        for row in rows {
            guard case .string(let domain)? = row["domain"], case .string(let status)? = row["status"],
                let code = row["code"]?.double
            else {
                Issue.record("bad row")
                continue
            }
            var underlying: String?
            if case .string(let u)? = row["underlying"] { underlying = u }
            #expect(
                AddressSearchWire.errorStatus(domain: domain, code: Int(code), underlyingDomain: underlying) == status)
        }
    }

    @Test("AS-S04 resolveOk keeps the numbers; no country is NSNull")
    func resolveOk() {
        let r = AddressSearchWire.resolveOk(lat: 21.03, lng: 105.85, country: nil)
        #expect(r["status"] as? String == "ok")
        #expect(r["lat"] as? Double == 21.03)
        #expect(r["lng"] as? Double == 105.85)
        #expect(r["country"] is NSNull)
        #expect(AddressSearchWire.resolveOk(lat: 1, lng: 2, country: "VN")["country"] as? String == "VN")
        #expect(AddressSearchWire.status("stale")["status"] as? String == "stale")
    }

    @Test("AS-S05 description prints neither the typed text nor coordinates")
    func descriptions() throws {
        let request = try #require(
            AddressSearchWire.completeRequest([
                "v": 1, "gen": 1, "query": "secret street 12",
                "region": ["s": 8.3, "w": 102.0, "n": 23.6, "e": 109.7],
            ]))
        #expect(!"\(request)".contains("secret"))
        #expect(!"\(request.region)".contains("102"))
        let fake = AddressFakeItem(t: "secret", s: "x", lat: 21.0312, lng: 105.8512, country: nil)
        #expect(!"\(fake)".contains("secret"))
        #expect(!"\(fake)".contains("21.03"))
    }

    @Test("diagFake items parse; invalid ones give nil")
    func fakeItems() {
        let ok: [String: Any] = [
            "items": [["t": "Bến xe", "s": "Hà Nội", "lat": 21.0, "lng": 105.8, "country": "VN"]]
        ]
        #expect(AddressSearchWire.fakeItems(ok)?.count == 1)
        #expect(AddressSearchWire.fakeItems(nil) == nil)
        #expect(AddressSearchWire.fakeItems(["items": [["t": "x", "s": "y", "lat": 99.0, "lng": 0.0]]]) == nil)
    }
}
