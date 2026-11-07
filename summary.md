# CI iOS — ci/ios-ipa-t292c-noadid

commit b7393d3bf4c45dd7d7f36b7788d02f2b8b1688fa · run https://github.com/Ryo51289/gps-alarm/actions/runs/42371376792 · 2026-11-07T12:20:14Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-07T12:11:39Z | 2026-11-07T12:11:40Z | 1 |
| swift-macos | skipped | — | — | — |
| ios-sim | skipped | — | — | — |
| ios-device | success | 2026-11-07T12:11:49Z | 2026-11-07T12:19:31Z | 8 |

## plan

- status: success (event push, ref ci/ios-ipa-t292c-noadid)
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
- C3 no AdSupport / AppTrackingTransparency (9 binaries): ok
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
- IDFA diag:
  - Runner
    L /System/Library/Frameworks/AlarmKit.framework/AlarmKit
    L /System/Library/Frameworks/ActivityKit.framework/ActivityKit
    L /System/Library/Frameworks/UIKit.framework/UIKit
    L /System/Library/Frameworks/Security.framework/Security
    L /System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration
    L /System/Library/Frameworks/CoreTelephony.framework/CoreTelephony
    L /System/Library/Frameworks/StoreKit.framework/StoreKit
    L /System/Library/Frameworks/Foundation.framework/Foundation
    L /System/Library/Frameworks/AVFAudio.framework/AVFAudio
    L /System/Library/Frameworks/AppIntents.framework/AppIntents
    L /System/Library/Frameworks/Combine.framework/Combine
    L /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
    L /System/Library/Frameworks/CoreGraphics.framework/CoreGraphics
    L /System/Library/Frameworks/CoreLocation.framework/CoreLocation
    L /System/Library/Frameworks/MapKit.framework/MapKit
    L /System/Library/Frameworks/SafariServices.framework/SafariServices
    L /System/Library/Frameworks/UserNotifications.framework/UserNotifications
    L /System/Library/Frameworks/SwiftUI.framework/SwiftUI
    S    2 AdSupport
    S    8 IdentitySupport
  - Frameworks/App.framework/App
  - Frameworks/FirebaseAnalytics.framework/FirebaseAnalytics
  - Frameworks/Flutter.framework/Flutter
    L /System/Library/Frameworks/AudioToolbox.framework/AudioToolbox
    L /System/Library/Frameworks/CoreMedia.framework/CoreMedia
    L /System/Library/Frameworks/CoreVideo.framework/CoreVideo
    L /System/Library/Frameworks/IOSurface.framework/IOSurface
    L /System/Library/Frameworks/QuartzCore.framework/QuartzCore
    L /System/Library/Frameworks/WebKit.framework/WebKit
    L /System/Library/Frameworks/UIKit.framework/UIKit
    L /System/Library/Frameworks/Foundation.framework/Foundation
    L /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
    L /System/Library/Frameworks/ImageIO.framework/ImageIO
    L /System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices
    L /System/Library/Frameworks/CoreServices.framework/CoreServices
    L /System/Library/Frameworks/CoreGraphics.framework/CoreGraphics
    L /System/Library/Frameworks/CoreText.framework/CoreText
    L /System/Library/Frameworks/Metal.framework/Metal
    L /System/Library/Frameworks/MetalPerformanceShaders.framework/MetalPerformanceShaders
    L /System/Library/Frameworks/Security.framework/Security
    L /System/Library/Frameworks/Accessibility.framework/Accessibility
  - Frameworks/GoogleAdsOnDeviceConversion.framework/GoogleAdsOnDeviceConversion
  - Frameworks/GoogleAppMeasurement.framework/GoogleAppMeasurement
  - Frameworks/GoogleAppMeasurementIdentitySupport.framework/GoogleAppMeasurementIdentitySupport
  - Frameworks/objective_c.framework/objective_c
  - Frameworks/sqlite3.framework/sqlite3
    A artifacts/abseil-cpp-binary/absl/absl.xcframework
    A artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework
    A artifacts/firebase-ios-sdk/FirebaseFirestoreInternal/FirebaseFirestoreInternal.xcframework
    A artifacts/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion/GoogleAdsOnDeviceConversion.xcframework
    A artifacts/googleappmeasurement/GoogleAppMeasurement/GoogleAppMeasurement.xcframework
    A artifacts/googleappmeasurement/GoogleAppMeasurementIdentitySupport/GoogleAppMeasurementIdentitySupport.xcframework
    A artifacts/grpc-binary/grpc/grpc.xcframework
    A artifacts/grpc-binary/grpcpp/grpcpp.xcframework
    A artifacts/grpc-binary/openssl_grpc/openssl_grpc.xcframework
- dSYM step: success
- dSYM: 5 found (Flutter engine: Flutter.framework.dSYM (from the build))
  - App.framework.dSYM 25047C5D-2FD6-333A-F612-5CFC59554563 arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
  - Runner.app.dSYM 14CAD5B2-BFDF-35A9-A7F4-2200BB21E972 arm64
  - objective_c.framework.dSYM 0029CFF3-635A-34E1-93B6-0E391911DCCF arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
- dSYM upload: ok (exit 0), 5 file(s), tool from SwiftPM checkout
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- SWIFT_ACTIVE_COMPILATION_CONDITIONS (Runner, Release) = NAPSTOP_DIAG
- ipa:  16M, artifact napstop-ios-unsigned (unsigned, 7 days; install with xtool install)
