# CI iOS — ci/ios-ipa-t42ads-gma

commit b1cce009f50410316d6fcb36119307ff54725cff · run https://github.com/Ryo51289/gps-alarm/actions/runs/43609942208 · 2026-11-14T15:32:03Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-14T15:23:43Z | 2026-11-14T15:23:48Z | 1 |
| swift-macos | skipped | — | — | — |
| ios-sim | skipped | — | — | — |
| ios-device | failure | 2026-11-14T15:23:55Z | 2026-11-14T15:31:46Z | 8 |

## plan

- status: success (event push, ref ci/ios-ipa-t42ads-gma)
- swift=false
- sim=false
- ipa=true
- diag=false
- telemetry=false

## ios-device

- status: failure; build: success; diag: false
- telemetry: auto
- firebase checks: failure
- C1 GoogleService-Info.plist in bundle: ok (BUNDLE_ID expected app.napstop)
- C2 Info.plist collection keys (7 false): ok
- C3 no AdSupport / AppTrackingTransparency (9 binaries): FAILED
  - C3 otool-L: Runner
      /System/Library/Frameworks/AdSupport.framework/AdSupport (compatibility version 1.0.0, current version 1.0.0)
  - C3 nm-u: Runner
      _OBJC_CLASS_$_ASIdentifierManager
- C4 privacy manifests (26, no tracking): ok
  - Firebase_FirebaseABTesting.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCore.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCoreExtension.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCoreInternal.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseCrashlytics.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseInstallations.bundle/PrivacyInfo.xcprivacy
  - Firebase_FirebaseRemoteConfig.bundle/PrivacyInfo.xcprivacy
  - Frameworks/Flutter.framework/PrivacyInfo.xcprivacy
  - Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy
  - Frameworks/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy
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
  - webview_flutter_wkwebview_webview_flutter_wkwebview.bundle/PrivacyInfo.xcprivacy
- dSYM step: success
- dSYM: 5 found (Flutter engine: Flutter.framework.dSYM (from the build))
  - App.framework.dSYM 4989B483-994B-C40A-05D2-4968D252395D arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
  - Runner.app.dSYM 5A410C88-3AB1-3ED5-B1A1-2B1D961A0B2D arm64
  - objective_c.framework.dSYM 9E6FA6F7-FB8B-32DE-B2F8-C33624BCAD6F arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
- dSYM upload: ok (exit 0), 5 file(s), tool from SwiftPM checkout
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- SWIFT_ACTIVE_COMPILATION_CONDITIONS (Runner, Release) = 
- ipa:  17M, artifact napstop-ios-unsigned (unsigned, 7 days; install with xtool install)

## E1 report (T42.1)

### Sizes (E1-f)

- ipa bytes: 18154409
- Runner.app KiB (du -sk): 46184
- Runner binary bytes: 14514896

```
   11952 KiB  Frameworks/App.framework
      40 KiB  Frameworks/FirebaseAnalytics.framework
   10244 KiB  Frameworks/Flutter.framework
      40 KiB  Frameworks/GoogleAppMeasurement.framework
      48 KiB  Frameworks/GoogleMobileAds.framework
     208 KiB  Frameworks/objective_c.framework
    1620 KiB  Frameworks/sqlite3.framework
      44 KiB  Frameworks/UserMessagingPlatform.framework
       8 KiB  Firebase_FirebaseABTesting.bundle
       8 KiB  Firebase_FirebaseCore.bundle
       8 KiB  Firebase_FirebaseCoreExtension.bundle
       8 KiB  Firebase_FirebaseCoreInternal.bundle
       8 KiB  Firebase_FirebaseCrashlytics.bundle
       8 KiB  Firebase_FirebaseInstallations.bundle
       8 KiB  Firebase_FirebaseRemoteConfig.bundle
      32 KiB  google_mobile_ads_google_mobile_ads.bundle
       8 KiB  GoogleDataTransport_GoogleDataTransport.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-AppDelegateSwizzler.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-Environment.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-Logger.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-MethodSwizzler.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-Network.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-NSData.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-Reachability.bundle
       8 KiB  GoogleUtilities_GoogleUtilities-UserDefaults.bundle
       8 KiB  nanopb_nanopb.bundle
       8 KiB  package_info_plus_package_info_plus.bundle
       8 KiB  Promises_FBLPromises.bundle
       8 KiB  shared_preferences_foundation_shared_preferences_foundation.bundle
       8 KiB  url_launcher_ios_url_launcher_ios.bundle
       8 KiB  webview_flutter_wkwebview_webview_flutter_wkwebview.bundle
```

### Link type and AdSupport/ATT signals per binary (E1-a, E1-c)

