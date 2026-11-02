/// GPX reader for the fixed tracegen format (README §2). String scanner: no XMLParser (needs libxml2 on Linux).
struct TraceSample: Sendable, Equatable {
    let index: Int
    let t: Int
    let lat: Double
    let lng: Double
    let accuracyM: Double
    let speedMps: Double?
}

enum Gpx {
    struct Invalid: Error, CustomStringConvertible { let description: String }

    static func read(_ text: String, startMs: Int64, intervalS: Int) throws -> [TraceSample] {
        let b = Array(text.utf8)
        var out: [TraceSample] = []
        var pos = 0
        let open = Array("<trkpt ".utf8), close = Array("</trkpt>".utf8)
        while let start = find(b, open, from: pos) {
            guard let end = find(b, close, from: start) else { throw Invalid(description: "gpx: unterminated trkpt") }
            let el = Array(b[start..<end])
            guard let lat = attr(el, "lat"), let lon = attr(el, "lon"),
                  let latV = Double(lat), let lonV = Double(lon) else { throw Invalid(description: "gpx: bad lat/lon") }
            guard let time = tag(el, "time") else { throw Invalid(description: "gpx: missing time") }
            guard let accS = tag(el, "napstop:acc"), let acc = Double(accS) else { throw Invalid(description: "gpx: missing acc") }
            var spd: Double? = nil
            if let s = tag(el, "napstop:spd") {
                guard let v = Double(s) else { throw Invalid(description: "gpx: bad spd") }
                spd = v
            }
            let ms = try IsoTime.parseMs(time)
            let dt = ms - startMs
            guard dt % 1000 == 0 else { throw Invalid(description: "gpx: time not whole seconds") }
            let t = Int(dt / 1000)
            guard t % intervalS == 0 else { throw Invalid(description: "gpx: t not multiple of interval") }
            if let prev = out.last, t <= prev.t { throw Invalid(description: "gpx: time not increasing") }
            out.append(TraceSample(index: out.count, t: t, lat: latV, lng: lonV, accuracyM: acc, speedMps: spd))
            pos = end + close.count
        }
        return out
    }

    private static func find(_ hay: [UInt8], _ needle: [UInt8], from: Int) -> Int? {
        guard needle.count <= hay.count else { return nil }
        var i = from
        let first = needle[0]
        while i + needle.count <= hay.count {
            if hay[i] == first {
                var ok = true
                for k in 1..<needle.count where hay[i + k] != needle[k] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }

    private static func attr(_ el: [UInt8], _ name: String) -> String? {
        let key = Array(" \(name)=\"".utf8)
        guard let i = find(el, key, from: 0) else { return nil }
        let s = i + key.count
        var e = s
        while e < el.count && el[e] != 0x22 { e += 1 }
        return String(decoding: el[s..<e], as: UTF8.self)
    }

    private static func tag(_ el: [UInt8], _ name: String) -> String? {
        let o = Array("<\(name)>".utf8), c = Array("</\(name)>".utf8)
        guard let i = find(el, o, from: 0), let j = find(el, c, from: i) else { return nil }
        return String(decoding: el[(i + o.count)..<j], as: UTF8.self)
    }
}
