# CI iOS — ci/ios-all-t292

commit aaaf719d323d9c683afd95979dbff978d059753b · run https://github.com/Ryo51289/gps-alarm/actions/runs/42364981781 · 2026-11-07T10:52:38Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-07T10:41:04Z | 2026-11-07T10:41:05Z | 1 |
| swift-macos | success | 2026-11-07T10:41:13Z | 2026-11-07T10:47:46Z | 7 |
| ios-sim | success | 2026-11-07T10:41:12Z | 2026-11-07T10:52:08Z | 11 |
| ios-device | success | 2026-11-07T10:41:13Z | 2026-11-07T10:49:28Z | 9 |

## plan

- status: success (event push, ref ci/ios-all-t292)
- swift=true
- sim=true
- ipa=true
- diag=true
- telemetry=false

## swift-macos (NapStopCore, T13)

- status: success
- Xcode: Xcode 26.6; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

```
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.007) seconds
✔ Test run with 510 tests in 80 suites passed after 134.574 seconds.
```

# killsweep (NapStopCore, Swift)

## bus_hn_slow/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 52 | 0 | 0.0 | 0 | 0.0 | 271 | 68.2 | 60.3 | 60 |
| policy (pooled) | 52 | 0 | 0.0 | 0 | 0.0 | 247 | 53.5 | 44.4 | 47 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 52 | -131 | 823 | 1278 | 1426 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 52 | -106 | 825 | 1453 | 1559 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

## coach_gb_phuly_overshoot/distance_1000_killsweep (statsOnly)

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 39 | 11 | 28.2 | 619 | 464.8 | -619 | 49.1 | 44.5 | 32 |
| policy (pooled) | 1404 | 469 | 33.4 | 728 | 474.8 | -728 | 40.6 | 35.9 | 28 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 39 | -670 | -55 | 49 | 49 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, all:

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 360 | 2065 | 3044 | 5609 | far |
| 420 | 2005 | 3044 | 4077 | far |
| 480 | 1945 | 3044 | 3289 | far |
| 300 | 2125 | 3010 | 6528 | far |
| 240 | 2185 | 2976 | 6770 | far |
| 180 | 2245 | 2942 | 3491 | far |
| 120 | 2305 | 2902 | 3525 | far |
| 540 | 1885 | 2859 | 2827 | far |
| 60 | 2365 | 2842 | 3550 | far |
| 600 | 1825 | 2635 | 2481 | far |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 1404 | -700 | -58 | 28 | 53 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, policy (pooled):

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 540 | 1885 | 3153 | 5750 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |

## coach_md_tb/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 119 | 0 | 0.0 | 0 | 0.0 | 100 | 54.1 | 50.6 | 68 |
| policy (pooled) | 119 | 0 | 0.0 | 0 | 0.0 | 97 | 45.6 | 42.6 | 52 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | 36 | 670 | 1203 | 1296 |
| 1–2 h | 60 | 1389 | 1930 | 2369 | 2435 |
| 2–4 h | 1 | 2382 | 2382 | 2382 | 2382 |
| > 4 h | 0 | null | null | null | null |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | 33 | 672 | 1207 | 1300 |
| 1–2 h | 60 | 1392 | 1845 | 2306 | 2337 |
| 2–4 h | 1 | 2382 | 2382 | 2382 | 2382 |
| > 4 h | 0 | null | null | null | null |

## train_hn_dh/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 561 | 0 | 0.0 | 0 | 0.0 | 40 | 69.0 | 68.7 | 165 |
| policy (pooled) | 561 | 0 | 0.0 | 0 | 0.0 | 40 | 30.4 | 30.1 | 52 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | -50 | 223 | 501 | 596 |
| 1–2 h | 60 | 173 | 591 | 786 | 848 |
| 2–4 h | 120 | 1029 | 2089 | 4272 | 4935 |
| > 4 h | 323 | 3681 | 4878 | 7657 | 22720 |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | -50 | 217 | 493 | 590 |
| 1–2 h | 60 | 15 | 497 | 771 | 820 |
| 2–4 h | 120 | 1035 | 2037 | 4382 | 4974 |
| > 4 h | 323 | 3657 | 4778 | 7394 | 22720 |

## train_hn_dh/time_15_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 547 | 0 | 0.0 | 0 | 0.0 | 708 | 70.1 | 69.5 | 165 |
| policy (pooled) | 547 | 0 | 0.0 | 0 | 0.0 | 644 | 31.0 | 30.4 | 52 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 44 | -64 | 96 | 345 | 408 |
| 1–2 h | 60 | -30 | 371 | 577 | 641 |
| 2–4 h | 120 | 821 | 1880 | 4068 | 4733 |
| > 4 h | 323 | 3673 | 4795 | 7654 | 21910 |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 44 | -65 | 100 | 316 | 376 |
| 1–2 h | 60 | -194 | 288 | 562 | 611 |
| 2–4 h | 120 | 826 | 1829 | 4178 | 4772 |
| > 4 h | 323 | 3649 | 4727 | 7390 | 21910 |