| binary | type | otool -L (AdSupport|AppTrackingTransparency|GoogleMobileAds|UserMessagingPlatform) | nm -u (ASIdentifierManager|ATTrackingManager) | strings (ASIdentifierManager|ATTrackingManager) |
|---|---|---|---|---|
| Runner | EXECUTE | AdSupport.framework/AdSupport | _OBJC_CLASS_$_ASIdentifierManager | 1 |
| Frameworks/App.framework/App | DYLIB | none | none | 0 |
| Frameworks/FirebaseAnalytics.framework/FirebaseAnalytics | DYLIB | none | none | 0 |
| Frameworks/Flutter.framework/Flutter | DYLIB | none | none | 0 |
| Frameworks/GoogleAppMeasurement.framework/GoogleAppMeasurement | DYLIB | none | none | 0 |
| Frameworks/GoogleMobileAds.framework/GoogleMobileAds | DYLIB | GoogleMobileAds.framework/GoogleMobileAds | none | 0 |
| Frameworks/objective_c.framework/objective_c | DYLIB | none | none | 0 |
| Frameworks/sqlite3.framework/sqlite3 | DYLIB | none | none | 0 |
| Frameworks/UserMessagingPlatform.framework/UserMessagingPlatform | DYLIB | UserMessagingPlatform.framework/UserMessagingPlatform | none | 0 |

- Runner, GMA linked in statically? `nm -m Runner | grep -c -i GADMobileAds` = 14; `strings -a Runner | grep -c GADMobileAds` = 15
- Runner load commands, AdSupport / ATT (weak or not):

```
LC_LOAD_DYLIB /System/Library/Frameworks/AdSupport.framework/AdSupport
```

### Strings in Runner (for C5 of T42.3, E1-d)

- `coarseLocationCollectionEnabled`: 2
- `setCoarseLocationCollectionEnabled:`: 1
- `publisherPrivacyPersonalizationState`: 3
- `GADApplicationIdentifier`: 2
- `GoogleAppMeasurementIdentitySupport`: 2
- `GoogleAdsOnDeviceConversion`: 6

### Privacy manifests in the bundle (E1-b)

- `Firebase_FirebaseABTesting.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `Firebase_FirebaseCore.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["UserDefaults:CA92.1"]}
- `Firebase_FirebaseCoreExtension.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `Firebase_FirebaseCoreInternal.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["UserDefaults:1C8F.1"]}
- `Firebase_FirebaseCrashlytics.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":["CrashData(linked=false,tracking=false)","OtherDiagnosticData(linked=false,tracking=false)"],"api":["UserDefaults:CA92.1"]}
- `Firebase_FirebaseInstallations.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":["OtherDiagnosticData(linked=false,tracking=false)"],"api":[]}
- `Firebase_FirebaseRemoteConfig.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":["OtherDiagnosticData(linked=false,tracking=false)"],"api":["UserDefaults:1C8F.1"]}
- `Frameworks/Flutter.framework/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["FileTimestamp:0A2A.1,C617.1","SystemBootTime:35F9.1"]}
- `Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy`: {"tracking":null,"domains":null,"collected":["OtherDiagnosticData(linked=false,tracking=false)","CoarseLocation(linked=true,tracking=false)","PerformanceData(linked=false,tracking=false)","CrashData(linked=false,tracking=false)","AdvertisingData(linked=true,tracking=false)","ProductInteraction(linked=true,tracking=false)","DeviceID(linked=true,tracking=true)"],"api":["SystemBootTime:35F9.1","UserDefaults:CA92.1","DiskSpace:E174.1"]}
- `Frameworks/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy`: {"tracking":null,"domains":null,"collected":["CoarseLocation(linked=false,tracking=false)","PerformanceData(linked=false,tracking=false)","ProductInteraction(linked=false,tracking=false)"],"api":["UserDefaults:CA92.1"]}
- `GoogleDataTransport_GoogleDataTransport.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":["OtherDiagnosticData(linked=false,tracking=false)"],"api":[]}
- `GoogleUtilities_GoogleUtilities-AppDelegateSwizzler.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `GoogleUtilities_GoogleUtilities-Environment.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["UserDefaults:C56D.1"]}
- `GoogleUtilities_GoogleUtilities-Logger.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `GoogleUtilities_GoogleUtilities-MethodSwizzler.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `GoogleUtilities_GoogleUtilities-Network.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["FileTimestamp:C617.1"]}
- `GoogleUtilities_GoogleUtilities-NSData.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `GoogleUtilities_GoogleUtilities-Reachability.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `GoogleUtilities_GoogleUtilities-UserDefaults.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["UserDefaults:1C8F.1,C56D.1"]}
- `nanopb_nanopb.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `package_info_plus_package_info_plus.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":["ProductInteraction(linked=false,tracking=false)","CrashData(linked=false,tracking=false)","OtherDiagnosticData(linked=false,tracking=false)","DeviceID(linked=false,tracking=false)"],"api":["UserDefaults:CA92.1","SystemBootTime:35F9.1","FileTimestamp:C617.1"]}
- `Promises_FBLPromises.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `shared_preferences_foundation_shared_preferences_foundation.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":["UserDefaults:1C8F.1"]}
- `url_launcher_ios_url_launcher_ios.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}
- `webview_flutter_wkwebview_webview_flutter_wkwebview.bundle/PrivacyInfo.xcprivacy`: {"tracking":false,"domains":[],"collected":[],"api":[]}

