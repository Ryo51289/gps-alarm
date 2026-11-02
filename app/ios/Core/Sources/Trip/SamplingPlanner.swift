// Sampling policy (T10 §4.12).
enum SamplingPlanner {
    static func tierOf(_ t: Double?, _ cur: SamplingTier, _ p: EngineParams) -> SamplingTier {
        guard let t else { return cur }
        let h = p.tierHysteresisFactor
        if t <= Double(p.denseEnterS) || (cur == .dense && t <= Double(p.denseEnterS) * h) { return .dense }
        if t <= Double(p.mediumEnterS) || (cur != .sparse && t <= Double(p.mediumEnterS) * h) { return .medium }
        return .sparse
    }

    /// nil = keep the current policy (ENDED, as Kotlin; step 9 never runs in ENDED).
    static func targetTier(_ s: EngineState, _ e: Estimate?, predicted: Int64?, now: Int64) -> SamplingTier? {
        switch s.phase {
        case .ended:
            return nil
        case .acquiring, .alarming, .snoozed, .overshot:
            return .dense
        case .tracking:
            let cur = s.policy?.tier ?? .dense
            let t: Double? = predicted.map { TMath.toS($0 - now) }
            var tier = tierOf(t, cur, s.params)
            if !(e?.established ?? false) { tier = TMath.maxTier(tier, .medium) }
            if s.gps == .lost { tier = TMath.maxTier(tier, cur) }
            return tier
        }
    }

    static func policyFor(_ tier: SamplingTier, _ p: EngineParams, maxSaving: Bool) -> SamplingPolicy {
        let f = maxSaving ? p.maxSavingIntervalFactor : 1
        switch tier {
        case .sparse:
            return SamplingPolicy(tier: .sparse, intervalS: p.samplingSparseIntervalS * f,
                                  minIntervalS: p.samplingSparseMinIntervalS * f, accuracy: .balanced)
        case .medium:
            return SamplingPolicy(tier: .medium, intervalS: p.samplingMediumIntervalS * f,
                                  minIntervalS: p.samplingMediumMinIntervalS * f, accuracy: .high)
        case .dense:
            return SamplingPolicy(tier: .dense, intervalS: p.samplingDenseIntervalS,
                                  minIntervalS: p.samplingDenseMinIntervalS, accuracy: .high)
        }
    }
}
