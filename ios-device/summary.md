## ios-device

- status: success; build: success; diag: false
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
  - App.framework.dSYM 2F269CFC-A216-48C3-7229-F3211B60EDB1 arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
  - Runner.app.dSYM ED07F874-163A-3062-9D8F-26D0054B0C88 arm64
  - objective_c.framework.dSYM 2FC1775B-D563-32B8-BCF4-E1818E927541 arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
- dSYM upload: ok (exit 0), 5 file(s), tool from SwiftPM checkout
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- SWIFT_ACTIVE_COMPILATION_CONDITIONS (Runner, Release) = 
- ipa:  16M, artifact napstop-ios-unsigned (unsigned, 7 days; install with xtool install)

## E1 report (T42.1)

### Sizes (E1-f)

- ipa bytes: 16491307
- Runner.app KiB (du -sk): 40980
- Runner binary bytes: 9324168

```
   11948 KiB  Frameworks/App.framework
      40 KiB  Frameworks/FirebaseAnalytics.framework
   10244 KiB  Frameworks/Flutter.framework
      40 KiB  Frameworks/GoogleAppMeasurement.framework
     208 KiB  Frameworks/objective_c.framework
    1620 KiB  Frameworks/sqlite3.framework
       8 KiB  Firebase_FirebaseABTesting.bundle
       8 KiB  Firebase_FirebaseCore.bundle
       8 KiB  Firebase_FirebaseCoreExtension.bundle
       8 KiB  Firebase_FirebaseCoreInternal.bundle
       8 KiB  Firebase_FirebaseCrashlytics.bundle
       8 KiB  Firebase_FirebaseInstallations.bundle
       8 KiB  Firebase_FirebaseRemoteConfig.bundle
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
```

### Link type and AdSupport/ATT signals per binary (E1-a, E1-c)

| binary | type | otool -L (AdSupport|AppTrackingTransparency|GoogleMobileAds|UserMessagingPlatform) | nm -u (ASIdentifierManager|ATTrackingManager) | strings (ASIdentifierManager|ATTrackingManager) |
|---|---|---|---|---|
| Runner | EXECUTE | none | none | 0 |
| Frameworks/App.framework/App | DYLIB | none | none | 0 |
| Frameworks/FirebaseAnalytics.framework/FirebaseAnalytics | DYLIB | none | none | 0 |
| Frameworks/Flutter.framework/Flutter | DYLIB | none | none | 0 |
| Frameworks/GoogleAppMeasurement.framework/GoogleAppMeasurement | DYLIB | none | none | 0 |
| Frameworks/objective_c.framework/objective_c | DYLIB | none | none | 0 |
| Frameworks/sqlite3.framework/sqlite3 | DYLIB | none | none | 0 |

- Runner, GMA linked in statically? `nm -m Runner | grep -c -i GADMobileAds` = 0; `strings -a Runner | grep -c GADMobileAds` = 0
- Runner load commands, AdSupport / ATT (weak or not):

```
none
```

### Strings in Runner (for C5 of T42.3, E1-d)

- `coarseLocationCollectionEnabled`: 0
- `setCoarseLocationCollectionEnabled:`: 0
- `publisherPrivacyPersonalizationState`: 0
- `GADApplicationIdentifier`: 0
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

Manifests of the GMA/UMP SwiftPM artifacts (not necessarily embedded; a static xcframework's manifest may not be copied):

- none found

### SwiftPM pins (E1-d, E1-g)

- `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
  - firebase-ios-sdk 13.1.1 (dc6dfd442b1f)
  - googleappmeasurement 13.0.1 (1a3546fb9189)
- `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
  - firebase-ios-sdk 13.1.1 (dc6dfd442b1f)
  - googleappmeasurement 13.0.1 (1a3546fb9189)

### Firebase IDFA frameworks (E1-g)

- embedded GoogleAppMeasurementIdentitySupport / GoogleAdsOnDeviceConversion / FirebaseAnalytics(IDFA): 
- SwiftPM checkouts/artifacts with IdentitySupport or OnDeviceConversion: Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion/GoogleAdsOnDeviceConversion.xcframework Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/extract/google-ads-on-device-conversion-ios-sdk/GoogleAdsOnDeviceConversion Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/extract/googleappmeasurement/GoogleAppMeasurementIdentitySupport Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/googleappmeasurement/GoogleAppMeasurementIdentitySupport Runner-grkxkaoseoydyugxgzowkwppgssv/SourcePackages/artifacts/googleappmeasurement/GoogleAppMeasurementIdentitySupport/GoogleAppMeasurementIdentitySupport.xcframework

SwiftPM checkouts actually used (DerivedData workspace-state.json):

- googleappmeasurement 13.0.1
