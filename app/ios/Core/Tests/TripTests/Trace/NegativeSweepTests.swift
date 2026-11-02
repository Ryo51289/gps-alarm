import Testing
@testable import Trip

/// TR36 and TR37-neg (T12 §8.7): the harness must catch the risks the T10.1/T10.2 fixes remove.
@Suite("NegativeSweepTests")
struct NegativeSweepTests {
    static func loadCase(_ traceId: String, _ caseId: String) throws -> (LoadedTrace, CaseSpec) {
        guard let t = LoadedTrace.named(traceId),
              let i = t.file.rawCases.firstIndex(where: { $0["id"]?.stringValue == caseId }) else {
            throw ModelError(description: "missing \(traceId)/\(caseId)")
        }
        return (t, try ExpectModel.parseCase(t.file.rawCases[i], index: i))
    }

    @Test("TR36 stopgap 36 phases with lostSpeedGuardUpdates = 0: at least one phase misses the TR30 window")
    func tr36() async throws {
        let (trace, spec) = try Self.loadCase("train_hn_dh_stopgap", "distance_1000")
        let modes = CaseCatalog.modes(spec, interval: trace.file.intervalS).filter { $0.hasPrefix("policy-j") }
        #expect(modes.count == 36)
        let filter = EventFilter(event: "alarm", reason: "GPS_LOST", ringNow: true, cause: nil)
        let results: [(String, Int?)] = await withTaskGroup(of: (String, Int?).self) { g in
            for m in modes {
                g.addTask {
                    var r = Runner(trace: trace, spec: spec, mode: m,
                                   options: RunOptions(paramOverrides: [("lostSpeedGuardUpdates", .number("0"))]))
                    r.runAll()
                    return (m, Checks.flat(r).first { Checks.matches($0.e, filter) }?.t)
                }
            }
            var out: [(String, Int?)] = []
            for await x in g { out.append(x) }
            return out.sorted { $0.0 < $1.0 }
        }
        let failed = results.filter { r in guard let t = r.1 else { return true }; return !(t >= 28_815 && t <= 35_045) }
        var md = "## TR36 (lostSpeedGuardUpdates = 0): \(failed.count)/36 phases miss [28815, 35045]\n\n| run | first GPS_LOST alarm |\n|---|---|\n"
        for r in failed { md += "| \(r.0) | \(r.1.map(String.init) ?? "none") |\n" }
        Report.shared.writePart(dir: "trace", name: "tr36", markdown: md + "\n", json: nil)
        #expect(failed.count >= 1, "TR36: no phase failed — báo designer")
    }

    @Test("TR37-neg train_hn_dh/distance_1000_killsweep with T10 parameters: some k rings after arrival")
    func tr37neg() async throws {
        let (trace, spec) = try Self.loadCase("train_hn_dh", "distance_1000_killsweep")
        let overrides: [(String, JsonValue)] = [("fallbackEarlyFrac", .number("0.1")), ("fallbackEarlyMaxS", .number("1800")),
                                                ("fallbackHintSpeedFactor", .number("0"))]
        var late = 0, total = 0
        for m in ["all", "policy"] {
            var r = Runner(trace: trace, spec: spec, mode: m, options: RunOptions(paramOverrides: overrides))
            r.runAll()
            #expect(r.configErrors.isEmpty)
            let (_, stats) = KillSweep.evaluate(r, spec.killSweep!)
            let pts = stats?.points ?? []
            total += pts.count
            late += pts.filter { $0.lateS > 0 }.count
        }
        Report.shared.writePart(dir: "trace", name: "tr37neg", markdown: "## TR37-neg: \(late)/\(total) k late (T10 params)\n\n", json: nil)
        #expect(late >= 1, "TR37-neg: no late k — báo designer")
    }
}
