import Foundation

/// ISO-8601 timestamps with milliseconds and a numeric offset ("2026-10-29T21:35:12.345+07:00"), done with integer
/// arithmetic: no DateFormatter (not Sendable, slow to create, differs between Apple Foundation and corelibs).
public enum IsoTime {
    /// `offsetSeconds`: seconds east of UTC (TimeZone.secondsFromGMT(for:)).
    public static func format(_ date: Date, offsetSeconds: Int) -> String {
        let local = epochMs(date) + Int64(offsetSeconds) * 1000
        let (days, msOfDay) = floorDivMod(local, 86_400_000)
        let (y, m, d) = civil(fromDays: days)
        let hh = Int(msOfDay / 3_600_000)
        let mm = Int(msOfDay / 60_000 % 60)
        let ss = Int(msOfDay / 1000 % 60)
        let ms = Int(msOfDay % 1000)
        let sign = offsetSeconds < 0 ? "-" : "+"
        let off = abs(offsetSeconds) / 60
        return "\(pad(Int(y), 4))-\(pad(m, 2))-\(pad(d, 2))T\(pad(hh, 2)):\(pad(mm, 2)):\(pad(ss, 2)).\(pad(ms, 3))"
            + "\(sign)\(pad(off / 60, 2)):\(pad(off % 60, 2))"
    }

    /// `format` with the device time zone at `date`.
    public static func local(_ date: Date) -> String {
        format(date, offsetSeconds: TimeZone.current.secondsFromGMT(for: date))
    }

    /// "yyyyMMdd-HHmmss" in the given offset (run ids, S3 §6.6).
    public static func compact(_ date: Date, offsetSeconds: Int) -> String {
        let s = format(date, offsetSeconds: offsetSeconds)
        let chars = Array(s)
        // yyyy-MM-ddTHH:mm:ss
        let ymd = String(chars[0..<4]) + String(chars[5..<7]) + String(chars[8..<10])
        let hms = String(chars[11..<13]) + String(chars[14..<16]) + String(chars[17..<19])
        return ymd + "-" + hms
    }

    /// "HH:mm:ss" in the given offset.
    public static func clock(_ date: Date, offsetSeconds: Int) -> String {
        let chars = Array(format(date, offsetSeconds: offsetSeconds))
        return String(chars[11..<19])
    }

    /// Parses `yyyy-MM-ddTHH:mm:ss[.fraction](Z|±hh:mm|±hhmm)`. Returns nil for anything else.
    public static func parse(_ text: String) -> Date? {
        let c = Array(text.unicodeScalars)
        var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= c.count else { return nil }
            var v = 0
            for k in 0..<n {
                let d = Int(c[i + k].value) - 48
                guard d >= 0, d <= 9 else { return nil }
                v = v * 10 + d
            }
            i += n
            return v
        }
        func take(_ ch: Unicode.Scalar) -> Bool {
            guard i < c.count, c[i] == ch else { return false }
            i += 1
            return true
        }
        guard let y = digits(4), take("-"), let mo = digits(2), take("-"), let d = digits(2) else { return nil }
        guard i < c.count, c[i] == "T" || c[i] == " " else { return nil }
        i += 1
        guard let hh = digits(2), take(":"), let mi = digits(2), take(":"), let ss = digits(2) else { return nil }
        guard (1...12).contains(mo), (1...31).contains(d), hh < 24, mi < 60, ss < 61 else { return nil }
        var fracMs = 0
        if take(".") {
            var scale = 100
            var any = false
            while i < c.count, let dv = digitValue(c[i]) {
                fracMs += dv * scale
                scale /= 10
                any = true
                i += 1
            }
            if !any { return nil }
        }
        var offset = 0
        guard i < c.count else { return nil }
        if take("Z") || take("z") {
            offset = 0
        } else if c[i] == "+" || c[i] == "-" {
            let negative = c[i] == "-"
            i += 1
            guard let oh = digits(2) else { return nil }
            _ = take(":")
            guard let om = digits(2) else { return nil }
            offset = (oh * 3600 + om * 60) * (negative ? -1 : 1)
        } else {
            return nil
        }
        guard i == c.count else { return nil }
        let days = daysFromCivil(Int64(y), mo, d)
        let localMs = days * 86_400_000 + Int64(hh * 3_600_000 + mi * 60_000 + ss * 1000 + fracMs)
        let ms = localMs - Int64(offset) * 1000
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    /// Milliseconds since 1970, rounded to the nearest (so format(parse(s)) == s despite binary floating point).
    public static func epochMs(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func digitValue(_ s: Unicode.Scalar) -> Int? {
        let d = Int(s.value) - 48
        return (d >= 0 && d <= 9) ? d : nil
    }

    private static func pad(_ v: Int, _ width: Int) -> String {
        let s = String(v)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    private static func floorDivMod(_ a: Int64, _ b: Int64) -> (Int64, Int64) {
        var q = a / b
        var r = a % b
        if r < 0 {
            q -= 1
            r += b
        }
        return (q, r)
    }

    // Howard Hinnant's civil-from-days / days-from-civil (proleptic Gregorian).
    private static func civil(fromDays days: Int64) -> (Int64, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, Int(m), Int(d))
    }

    private static func daysFromCivil(_ year: Int64, _ month: Int, _ day: Int) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = Int64(month > 2 ? month - 3 : month + 9)
        let doy = (153 * mp + 2) / 5 + Int64(day) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

/// Core Audio / AVAudioSession error codes are four-character codes ('!int' = cannotInterruptOthers).
public enum FourCC {
    /// "!int" for 0x21696E74; nil when the code is not four printable ASCII characters.
    public static func string(_ code: Int) -> String? {
        guard code > 0, code <= Int(UInt32.max) else { return nil }
        let v = UInt32(code)
        var s = ""
        for shift in [24, 16, 8, 0] {
            let byte = (v >> UInt32(shift)) & 0xFF
            guard byte >= 0x20, byte < 0x7F, let scalar = Unicode.Scalar(byte) else { return nil }
            s.unicodeScalars.append(scalar)
        }
        return s
    }
}

/// Vietnamese duration text for summaries.
public enum DurationText {
    /// 45 → "45 s", 125 → "2 ph 05 s", 3725 → "1 g 02 ph".
    public static func vi(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        if total < 3600 {
            let s = total % 60
            return "\(total / 60) ph " + (s < 10 ? "0" : "") + "\(s) s"
        }
        let m = total / 60 % 60
        return "\(total / 3600) g " + (m < 10 ? "0" : "") + "\(m) ph"
    }
}
