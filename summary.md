# CI iOS — ci/ios-ipa-t237

commit 5ed1ec359cf481d8ac63bf01df28981b09eaab71 · run https://github.com/Ryo51289/gps-alarm/actions/runs/43186315813 · 2026-11-12T09:00:53Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-12T08:50:59Z | 2026-11-12T08:51:01Z | 1 |
| swift-macos | skipped | — | — | — |
| ios-sim | skipped | — | — | — |
| ios-device | success | 2026-11-12T08:51:11Z | 2026-11-12T09:00:12Z | 10 |

## plan

- status: success (event push, ref ci/ios-ipa-t237)
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
- dSYM: 6 found (Flutter engine: Flutter.framework.dSYM (from the build))
  - App.framework.dSYM CCEA31BD-677A-A2F5-D521-BDF94E0612D3 arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
  - NapStopLiveActivity.appex.dSYM 479C2842-ECAE-3982-A3B7-E0658B59472A arm64
  - Runner.app.dSYM ED436B0E-AD73-396E-BEDF-68FD3A3D32E6 arm64
  - objective_c.framework.dSYM CA4DE62E-184D-32ED-A1A1-9BD2E88EDA8F arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
- dSYM upload: ok (exit 0), 6 file(s), tool from SwiftPM checkout
- appex checks (T23.6): success
  - A1 PlugIns = NapStopLiveActivity.appex: ok
  - A2 extension point widgetkit, package XPC!: ok
  - A3 bundle id app.napstop.LiveActivity: ok
  - A4 MinimumOSVersion 17.0, version 0.1.0 (1) = app: ok
  - A5 executable NapStopLiveActivity, archs arm64: ok
  - A6 no entitlements, no provisioning profile: ok
  - A7 ipa holds PlugIns/NapStopLiveActivity.appex: ok
  - info: appex size 144K
appex checks: ok
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- SWIFT_ACTIVE_COMPILATION_CONDITIONS (Runner, Release) = NAPSTOP_DIAG
- ipa:  16M, artifact napstop-ios-unsigned (unsigned, 7 days; install with xtool install)
