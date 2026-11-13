import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T23.8 CU15, CU27: shared cases in fixtures/commute (schema: fixtures/commute/README.md).
@Suite("T23.8 commute fixtures")
struct CommuteFixtureTests {
    @Test("CU15/CU16 validation_cases.json: first error and D12 separation (§5.6a) match every case")
    func validationCases() throws {
        let root = try CS.load("validation_cases.json")
        #expect(CS.int(root["version"]) == 1)
        let base = try #require(root["base"] as? [String: Any])
        let cases = try #require(root["cases"] as? [[String: Any]])
        #expect(cases.count >= 40)
        var names = Set<String>()
        for c in cases {
            let name = CS.str(c["name"]) ?? "?"
            #expect(names.insert(name).inserted, "duplicate case name \(name)")
            let route = CS.routeJ(CS.deepMerge(base, c["override"] as? [String: Any] ?? [:]))
            let got = CommuteRouteValidator.validate(route)
            #expect(got == CS.str(c["expected"]), "\(name)")
            // Mandatory in every case (README): Dart uses it as an input, Swift/Kotlin must compute the same Int.
            let need = CS.int(c["requiredSeparationM"])
            #expect(need != nil, "\(name): requiredSeparationM missing or not a whole number")
            #expect(CommuteRouteValidator.requiredSeparationM(route) == need, "\(name)")
            if got == "route: tooClose" || got == nil {
                let sep = CommuteRouteValidator.separation(route)
                #expect(sep.requiredM == need, "\(name)")
                #expect((sep.actualM < sep.requiredM) == (got != nil), "\(name): separation agrees with validate")
                // README: no case within 50 m of the threshold (platform sin/cos may differ by a few ULP).
                let d = CommuteRouteValidator.distanceM(route.aLat, route.aLng, route.bLat, route.bLng)
                #expect(d.isFinite && abs(d - Double(sep.requiredM)) >= 50, "\(name): A–B too close to the threshold")
            }
        }
    }

    @Test("CU27 trigger_cases.json: every step's decision and state match (≥ 30 cases, CU01–CU14, CU29, CU30 covered)")
    func triggerCases() throws {
        let root = try CS.load("trigger_cases.json")
        #expect(CS.int(root["version"]) == 1)
        let defaults = try #require(root["defaults"] as? [String: Any])
        let dRoute = try #require(defaults["route"] as? [String: Any])
        let dState = try #require(defaults["state"] as? [String: Any])
        let dCtx = try #require(defaults["ctx"] as? [String: Any])
        let cases = try #require(root["cases"] as? [[String: Any]])
        #expect(cases.count >= 30)
        var ids = Set<String>()
        for c in cases {
            let name = CS.str(c["name"]) ?? "?"
            for id in c["ids"] as? [String] ?? [] { ids.insert(id) }
            let route = CS.routeJ(CS.deepMerge(dRoute, c["route"] as? [String: Any] ?? [:]))
            var state = CS.stateJ(CS.shallowMerge(dState, c["state"] as? [String: Any]))
            let steps = try #require(c["steps"] as? [[String: Any]])
            for (i, s) in steps.enumerated() {
                let label = "\(name) step \(i + 1)"
                let e = try #require(s["event"] as? [String: Any])
                let at = CS.ms(try #require(CS.str(e["at"])))
                let event = RegionEvent(identifier: try #require(CS.str(e["id"])),
                                        state: try #require(RegionState(rawValue: CS.str(e["state"]) ?? "")),
                                        dateWallMs: at, authorizationDenied: CS.bool(e["authorizationDenied"]))
                let x = CS.shallowMerge(dCtx, s["ctx"] as? [String: Any])
                let access = LocationAccess(whenInUseOrAlways: true, fullAccuracy: CS.bool(x["fullAccuracy"]),
                                            servicesEnabled: CS.bool(x["servicesEnabled"]), always: CS.bool(x["always"]))
                let ctx = TriggerContext(nowWallMs: CS.str(x["processedAt"]).map(CS.ms) ?? at,
                                         utcOffsetS: try #require(CS.int(x["utcOffsetS"])), access: access,
                                         tripActive: CS.bool(x["tripActive"]), osSupported: CS.bool(x["osSupported"]))
                let (decision, next) = CommuteTriggerEvaluator.evaluate(event, route: route, state: state, ctx: ctx)
                state = next
                let exp = try #require(s["expect"] as? [String: Any])
                let expected: TriggerDecision
                if let dir = CS.str(exp["start"]) {
                    expected = .start(try #require(CommuteDirection(rawValue: dir)), dateKey: try #require(CS.str(exp["dateKey"])))
                } else {
                    expected = .skip(try #require(SkipReason(rawValue: CS.str(exp["skip"]) ?? ""), "\(label): skip name"))
                }
                #expect(decision == expected, "\(label)")
                if case let .start(dir, key) = decision, !CS.bool(s["rejected"]) {
                    state = state.markingFired(dir, dateKey: key)
                }
                if let ls = s["expectLastState"] as? [String: Any] {
                    for (k, v) in ls {
                        let p = try #require(CommutePoint(rawValue: k))
                        #expect((state.lastState[p] ?? .unknown).rawValue == CS.str(v), "\(label): lastState \(k)")
                    }
                }
                if let fk = s["expectFiredKeys"] as? [Any] {
                    #expect(state.firedKeys == fk.compactMap { $0 as? String }, "\(label): firedKeys")
                }
            }
        }
        for n in Array(1...14) + [29, 30] {
            let id = n < 10 ? "CU0\(n)" : "CU\(n)"
            #expect(ids.contains(id), "trigger_cases.json misses \(id)")
        }
    }
}