Manifests of the GMA/UMP SwiftPM artifacts (not necessarily embedded; a static xcframework's manifest may not be copied):

- `Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/swift-package-manager-google-mobile-ads/GoogleMobileAds/GoogleMobileAds.xcframework/ios-arm64/GoogleMobileAds.framework/PrivacyInfo.xcprivacy`: {"tracking":null,"domains":null,"collected":["OtherDiagnosticData(linked=false,tracking=false)","CoarseLocation(linked=true,tracking=false)","PerformanceData(linked=false,tracking=false)","CrashData(linked=false,tracking=false)","AdvertisingData(linked=true,tracking=false)","ProductInteraction(linked=true,tracking=false)","DeviceID(linked=true,tracking=true)"],"api":["SystemBootTime:35F9.1","UserDefaults:CA92.1","DiskSpace:E174.1"]}
- `Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/swift-package-manager-google-user-messaging-platform/UserMessagingPlatform/UserMessagingPlatform.xcframework/ios-arm64/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy`: {"tracking":null,"domains":null,"collected":["CoarseLocation(linked=false,tracking=false)","PerformanceData(linked=false,tracking=false)","ProductInteraction(linked=false,tracking=false)"],"api":["UserDefaults:CA92.1"]}
- `ios/../build/ios/SourcePackages/artifacts/swift-package-manager-google-mobile-ads/GoogleMobileAds/GoogleMobileAds.xcframework/ios-arm64/GoogleMobileAds.framework/PrivacyInfo.xcprivacy`: {"tracking":null,"domains":null,"collected":["OtherDiagnosticData(linked=false,tracking=false)","CoarseLocation(linked=true,tracking=false)","PerformanceData(linked=false,tracking=false)","CrashData(linked=false,tracking=false)","AdvertisingData(linked=true,tracking=false)","ProductInteraction(linked=true,tracking=false)","DeviceID(linked=true,tracking=true)"],"api":["SystemBootTime:35F9.1","UserDefaults:CA92.1","DiskSpace:E174.1"]}
- `ios/../build/ios/SourcePackages/artifacts/swift-package-manager-google-user-messaging-platform/UserMessagingPlatform/UserMessagingPlatform.xcframework/ios-arm64/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy`: {"tracking":null,"domains":null,"collected":["CoarseLocation(linked=false,tracking=false)","PerformanceData(linked=false,tracking=false)","ProductInteraction(linked=false,tracking=false)"],"api":["UserDefaults:CA92.1"]}

### SwiftPM pins (E1-d, E1-g)

- `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
  - firebase-ios-sdk 13.1.1 (dc6dfd442b1f)
  - googleappmeasurement 13.0.1 (1a3546fb9189)
  - swift-package-manager-google-mobile-ads 13.12.0 (f6308a186913)
  - swift-package-manager-google-user-messaging-platform 3.1.0 (13b248eaa73b)
- `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
  - firebase-ios-sdk 13.1.1 (dc6dfd442b1f)
  - googleappmeasurement 13.0.1 (1a3546fb9189)
  - swift-package-manager-google-mobile-ads 13.12.0 (f6308a186913)
  - swift-package-manager-google-user-messaging-platform 3.1.0 (13b248eaa73b)

### Firebase IDFA frameworks (E1-g)

- embedded GoogleAppMeasurementIdentitySupport / GoogleAdsOnDeviceConversion / FirebaseAnalytics(IDFA): 
- SwiftPM checkouts/artifacts with IdentitySupport or OnDeviceConversion: Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion/GoogleAdsOnDeviceConversion.xcframework Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/extract/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/extract/googleappmeasurement/GoogleAppMeasurementIdentitySupport Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/googleappmeasurement/GoogleAppMeasurementIdentitySupport Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/googleappmeasurement/GoogleAppMeasurementIdentitySupport/GoogleAppMeasurementIdentitySupport.xcframework

SwiftPM checkouts actually used (DerivedData workspace-state.json):

- googleappmeasurement 13.0.1
- swift-package-manager-google-mobile-ads 13.12.0
- swift-package-manager-google-user-messaging-platform 3.1.0
