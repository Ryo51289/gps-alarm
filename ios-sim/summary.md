## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'AddressSearchErrorCodeTests' passed at 2026-11-11 05:07:57.224.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.004 (0.005) seconds
Test Suite 'DeviceStatusStubTests' passed at 2026-11-11 05:07:57.232.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.006 (0.008) seconds
Test Suite 'RunnerTests' passed at 2026-11-11 05:07:57.233.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-11 05:07:58.059.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.824 (0.826) seconds
2026-11-11 05:08:00.909096+0000 Runner[54519:154529] [[FirebaseRemoteConfig]] 13.1.1 - [FirebaseRemoteConfig][I-RCN000073] Failed to get installations token. Error : Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018), NSUnderlyingError=0x11b7db0c0 {Error Domain=com.gul.keychain.ErrorDomain Code=0 "SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=SecItemCopyMatching (-34018)}}}.
2026-11-11 05:08:00.999959+0000 Runner[54519:154529] [[FirebaseAnalytics]] 13.1.1 - [FirebaseAnalytics][I-ACS025038] Failed to get Installation ID.: Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018), NSUnderlyingError=0x11b7db0c0 {Error Domain=com.gul.keychain.ErrorDomain Code=0 "SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=SecItemCopyMatching (-34018)}}}
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-11 05:08:02.172.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.984 (4.113) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-11 05:08:02.182.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.008 (0.009) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-11 05:08:02.257.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.052 (0.070) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-11 05:08:02.258.
	 Executed 22 tests, with 0 failures (0 unexpected) in 4.878 (5.039) seconds
Test Suite 'All tests' passed at 2026-11-11 05:08:02.259.
	 Executed 22 tests, with 0 failures (0 unexpected) in 4.878 (5.040) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 361s |
| integration_test/firebase_ios_test.dart | pass | group 1, 361s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 361s |
| integration_test/map_ios_test.dart | pass | group 1, 361s |
| integration_test/address_search_ios_test.dart | pass | group 1, 361s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 361s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 361s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 361s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 72s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
