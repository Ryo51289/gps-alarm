import Foundation

/// Report files under `<reportDir>` (T13 §8.4). Parallel tests write parts; summaries are rebuilt from all parts
/// (sorted by name) after every write, so the final content is deterministic.
final class Report: @unchecked Sendable {
    static let shared = Report()
    private let lock = NSLock()

    func writePart(dir: String, name: String, markdown: String, json: String?) {
        lock.lock()
        defer { lock.unlock() }
        let base = FixturePaths.reportDir + "/" + dir
        try? FixturePaths.write(base + "/parts/" + name + ".md", markdown)
        if let json { try? FixturePaths.write(base + "/parts/" + name + ".json", json) }
        rebuild(base: base, title: dir)
    }

    private func rebuild(base: String, title: String) {
        let parts = (try? FileManager.default.contentsOfDirectory(atPath: base + "/parts")) ?? []
        let md = parts.filter { $0.hasSuffix(".md") }.sorted()
        var summary = "# \(title) (NapStopCore, Swift)\n\n"
        for p in md { summary += (try? FixturePaths.read(base + "/parts/" + p)) ?? "" }
        try? FixturePaths.write(base + "/summary.md", summary)
        let js = parts.filter { $0.hasSuffix(".json") }.sorted()
        if !js.isEmpty {
            let body = js.compactMap { try? FixturePaths.read(base + "/parts/" + $0) }.joined(separator: ",\n")
            try? FixturePaths.write(base + "/" + title + ".json", "[\n" + body + "\n]\n")
        }
    }

    func write(_ relPath: String, _ content: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FixturePaths.write(FixturePaths.reportDir + "/" + relPath, content)
    }
}
