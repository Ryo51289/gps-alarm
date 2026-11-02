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

    @Test("IdCoverage: U01–U98 and S01–S16 have a test whose name starts with the ID")
    func unitIds() throws {
        let src = try Self.testSources()
        var missing: [String] = []
        for i in 1...98 {
            let id = String(format: "U%02d", i)
            if !src.contains("@Test(\"\(id)") { missing.append(id) }
        }
        for i in 1...16 {
            let id = String(format: "S%02d", i)
            if !src.contains("@Test(\"\(id)") { missing.append(id) }
        }
        #expect(missing.isEmpty, "missing: \(missing)")
    }

    @Test("IdCoverage: TR01–TR35, TR37, TR38 in fixture testIds; TR36 in NegativeSweepTests")
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
    }
}
