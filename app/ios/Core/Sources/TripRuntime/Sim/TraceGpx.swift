// Reader of the bundled GPX traces (fixtures/traces/README.md §2, T18 §4, T18.1 D13): XMLParser with namespaces, every
// trk/trkseg/trkpt in document order. Same rules and messages as Kotlin `TraceGpx`. Errors name the rule only: never a
// value or a coordinate. External entities are never resolved [XML].
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum TraceGpx {
    public static let ns = "https://napstop.app/xmlns/trace/1"

    public static func parse(_ data: Data) throws(TraceFormatError) -> [TraceSample] {
        let handler = Handler()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        let ok = parser.parse()
        if let e = handler.error { throw e }
        // A truncated document may parse "ok" on some XMLParser builds (FoundationXML): an unclosed root is malformed too.
        if !ok || !handler.closedRoot { throw TraceFormatError(rule: "xml malformed") }
        guard let t0 = handler.points.first?.timeMs else { throw TraceFormatError(rule: "no trkpt") }
        return handler.points.map { p in
            TraceSample(t: Int((p.timeMs - t0) / 1000), lat: p.lat, lng: p.lng, accM: p.acc, spdMps: p.spd,
                        tMs: p.timeMs - t0)
        }
    }

    /// ISO-8601 UTC (`2026-03-14T02:00:00Z`, fractional seconds allowed) → epoch ms; nil when invalid.
    static func timeMs(_ s: String) -> Int64? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return Int64((d.timeIntervalSince1970 * 1000).rounded()) }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return Int64((d.timeIntervalSince1970 * 1000).rounded()) }
        return nil
    }

    private struct Point {
        let lat: Double
        let lng: Double
        let timeMs: Int64
        let acc: Double
        let spd: Double?
    }

    private final class Handler: NSObject, XMLParserDelegate {
        var points: [Point] = []
        var error: TraceFormatError?
        private var depth = 0
        private var sawRoot = false
        var closedRoot: Bool { sawRoot && depth == 0 }
        private var inPoint = false
        private var lat = 0.0
        private var lng = 0.0
        private var time: Int64?
        private var acc: Double?
        private var spd: Double?
        private var field: String?
        private var text = ""

        private func fail(_ parser: XMLParser, _ rule: String) {
            if error == nil { error = TraceFormatError(rule: rule) }
            parser.abortParsing()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            depth += 1
            sawRoot = true
            guard error == nil else { return }
            let uri = namespaceURI ?? ""
            if elementName == "trkpt" && uri != TraceGpx.ns {
                if inPoint { return fail(parser, "trkpt nested") }
                inPoint = true
                guard let la = coord(attributeDict["lat"], 90, "lat", parser) else { return }
                guard let lo = coord(attributeDict["lon"], 180, "lon", parser) else { return }
                lat = la
                lng = lo
                time = nil
                acc = nil
                spd = nil
                return
            }
            if !inPoint { return }
            if elementName == "time" && uri != TraceGpx.ns {
                field = "time"
            } else if (elementName == "acc" || elementName == "spd") && uri == TraceGpx.ns {
                field = elementName
            } else {
                field = nil
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if field != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            depth -= 1
            guard error == nil else { return }
            let uri = namespaceURI ?? ""
            if let f = field, elementName == f {
                let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
                switch f {
                case "time":
                    guard let ms = TraceGpx.timeMs(v) else { return fail(parser, "time invalid") }
                    time = ms
                case "acc":
                    guard let a = Double(v), a.isFinite, a > 0 else { return fail(parser, "acc invalid") }
                    acc = a
                default:
                    guard let s = Double(v), s.isFinite, s >= 0 else { return fail(parser, "spd invalid") }
                    spd = s
                }
                field = nil
                return
            }
            if elementName == "trkpt" && uri != TraceGpx.ns && inPoint {
                guard let t = time else { return fail(parser, "time missing") }
                guard let a = acc else { return fail(parser, "acc missing") }
                if let prev = points.last, t <= prev.timeMs { return fail(parser, "time not increasing") }
                points.append(Point(lat: lat, lng: lng, timeMs: t, acc: a, spd: spd))
                inPoint = false
            }
        }

        private func coord(_ raw: String?, _ limit: Double, _ what: String, _ parser: XMLParser) -> Double? {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), let v = Double(s) else {
                fail(parser, "\(what) missing")
                return nil
            }
            if !v.isFinite || v < -limit || v > limit {
                fail(parser, "\(what) out of range")
                return nil
            }
            return v
        }
    }
}
