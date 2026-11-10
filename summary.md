# CI iOS — ci/ios-ipa-t292e

commit 3ab549df6589d8961c6c626fcd406f224e2efb11 · run https://github.com/Ryo51289/gps-alarm/actions/runs/42741120860 · 2026-11-10T02:23:28Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-10T02:12:25Z | 2026-11-10T02:12:26Z | 1 |
| swift-macos | skipped | — | — | — |
| ios-sim | skipped | — | — | — |
| ios-device | success | 2026-11-10T02:12:35Z | 2026-11-10T02:22:41Z | 11 |

## plan

- status: success (event push, ref ci/ios-ipa-t292e)
- swift=false
- sim=false
- ipa=true
- diag=true
- telemetry=false

## ios-device

- status: success; build: success; diag: true
- telemetry: auto
- firebase checks: success
- C1 GoogleService-Info.plist in bundle: ok (BUNDLE_ID expected app.napstop)
- C2 Info.plist collection keys (7 false): ok
- C3 no AdSupport / AppTrackingTransparency (7 binaries): ok
- C4 privacy manifests (23, no tracking): ok
  - Firebase_FirebaseABTesting.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCore.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCoreExtension.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCoreInternal.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCrashlytics.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseInstallations.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseRemoteConfig.bundle/PrivacyInfo.xcprivacy
  - Frameworks/Flutter.framework/PrivacyInfo.xcprivacy
  - GoogleDataTransport_GoogleDataTransport.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-AppDelegateSwizzler.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-Environment.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-Logger.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-MethodSwizzler.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-NSData.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-Network.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-Reachability.bundle/PrivacyInfo.xcprivacy
  - GoogleUtilities_GoogleUtilities-UserDefaults.bundle/PrivacyInfo.xcprivacy
  - PrivacyInfo.xcprivacy
  - Promises_FBLPromises.bundle/PrivacyInfo.xcprivacy
  - nanopb_nanopb.bundle/PrivacyInfo.xcprivacy
  - package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy
  - shared_preferences_foundation_shared_preferences_foundation.bundle/PrivacyInfo.xcprivacy
  - url_launcher_ios_url_launcher_ios.bundle/PrivacyInfo.xcprivacy
- dSYM step: success
- dSYM: 5 found (Flutter engine: Flutter.framework.dSYM (from the build))
  - App.framework.dSYM 25047C5D-2FD6-333A-F612-5CFC59554563 arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
  - Runner.app.dSYM 924CE10E-B88A-3339-8D74-9D37E42CBCAC arm64
  - objective_c.framework.dSYM 01D17F16-2C12-349D-8EA9-8DBA11BD4CDB arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
- dSYM upload: ok (exit 0), 5 file(s), tool from SwiftPM checkout
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- SWIFT_ACTIVE_COMPILATION_CONDITIONS (Runner, Release) = NAPSTOP_DIAG
- ipa:  16M, artifact napstop-ios-unsigned (unsigned, 7 days; install with xtool install)
