/// Bit-level helpers for exact Double comparison (U51, U69, S01).
enum Bits {
    static func hex(_ x: Double) -> String {
        let h = String(x.bitPattern, radix: 16)
        return String(repeating: "0", count: 16 - h.count) + h
    }

    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.bitPattern == y.bitPattern
        default: return false
        }
    }

    static func same(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.bitPattern == $1.bitPattern }
    }
}
