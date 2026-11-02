import Foundation

/// Locations of fixtures, P05 data and the report directory (T13 §8.1, §8.4).
enum FixturePaths {
    /// `fixtures/traces` (NAPSTOP_FIXTURES_DIR or found from #filePath upwards).
    static let tracesDir: String = {
        if let env = ProcessInfo.processInfo.environment["NAPSTOP_FIXTURES_DIR"], !env.isEmpty { return env }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("fixtures/traces/README.md").path
            if FileManager.default.fileExists(atPath: candidate) { return dir.appendingPathComponent("fixtures/traces").path }
            dir = dir.deletingLastPathComponent()
        }
        return "fixtures/traces"
    }()

    static var p05Dir: String { URL(fileURLWithPath: tracesDir).deletingLastPathComponent().appendingPathComponent("p05").path }

    /// Root of the package (for source scans).
    static let packageDir: String = {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path
    }()

    static var sourcesDir: String { packageDir + "/Sources/Trip" }
    static var testsDir: String { packageDir + "/Tests/TripTests" }

    static let reportDir: String = {
        if let env = ProcessInfo.processInfo.environment["NAPSTOP_REPORT_DIR"], !env.isEmpty { return env }
        return packageDir + "/.build/napstop-report"
    }()

    static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    static func write(_ path: String, _ content: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func expectFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: tracesDir).filter { $0.hasSuffix(".expect.json") }.sorted()
    }
}
