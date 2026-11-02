/// Deterministic PRNG for property tests (same algorithm as tools/tracegen SplitMix64).
struct SplitMix64 {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextDouble() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }

    mutating func nextInt(_ upper: Int) -> Int { Int(next() % UInt64(upper)) }
}
