import Foundation
import Testing
@testable import Trip

/// P05 (T12 §9.4, T13 §9.3): Swift transcripts must match the Kotlin manifest (`fixtures/p05/manifest.json`).
enum P05 {
    struct Entry: Sendable, Equatable { let run: String; let lines: Int; let sha256: String }

    /// Transcript of every main run (291), sorted by run name.
    static func allTranscripts(diag: Bool) async throws -> [(run: String, text: String, diag: String?)] {
        var jobs: [(LoadedTrace, CaseSpec, String)] = []
        for ref in CaseCatalog.refs {
            let (t, spec) = try CaseCatalog.load(ref)
            for m in CaseCatalog.modes(spec, interval: t.file.intervalS) { jobs.append((t, spec, m)) }
        }
        let out = await withTaskGroup(of: (String, String, String?).self) { g in
            for (t, spec, m) in jobs { g.addTask { transcript(t, spec, m, diag: diag) } }
            var res: [(String, String, String?)] = []
            for await x in g { res.append(x) }
            return res
        }
        return out.sorted { $0.0 < $1.0 }.map { (run: $0.0, text: $0.1, diag: $0.2) }
    }

    static func transcript(_ t: LoadedTrace, _ spec: CaseSpec, _ mode: String, diag: Bool) -> (String, String, String?) {
        var r = Runner(trace: t, spec: spec, mode: mode, options: RunOptions(keepStates: diag))
        r.runAll()
        return (r.run, r.transcript(), diag ? Transcript.renderDiag(records: r.records, states: r.states) : nil)
    }

    static func fileName(_ run: String) -> String { run.replacingOccurrences(of: "/", with: "__") + ".jsonl" }

    static func parseManifest(_ text: String) throws -> [Entry] {
        let root = try MiniJson.parse(text)
        guard root["p05"]?.asLongExact() == 1, let runs = root["runs"]?.arrayValue else {
            throw ModelError(description: "manifest: bad format")
        }
        return try runs.map { r in
            guard let run = r["run"]?.stringValue, let lines = r["lines"]?.asIntExact(), let sha = r["sha256"]?.stringValue else {
                throw ModelError(description: "manifest: bad run entry")
            }
            return Entry(run: run, lines: lines, sha256: sha)
        }
    }

    static func dump(_ items: [(run: String, text: String, diag: String?)]) {
        guard let dir = ProcessInfo.processInfo.environment["NAPSTOP_P05_DUMP"], !dir.isEmpty else { return }
        precondition(!dir.contains("fixtures/p05"), "never write into fixtures/p05")
        for x in items {
            try? FixturePaths.write(dir + "/" + fileName(x.run), x.text)
            if let d = x.diag { try? FixturePaths.write(dir + "/" + fileName(x.run).replacingOccurrences(of: ".jsonl", with: ".diag.jsonl"), d) }
        }
    }
}

