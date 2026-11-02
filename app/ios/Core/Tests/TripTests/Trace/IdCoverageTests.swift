import Foundation
import Testing
@testable import Trip

/// Every T10 ID has a test (T12 IdCoverageTest + T13 S-IDs).
@Suite("IdCoverageTests")
struct IdCoverageTests {
    static func testSources() throws -> String {
        let fm = FileManager.default
        var all = ""
        let root = FixturePaths.testsDir
        guard let e = fm.enumerator(atPath: root) else { return "" }
        for case let p as String in e where p.hasSuffix(".swift") { all += try FixturePaths.read(root + "/" + p) }
        return all
    }

    /// IDs declared by test names: every `@Test("` followed by `U`/`S` and a maximal run of digits (word boundary, like Kotlin
    /// `U\d{2,3}\b`), so `@Test("U100 …` declares U100, not U10.
    static func declaredIds(_ src: String) -> Set<String> {
        let b = Array(src.utf8)
        let marker = Array("@Test(\"".utf8)
        var out: Set<String> = []
        var i = 0
        while i + marker.count < b.count {
            if b[i] == marker[0] && Array(b[i..<(i + marker.count)]) == marker {
                var j = i + marker.count
                let letter = b[j]
                if letter == UInt8(ascii: "U") || letter == UInt8(ascii: "S") {
                    j += 1
                    let digitsStart = j
                    while j < b.count && b[j] >= UInt8(ascii: "0") && b[j] <= UInt8(ascii: "9") { j += 1 }
                    if j > digitsStart { out.insert(String(decoding: b[(digitsStart - 1)..<j], as: UTF8.self)) }
                }
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    @Test("IdCoverage self-check: an ID is matched with a word boundary (U100–U105 do not declare U10)")
    func declaredIdsWordBoundary() {
        let ids = Self.declaredIds("@Test(\"U100 x\") @Test(\"U105 a y\") @Test(\"S01: z\") @Test(\"U70 (i) w\") @Test(\"TR36 v\")")
        #expect(ids == ["U100", "U105", "S01", "U70"])
        #expect(!ids.contains("U10"))
        #expect(Self.declaredIds("@Test(\"U10 EMA\")") == ["U10"])
    }

    @Test("IdCoverage: U01–U105 and S01–S16 have a test whose name starts with the ID")
    func unitIds() throws {
        let declared = Self.declaredIds(try Self.testSources())
        var missing: [String] = []
        for i in 1...105 {
            let id = String(format: "U%02d", i)
            if !declared.contains(id) { missing.append(id) }
        }
        for i in 1...16 {
            let id = String(format: "S%02d", i)
            if !declared.contains(id) { missing.append(id) }
        }
        #expect(missing.isEmpty, "missing: \(missing)")
    }

    @Test("IdCoverage: TR01–TR35, TR37, TR38 in fixture testIds; TR36 in NegativeSweepTests, TR39 in DozeModelTests")
    func traceIds() throws {
        let ids = Set(CaseCatalog.refs.flatMap(\.testIds))
        var missing: [String] = []
        for i in 1...38 where i != 36 {
            let id = String(format: "TR%02d", i)
            if !ids.contains(id) { missing.append(id) }
        }
        #expect(missing.isEmpty, "missing: \(missing)")
        let neg = try FixturePaths.read(FixturePaths.testsDir + "/Trace/NegativeSweepTests.swift")
        #expect(neg.contains("@Test(\"TR36"))
        let doze = try FixturePaths.read(FixturePaths.testsDir + "/Trace/DozeModelTests.swift")
        #expect(doze.contains("@Test(\"TR39"))
    }
}
