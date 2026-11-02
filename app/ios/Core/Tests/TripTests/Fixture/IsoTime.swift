/// `YYYY-MM-DDTHH:MM:SSZ` → epoch ms (days-from-civil, H. Hinnant). Anything else is an error.
enum IsoTime {
    struct Invalid: Error, CustomStringConvertible { var description: String { "invalid ISO time" } }

    static func parseMs(_ s: String) throws -> Int64 {
        let b = Array(s.utf8)
        guard b.count == 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A, b[19] == 0x5A else {
            throw Invalid()
        }
        func num(_ from: Int, _ len: Int) throws -> Int64 {
            var v: Int64 = 0
            for i in from..<(from + len) {
                guard b[i] >= 0x30 && b[i] <= 0x39 else { throw Invalid() }
                v = v * 10 + Int64(b[i] - 0x30)
            }
            return v
        }
        let y = try num(0, 4), m = try num(5, 2), d = try num(8, 2)
        let hh = try num(11, 2), mm = try num(14, 2), ss = try num(17, 2)
        guard (1...12).contains(m), (1...31).contains(d), hh < 24, mm < 60, ss < 60 else { throw Invalid() }
        return (daysFromCivil(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss) * 1000
    }

    static func daysFromCivil(_ y0: Int64, _ m: Int64, _ d: Int64) -> Int64 {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
