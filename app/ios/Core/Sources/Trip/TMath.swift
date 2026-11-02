// Deterministic helpers of T10 §4.0 / §6 (D1–D7) and Kotlin conversion semantics (T13 §5.2).
// Never use the standard library min/max on Double: their -0.0/NaN behaviour differs from the JVM.

enum TMath {
    // MARK: min / max / clamp (T10 §4.0: a <= b ? a : b, a >= b ? a : b)

    @inline(__always) static func min(_ a: Double, _ b: Double) -> Double { a <= b ? a : b }
    @inline(__always) static func max(_ a: Double, _ b: Double) -> Double { a >= b ? a : b }
    @inline(__always) static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { TMath.min(TMath.max(x, lo), hi) }

    @inline(__always) static func min(_ a: Int, _ b: Int) -> Int { a <= b ? a : b }
    @inline(__always) static func max(_ a: Int, _ b: Int) -> Int { a >= b ? a : b }
    @inline(__always) static func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int { TMath.min(TMath.max(x, lo), hi) }

    @inline(__always) static func min(_ a: Int64, _ b: Int64) -> Int64 { a <= b ? a : b }
    @inline(__always) static func max(_ a: Int64, _ b: Int64) -> Int64 { a >= b ? a : b }
    @inline(__always) static func clamp(_ x: Int64, _ lo: Int64, _ hi: Int64) -> Int64 { TMath.min(TMath.max(x, lo), hi) }

    /// Minimum of the non-nil elements, scanned left to right; nil when all are nil.
    static func minOrNull(_ xs: Int64?...) -> Int64? { minOrNull(array: xs) }

    static func minOrNull(array xs: [Int64?]) -> Int64? {
        var best: Int64? = nil
        for x in xs {
            guard let x else { continue }
            if let b = best { best = TMath.min(b, x) } else { best = x }
        }
        return best
    }

    static func maxTier(_ a: SamplingTier, _ b: SamplingTier) -> SamplingTier { a.rawValue >= b.rawValue ? a : b }

    /// T10 §4.0: drop nils; empty → nil; sort ascending (stable insertion sort, `<` only); element floor(n/2).
    static func medianHi(_ xs: [Double?]) -> Double? {
        var v: [Double] = []
        for x in xs { if let x { v.append(x) } }
        if v.isEmpty { return nil }
        // Insertion sort with strict `<`: equal values keep input order (same as a stable sort).
        var i = 1
        while i < v.count {
            let key = v[i]
            var j = i - 1
            while j >= 0 && key < v[j] {
                v[j + 1] = v[j]
                j -= 1
            }
            v[j + 1] = key
            i += 1
        }
        return v[v.count / 2]
    }

    /// Seconds (Double ≥ 0) → milliseconds: (Long) floor(s · 1000.0).
    @inline(__always) static func floorMs(_ s: Double) -> Int64 { kotlinToLong((s * 1000.0).rounded(.down)) }

    /// Int seconds parameter → ms as a Long multiplication (T10 §5, D3).
    @inline(__always) static func ms(_ seconds: Int) -> Int64 { Int64(seconds) * 1000 }

    /// Int → Int64 (exact).
    @inline(__always) static func i64(_ x: Int) -> Int64 { Int64(x) }

    /// Milliseconds → seconds.
    @inline(__always) static func toS(_ ms: Int64) -> Double { Double(ms) / 1000.0 }

    /// (Int) floor(x + 0.5); only used with x ≥ 0.
    @inline(__always) static func roundHalfUp(_ x: Double) -> Int { kotlinToInt((x + 0.5).rounded(.down)) }

    /// T10 §4.0: ema == nil ? x : ema + (x − ema) · dt / (tau + dt).
    static func blend(_ ema: Double?, _ x: Double, _ dt: Double, tauS: Int) -> Double {
        guard let ema else { return x }
        return ema + (x - ema) * dt / (Double(tauS) + dt)
    }

    // MARK: Kotlin conversion semantics (saturating, NaN → 0)

    /// Kotlin `Double.toLong()`.
    static func kotlinToLong(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        if x >= 9223372036854775808.0 { return Int64.max }
        if x <= -9223372036854775808.0 { return Int64.min }
        return Int64(x)
    }

    /// Kotlin `Double.toInt()` (Kotlin Int is 32-bit).
    static func kotlinToInt(_ x: Double) -> Int {
        if x.isNaN { return 0 }
        if x >= 2147483647.0 { return Int(Int32.max) }
        if x <= -2147483648.0 { return Int(Int32.min) }
        return Int(x)
    }

    /// Only for test S05: Swift never contracts `a * b + c` into an FMA.
    static func contractionProbe(_ a: Double, _ b: Double, _ c: Double) -> Double { a * b + c }
}
