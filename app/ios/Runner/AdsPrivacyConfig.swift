import GoogleMobileAds

/// T42.1 E1 (CI branch ci/ios-*-t42ads-gma only, never merged): privacy flags of the Google Mobile Ads SDK, set at the
/// top of `application(_:didFinishLaunchingWithOptions:)`, before any plugin is registered. The SDK is never started
/// here (no `MobileAds.shared.start`): E1 only measures what linking it changes.
enum AdsPrivacyConfig {
  static func apply() {
    let config = MobileAds.shared.requestConfiguration
    // Non-personalized ads (ADR-004 C-A2) [G2].
    config.publisherPrivacyPersonalizationState = .disabled
    // GMA iOS >= 13.12.0 collects coarse location by default when the app has location permission [G2].
    config.coarseLocationCollectionEnabled = false
  }

  /// Read back for AdsPrivacyConfigTests, so the test does not need `import GoogleMobileAds` itself.
  static func snapshot() -> (personalizationState: Int, coarseLocationCollectionEnabled: Bool) {
    let config = MobileAds.shared.requestConfiguration
    return (config.publisherPrivacyPersonalizationState.rawValue, config.coarseLocationCollectionEnabled)
  }
}
