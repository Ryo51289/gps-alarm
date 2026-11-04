import Foundation
import Testing
@testable import Trip

/// One fixture case (argument of the parameterised trace test).
struct CaseRef: Sendable, CustomTestStringConvertible {
    let traceId: String
    let caseIndex: Int
    let caseId: String
    let testIds: [String]
    var testDescription: String { "\(testIds.joined(separator: ",")) \(traceId)/\(caseId)" }
}

enum CaseCatalog {
    /// Every case of every `*.expect.json`, sorted by file name then `cases[]` order (T13 §8.1).
    static let refs: [CaseRef] = {
        var out: [CaseRef] = []
        for t in LoadedTrace.all {
            for (i, c) in t.file.rawCases.enumerated() {
                let ids = (c["testIds"]?.arrayValue ?? []).compactMap(\.stringValue)
                out.append(CaseRef(traceId: t.file.traceId, caseIndex: i, caseId: t.file.caseId(i), testIds: ids))
            }
        }
        return out
    }()

    /// Sampling runs of a case (T12 §9.1).
    static func modes(_ spec: CaseSpec, interval: Int) -> [String] {
        let declared = spec.samplingModes ?? ["all", "policy"]
        var out: [String] = []
        for m in declared {
            if m == "policy" && spec.policyPhaseSweep {
                let sparse = EngineParamsFactory.parseOverrides(MiniJson.write(.object(spec.config.params))).params
                    .samplingSparseIntervalS
                let k = max(1, sparse / interval)
                for j in 0..<k { out.append(String(format: "policy-j%02d", j)) }
            } else {
                out.append(m)
            }
        }
        return out
    }

    static func load(_ ref: CaseRef) throws -> (LoadedTrace, CaseSpec) {
        guard let trace = LoadedTrace.named(ref.traceId) else { throw ModelError(description: "trace \(ref.traceId) not loaded") }
        return (trace, try ExpectModel.parseCase(trace.file.rawCases[ref.caseIndex], index: ref.caseIndex))
    }

    static var traceCount: Int { (try? FixturePaths.expectFiles().count) ?? 0 }
}

struct ModeResult: Sendable {
    let mode: String
    let failures: [String]
    let kill: KillRunStats?
    let firstGpsLostAlarmT: Int?
}

/// Runs one sampling mode of a case with every per-run check, plus I8/I9/P06 at j = 0.
func runModeWithChecks(_ trace: LoadedTrace, _ spec: CaseSpec, _ mode: String) -> ModeResult {
    let isJ0 = mode == "all" || mode == "policy" || mode == "policy-j00"
    var failures: [String] = []
    var main = Runner(trace: trace, spec: spec, mode: mode)
    if isJ0 && main.configErrors.isEmpty {
        let (m, caps) = RestoreEquivalence.runWithCaptures(main)
        main = m
        if main.configErrors.isEmpty {
            for (c, copy) in caps { failures += RestoreEquivalence.check(original: main, checkpoint: c, captured: copy) }
            let transcript = main.transcript()
            var again = Runner(trace: trace, spec: spec, mode: mode, options: RunOptions(probes: false))
            again.runAll()
            if Sha256.hex(again.transcript()) != Sha256.hex(transcript) { failures.append("[\(main.run)] I9: transcript differs on rerun") }
            var shifted = Runner(trace: trace, spec: spec, mode: mode, options: RunOptions(timeShiftMs: 86_400_000, probes: false))
            shifted.runAll()
            if shifted.transcript() != transcript { failures.append("[\(main.run)] P06: transcript differs with +1 day") }
        }
    } else {
        main.runAll()
    }
    failures += Checks.run(main)
    var kill: KillRunStats? = nil
    if let ks = spec.killSweep, main.configErrors.isEmpty {
        let (f, st) = KillSweep.evaluate(main, ks)
        failures += f
        kill = st
    }
    let gl = Checks.flat(main).first { Checks.matches($0.e, EventFilter(event: "alarm", reason: "GPS_LOST", ringNow: true, cause: nil)) }
    return ModeResult(mode: mode, failures: failures, kill: kill, firstGpsLostAlarmT: gl?.t)
}

/// Runs all modes of a case in parallel; results sorted by mode name (deterministic).
func runCase(_ trace: LoadedTrace, _ spec: CaseSpec) async -> [ModeResult] {
    let modes = CaseCatalog.modes(spec, interval: trace.file.intervalS)
    let results = await withTaskGroup(of: ModeResult.self) { group in
        for m in modes { group.addTask { runModeWithChecks(trace, spec, m) } }
        var out: [ModeResult] = []
        for await r in group { out.append(r) }
        return out
    }
    return results.sorted { $0.mode < $1.mode }
}

@Suite("TraceSuite")
struct TraceSuite {
    @Test("Fixture directory loads (17 traces, 64 cases, 303 runs after T11.3)")
    func catalogLoads() throws {
        #expect(LoadedTrace.all.count == CaseCatalog.traceCount)
        #expect(CaseCatalog.traceCount == 17)
        #expect(CaseCatalog.refs.count == 64)
        var runs = 0
        for ref in CaseCatalog.refs {
            let (t, spec) = try CaseCatalog.load(ref)
            runs += CaseCatalog.modes(spec, interval: t.file.intervalS).count
        }
        #expect(runs == P05.expectedRuns)
    }

    @Test("TR01–TR35, TR37, TR38 · P01 P02 P03 P04 P06 P07 · fixture case", arguments: CaseCatalog.refs)
    func traceCase(_ ref: CaseRef) async throws {
        let (trace, spec) = try CaseCatalog.load(ref)
        let results = await runCase(trace, spec)
        var failures = results.flatMap(\.failures)
        if let ks = spec.killSweep {
            let all = results.filter { $0.mode == "all" }.compactMap(\.kill)
            let pol = results.filter { $0.mode.hasPrefix("policy") }.compactMap(\.kill)
            let name = "\(trace.file.traceId)/\(spec.id)"
            var reference: (Double, Int64)? = nil
            if name == "coach_gb_phuly_overshoot/distance_1000_killsweep" { reference = (34.6, 744) }
            if name == "train_longstop/distance_1000_killsweep" { reference = (13.6, 340) }
            let (md, json) = KillSweep.summarize(caseName: name, statsOnly: ks.statsOnly,
                                                 groups: [.init(label: "all", runs: all), .init(label: "policy (pooled)", runs: pol)],
                                                 nearS: EngineParams.defaults.fallbackNearS, reference: reference)
            Report.shared.writePart(dir: "killsweep", name: name.replacingOccurrences(of: "/", with: "__"), markdown: md, json: json)
        }
        if trace.file.traceId == "train_hn_dh_stopgap" && spec.id == "distance_1000" {
            var md = "## TR30 train_hn_dh_stopgap/distance_1000: first alarm GPS_LOST ringNow=true per run\n\n| run | t |\n|---|---|\n"
            for r in results { md += "| \(r.mode) | \(r.firstGpsLostAlarmT.map(String.init) ?? "none") |\n" }
            Report.shared.writePart(dir: "trace", name: "tr30", markdown: md + "\n", json: nil)
            #expect(results.count == 37)
        }
        if failures.count > 40 { failures = Array(failures.prefix(40)) + ["… \(failures.count - 40) more"] }
        for f in failures { Issue.record(Comment(rawValue: f)) }
    }
}
