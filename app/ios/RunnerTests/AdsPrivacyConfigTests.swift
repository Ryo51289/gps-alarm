import XCTest

#if canImport(GoogleMobileAds)
  import GoogleMobileAds
#endif

@testable import Runner

/// T42.1 E1-e (CI branch ci/ios-sim-t42ads-gma only, never merged).
final class AdsPrivacyConfigTests: XCTestCase {
  /// Through Runner only: passes whether or not RunnerTests can import GoogleMobileAds.
  func testApplySetsNonPersonalizedAndNoCoarseLocation() {
    AdsPrivacyConfig.apply()
    let s = AdsPrivacyConfig.snapshot()
    XCTAssertEqual(s.personalizationState, 2, "PublisherPrivacyPersonalizationState.disabled is 2 in GADRequestConfiguration.h")
    XCTAssertFalse(s.coarseLocationCollectionEnabled)
  }

  #if canImport(GoogleMobileAds)
    /// E1-c/E1-e: RunnerTests can import the module; the typed API reads the same values.
    func testTypedApiAfterApply() {
      AdsPrivacyConfig.apply()
      let config = MobileAds.shared.requestConfiguration
      XCTAssertEqual(config.publisherPrivacyPersonalizationState, .disabled)
      XCTAssertFalse(config.coarseLocationCollectionEnabled)
    }
  #else
    func testTypedApiAfterApply() throws {
      throw XCTSkip("E1-c: RunnerTests cannot import GoogleMobileAds (canImport is false)")
    }
  #endif
}