## train_hn_dh_stopgap/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 543 | 0 | 0.0 | 0 | 0.0 | 1398 | 69.1 | 68.9 | 165 |
| policy (pooled) | 19523 | 0 | 0.0 | 0 | 0.0 | 1413 | 30.2 | 29.9 | 53 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 14 | 2604 | 2604 | 2668 | 2668 |
| 1–2 h | 60 | 1593 | 2818 | 3178 | 3268 |
| 2–4 h | 120 | 2174 | 3231 | 3925 | 4349 |
| > 4 h | 349 | 5215 | 6310 | 9123 | 24260 |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 479 | 2621 | 2651 | 2690 | 2730 |
| 1–2 h | 2160 | 1780 | 2883 | 3243 | 3360 |
| 2–4 h | 4320 | 2177 | 3239 | 3936 | 4368 |
| > 4 h | 12564 | 5205 | 6254 | 8840 | 24260 |

## train_longstop/distance_1000_killsweep (statsOnly)

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 75 | 6 | 8.0 | 114 | 90.0 | -114 | 53.0 | 50.6 | 62 |
| policy (pooled) | 2700 | 358 | 13.3 | 300 | 127.5 | -300 | 37.4 | 35.2 | 45 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | -71 | 107 | 924 | 996 |
| 1–2 h | 17 | -204 | 484 | 934 | 965 |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, all:

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 180 | 4460 | 4754 | 5869 | far |
| 240 | 4400 | 4754 | 8443 | far |
| 300 | 4340 | 4754 | 6731 | far |
| 360 | 4280 | 4754 | 5904 | far |
| 120 | 4520 | 4712 | 5943 | far |
| 60 | 4580 | 4652 | 5963 | far |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 2088 | -71 | 121 | 918 | 969 |
| 1–2 h | 612 | -312 | -157 | 739 | 894 |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, policy (pooled):

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |


## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-07 10:47:43.557.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.018 (0.020) seconds
Test Suite 'RunnerTests' passed at 2026-11-07 10:47:43.560.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-07 10:47:43.857.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.019 (0.296) seconds
2026-11-07 10:47:45.309548+0000 Runner[23197:80570] [[FirebaseAnalytics]] 13.1.1 - [FirebaseAnalytics][I-ACS025038] Failed to get Installation ID.: Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018), NSUnderlyingError=0x11f781ad0 {Error Domain=com.gul.keychain.ErrorDomain Code=0 "SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=SecItemCopyMatching (-34018)}}}
2026-11-07 10:47:45.352245+0000 Runner[23197:80570] [[FirebaseRemoteConfig]] 13.1.1 - [FirebaseRemoteConfig][I-RCN000073] Failed to get installations token. Error : Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018), NSUnderlyingError=0x11f781ad0 {Error Domain=com.gul.keychain.ErrorDomain Code=0 "SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=SecItemCopyMatching (-34018)}}}.
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-07 10:47:47.694.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.834 (3.837) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-07 10:47:47.698.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-07 10:47:47.732.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.032 (0.034) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-07 10:47:47.757.
	 Executed 21 tests, with 0 failures (0 unexpected) in 3.906 (4.220) seconds
Test Suite 'All tests' passed at 2026-11-07 10:47:47.758.
	 Executed 21 tests, with 0 failures (0 unexpected) in 3.906 (4.221) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 176s |
| integration_test/firebase_ios_test.dart | pass | group 1, 176s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 176s |
| integration_test/map_ios_test.dart | pass | group 1, 176s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 176s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 176s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 176s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 78s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```

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
- dSYM: 9 found (Flutter engine: Flutter.framework.dSYM)
  - App.framework.dSYM 25047C5D-2FD6-333A-F612-5CFC59554563 arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
  - Runner.app.dSYM 14CAD5B2-BFDF-35A9-A7F4-2200BB21E972 arm64
  - objective_c.framework.dSYM 33069127-DC8A-3A13-A158-09A0667C7315 arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
  - objective_c.framework.dSYM 33069127-DC8A-3A13-A158-09A0667C7315 arm64
  - sqlite3.framework.dSYM 2948CD94-FF5F-3FF1-B0FA-CAFF033A7BB3 arm64
  - Flutter.framework.dSYM 4C4C44BF-5555-3144-A1E0-9BF224E64ED2 arm64
  - Flutter.framework.dSYM 4C4C445B-5555-3144-A197-ADB2A127B333 arm64
- dSYM upload: ok (exit 0), 9 file(s), tool from SwiftPM checkout
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- SWIFT_ACTIVE_COMPILATION_CONDITIONS (Runner, Release) = NAPSTOP_DIAG
- ipa:  16M, artifact napstop-ios-unsigned (unsigned, 7 days; install with xtool install)
