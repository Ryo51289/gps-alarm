import Foundation
import Testing

/// T17.1 PU07 (docs/specs/T17.1.md §4, §5): the two usage strings are the same in the ARB files, the InfoPlist.strings of
/// each language and Info.plist (= Vietnamese, the source); the app privacy manifest declares exactly the reasons of §5.
@Suite("T17.1 Plist strings")
struct PlistStringsTests {
    static let runnerDir = "\(RTPaths.repoRoot)/app/ios/Runner"
    /// ARB key → Info.plist key.
    static let keys: [(arb: String, plist: String)] = [
        ("iosLocationUsage", "NSLocationWhenInUseUsageDescription"),
        ("iosAlarmKitUsage", "NSAlarmKitUsageDescription"),
    ]

    static func arb(_ lang: String) throws -> [String: Any] {
        let d = try Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.l10nDir)/app_\(lang).arb"))
        return try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
    }

    static func plist(_ path: String) throws -> [String: Any] {
        let d = try Data(contentsOf: URL(fileURLWithPath: path))
        return try PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] ?? [:]
    }

    static func bool(_ v: Any?) -> Bool? { (v as? Bool) ?? (v as? NSNumber)?.boolValue }

    @Test("PU07 ARB = InfoPlist.strings (vi, en); Info.plist = vi")
    func usageStrings() throws {
        let info = try Self.plist("\(Self.runnerDir)/Info.plist")
        for lang in ["vi", "en"] {
            let arb = try Self.arb(lang)
            let text = try String(contentsOfFile: "\(Self.runnerDir)/\(lang).lproj/InfoPlist.strings", encoding: .utf8)
            let strings = try StringsFile.parse(text)
            #expect(Set(strings.keys) == Set(Self.keys.map(\.plist)), "\(lang): only the two usage strings")
            for k in Self.keys {
                let a = arb[k.arb] as? String
                #expect(a != nil && !(a ?? "").isEmpty, "\(lang) ARB \(k.arb)")
                #expect(strings[k.plist] == a, "\(lang) \(k.plist)")
                if lang == "vi" {
                    #expect(info[k.plist] as? String == a, "Info.plist \(k.plist) must be the Vietnamese source")
                }
            }
        }
        let viArb = try Self.arb("vi")
        for k in Self.keys {
            let meta = viArb["@\(k.arb)"] as? [String: Any]
            #expect((meta?["description"] as? String)?.contains("InfoPlist.strings") == true, "@\(k.arb).description")
        }
    }

    @Test("PU07 PrivacyInfo.xcprivacy: no tracking, the three required reason APIs of §5")
    func privacyManifest() throws {
        let p = try Self.plist("\(Self.runnerDir)/PrivacyInfo.xcprivacy")
        #expect(Self.bool(p["NSPrivacyTracking"]) == false)
        #expect((p["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((p["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let apis = p["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        var got: [String: [String]] = [:]
        for a in apis {
            if let t = a["NSPrivacyAccessedAPIType"] as? String {
                got[t] = a["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            }
        }
        #expect(apis.count == 3)
        #expect(got == [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
        ])
    }

    @Test("StringsFile parser: comments, escapes, errors")
    func parser() throws {
        let s = try StringsFile.parse("/* c */\n// line\n\"A\" = \"x \\\"q\\\" \\\\ y\";\n \"B\"=\"Đã bật\" ;\n")
        #expect(s == ["A": "x \"q\" \\ y", "B": "Đã bật"])
        #expect(throws: StringsFile.Failure.self) { try StringsFile.parse("\"A\" = \"x\"") }
        #expect(throws: StringsFile.Failure.self) { try StringsFile.parse("\"A\" \"x\";") }
        #expect(throws: StringsFile.Failure.self) { try StringsFile.parse("\"A\" = \"x\";\n\"A\" = \"y\";") }
    }
}

/// Minimal parser of the old-style `.strings` format used by InfoPlist.strings: `"key" = "value";`, `/* */` and `//`
/// comments, escapes \" \\ \n \t.
enum StringsFile {
    struct Failure: Error { let reason: String }

    static func parse(_ text: String) throws -> [String: String] {
        let c = Array(text.unicodeScalars)
        var i = 0
        func skip() {
            while i < c.count {
                if CharacterSet.whitespacesAndNewlines.contains(c[i]) {
                    i += 1
                } else if c[i] == "/", i + 1 < c.count, c[i + 1] == "*" {
                    i += 2
                    while i + 1 < c.count, !(c[i] == "*" && c[i + 1] == "/") { i += 1 }
                    i += 2
                } else if c[i] == "/", i + 1 < c.count, c[i + 1] == "/" {
                    while i < c.count, c[i] != "\n" { i += 1 }
                } else {
                    return
                }
            }
        }
        func quoted() throws -> String {
            guard i < c.count, c[i] == "\"" else { throw Failure(reason: "expected a quote at \(i)") }
            i += 1
            var out = String.UnicodeScalarView()
            while i < c.count, c[i] != "\"" {
                if c[i] == "\\", i + 1 < c.count {
                    i += 1
                    switch c[i] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(c[i])
                    }
                } else {
                    out.append(c[i])
                }
                i += 1
            }
            guard i < c.count else { throw Failure(reason: "unterminated string") }
            i += 1
            return String(out)
        }
        func expect(_ ch: Unicode.Scalar) throws {
            skip()
            guard i < c.count, c[i] == ch else { throw Failure(reason: "expected \(ch) at \(i)") }
            i += 1
        }
        var result: [String: String] = [:]
        skip()
        while i < c.count {
            let key = try quoted()
            try expect("=")
            skip()
            let value = try quoted()
            try expect(";")
            guard result[key] == nil else { throw Failure(reason: "duplicate key \(key)") }
            result[key] = value
            skip()
        }
        return result
    }
}
