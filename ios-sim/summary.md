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
