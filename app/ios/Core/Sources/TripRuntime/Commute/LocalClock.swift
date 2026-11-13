// Local calendar arithmetic for commute windows (docs/specs/T23.8.md §5.2, D8). Pure, no Calendar/TimeZone:
// proleptic Gregorian on wallMs + offsetS·1000, so Linux and Apple agree and tests need no time zone database.
import Foundation

public struct LocalTime: Sendable, Equatable {
    /// 0 = Monday … 6 = Sunday.
    public let weekdayIndex: Int
    /// 0...1439.
    public let minuteOfDay: Int
    /// "yyyy-MM-dd".
    public let dateKey: String
}

public enum LocalClock {
    private static let msPerDay: Int64 = 86_400_000

    /// Local weekday, minute and date of `wallMs` at UTC offset `offsetS` (the offset at that instant).
    public static func local(_ wallMs: Int64, offsetS: Int) -> LocalTime {
        let (shifted, overflow) = wallMs.addingReportingOverflow(Int64(offsetS) * 1000)
        let t = overflow ? wallMs : shifted
        let days = floorDiv(t, msPerDay)
        let msOfDay = t - days * msPerDay
        // 1970-01-01 was a Thursday (index 3).
        let weekday = Int(floorMod(days + 3, 7))
        let (y, m, d) = civil(fromDays: days)
        return LocalTime(weekdayIndex: weekday, minuteOfDay: Int(msOfDay / 60_000), dateKey: dateKey(y, m, d))
    }

    /// Days since 1970-01-01 of a canonical "yyyy-MM-dd" key (year 0001...9999, real calendar date), else nil.
    public static func dayNumber(dateKey k: String) -> Int64? {
        let u = Array(k.utf8)
        guard u.count == 10, u[4] == UInt8(ascii: "-"), u[7] == UInt8(ascii: "-") else { return nil }
        func num(_ r: Range<Int>) -> Int64? {
            var v: Int64 = 0
            for i in r {
                let c = u[i]
                guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else { return nil }
                v = v * 10 + Int64(c - UInt8(ascii: "0"))
            }
            return v
        }
        guard let y = num(0..<4), let m = num(5..<7), let d = num(8..<10), y >= 1, (1...12).contains(m) else { return nil }
        guard d >= 1, d <= daysInMonth(y, m) else { return nil }
        return days(fromCivil: y, m, d)
    }

    // MARK: Gregorian (H. Hinnant, "chrono-compatible low-level date algorithms")

    static func civil(fromDays z0: Int64) -> (Int64, Int64, Int64) {
        let z = z0 + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }

    static func days(fromCivil y0: Int64, _ m: Int64, _ d: Int64) -> Int64 {
        let y = m <= 2 ? y0 - 1 : y0
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let mp = m > 2 ? m - 3 : m + 9
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func daysInMonth(_ y: Int64, _ m: Int64) -> Int64 {
        switch m {
        case 2: (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func dateKey(_ y: Int64, _ m: Int64, _ d: Int64) -> String {
        func pad(_ v: Int64, _ w: Int) -> String {
            let s = String(v)
            return s.count >= w ? s : String(repeating: "0", count: w - s.count) + s
        }
        return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))"
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    private static func floorMod(_ a: Int64, _ b: Int64) -> Int64 { a - floorDiv(a, b) * b }
}