@Suite("P05ManifestTests")
struct P05ManifestTests {
    @Test("P05 295 transcripts match fixtures/p05/manifest.json (run set, lines, sha256) + S15 samples byte-exact")
    func manifest() async throws {
        let manifestPath = FixturePaths.p05Dir + "/manifest.json"
        let diag = ProcessInfo.processInfo.environment["NAPSTOP_P05_DIAG"] == "1"
        let wantDump = ProcessInfo.processInfo.environment["NAPSTOP_P05_DUMP"].map { !$0.isEmpty } ?? false
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            if wantDump { P05.dump(try await P05.allTranscripts(diag: diag)) }
            Issue.record("P05: chờ T12 commit manifest (\(manifestPath) không có)")
            return
        }
        let expected = try P05.parseManifest(try FixturePaths.read(manifestPath))
        let items = try await P05.allTranscripts(diag: diag)
        P05.dump(items)
        let actual = items.map { P05.Entry(run: $0.run, lines: Transcript.lineCount($0.text), sha256: Sha256.hex($0.text)) }
        #expect(actual.count == 295)
        let dupes = Dictionary(grouping: expected.map(\.run), by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "manifest has duplicate runs: \(dupes)")
        let expMap = Dictionary(expected.map { ($0.run, $0) }, uniquingKeysWith: { first, _ in first })
        let actMap = Dictionary(actual.map { ($0.run, $0) }, uniquingKeysWith: { first, _ in first })
        let missing = expected.map(\.run).filter { actMap[$0] == nil }
        let extra = actual.map(\.run).filter { expMap[$0] == nil }
        #expect(missing.isEmpty, "runs missing in Swift: \(missing)")
        #expect(extra.isEmpty, "runs not in manifest: \(extra)")
        var mismatches: [String] = []
        for item in items {
            guard let e = expMap[item.run], let a = actMap[item.run], e != a else { continue }
            mismatches.append("\(item.run): lines \(e.lines) expected, \(a.lines) actual")
            Report.shared.write("p05-mismatch/" + P05.fileName(item.run), item.text)
        }
        #expect(mismatches.isEmpty, "P05 mismatches (\(mismatches.count)): \(mismatches.prefix(20))")
        // S15: the three samples, byte for byte.
        let sampleDir = FixturePaths.p05Dir + "/samples"
        let samples = (try? FileManager.default.contentsOfDirectory(atPath: sampleDir).filter { $0.hasSuffix(".jsonl") }) ?? []
        #expect(samples.count == 3, "expected 3 samples in fixtures/p05/samples")
        for s in samples {
            let run = String(s.dropLast(".jsonl".count)).replacingOccurrences(of: "__", with: "/")
            guard let mine = items.first(where: { $0.run == run }) else { Issue.record("sample \(s): no such run"); continue }
            #expect(try FixturePaths.read(sampleDir + "/" + s) == mine.text, "S15 sample \(s) differs")
        }
    }

    @Test("S15 transcript format: header, KILL marker, relative times, v only on change, ev omitted when empty")
    func s15Format() throws {
        let (t, spec) = try NegativeSweepTests.loadCase("coach_gb_phuly_overshoot", "distance_1000_fallback_silenced")
        let (_, text, _) = P05.transcript(t, spec, "all", diag: false)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "{\"p05\":1,\"run\":\"coach_gb_phuly_overshoot/distance_1000_fallback_silenced/all\"}")
        #expect(text.hasSuffix("\n"))
        #expect(lines[1].hasPrefix("{\"t\":0,\"in\":[\"START\"],\"ev\":[{\"e\":\"samplingPolicyChanged\",\"atMs\":0,"))
        #expect(lines.contains("{\"t\":1825,\"in\":[\"KILL\"]}"))
        #expect(text.contains("[\"RESTORE\","))
        #expect(!text.contains(" "))
        #expect(text.utf8.allSatisfy { $0 < 0x80 })
        #expect(!text.contains("\"ev\":[]"))
        // No Double in the transcript: no '.' outside strings and no exponent.
        #expect(!text.contains("."))
    }

    @Test("S16 transcripts are deterministic when generated twice in parallel")
    func s16() async throws {
        let picks = [("coach_dn_langco_tunnel", "distance_1000_gps_lost", "all"),
                     ("coach_dn_langco_tunnel", "distance_1000_gps_lost", "policy"),
                     ("coach_gb_phuly_overshoot", "distance_1000_fallback_silenced", "all")]
        var jobs: [(LoadedTrace, CaseSpec, String)] = []
        for p in picks {
            let (t, s) = try NegativeSweepTests.loadCase(p.0, p.1)
            jobs.append((t, s, p.2))
            jobs.append((t, s, p.2))
        }
        let out = await withTaskGroup(of: (String, String).self) { g in
            for (t, s, m) in jobs { g.addTask { let x = P05.transcript(t, s, m, diag: false); return (x.0, Sha256.hex(x.1)) } }
            var r: [(String, String)] = []
            for await x in g { r.append(x) }
            return r
        }
        let grouped = Dictionary(grouping: out, by: \.0)
        #expect(grouped.count == 3)
        for (_, v) in grouped { #expect(Set(v.map(\.1)).count == 1) }
    }
}
