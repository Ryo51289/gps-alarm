## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'AddressSearchErrorCodeTests' passed at 2026-11-11 04:54:37.856.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.003 (0.005) seconds
Test Suite 'DeviceStatusStubTests' passed at 2026-11-11 04:54:37.874.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.010 (0.018) seconds
Test Suite 'RunnerTests' passed at 2026-11-11 04:54:37.955.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.080) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-11 04:54:37.990.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.018 (0.034) seconds
2026-11-11 04:54:39.343139+0000 Runner[27753:94180] [[FirebaseRemoteConfig]] 13.1.1 - [FirebaseRemoteConfig][I-RCN000073] Failed to get installations token. Error : Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018), NSUnderlyingError=0x10442cb40 {Error Domain=com.gul.keychain.ErrorDomain Code=0 "SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=SecItemCopyMatching (-34018)}}}.
2026-11-11 04:54:39.358219+0000 Runner[27753:94180] [[FirebaseAnalytics]] 13.1.1 - [FirebaseAnalytics][I-ACS025038] Failed to get Installation ID.: Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=Underlying error: The operation couldn’t be completed. SecItemCopyMatching (-34018), NSUnderlyingError=0x10442cb40 {Error Domain=com.gul.keychain.ErrorDomain Code=0 "SecItemCopyMatching (-34018)" UserInfo={NSLocalizedFailureReason=SecItemCopyMatching (-34018)}}}
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-11 04:54:41.624.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.632 (3.634) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-11 04:54:41.629.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-11 04:54:41.659.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.028 (0.030) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-11 04:54:41.659.
	 Executed 22 tests, with 0 failures (0 unexpected) in 3.694 (3.808) seconds
Test Suite 'All tests' passed at 2026-11-11 04:54:41.660.
	 Executed 22 tests, with 0 failures (0 unexpected) in 3.694 (3.808) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 219s |
| integration_test/firebase_ios_test.dart | pass | group 1, 219s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 219s |
| integration_test/map_ios_test.dart | pass | group 1, 219s |
| integration_test/address_search_ios_test.dart | pass | group 1, 219s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 219s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 219s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 219s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 69s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
