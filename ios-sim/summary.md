## ios-sim

- status: failure
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: failure
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'AddressSearchErrorCodeTests' passed at 2026-11-11 03:21:38.465.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.008 (0.015) seconds
Test Suite 'DeviceStatusStubTests' passed at 2026-11-11 03:21:38.483.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.015 (0.019) seconds
Test Suite 'RunnerTests' passed at 2026-11-11 03:21:38.536.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.052) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-11 03:21:38.746.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.034 (0.210) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-11 03:21:50.362.
	 Executed 6 tests, with 0 failures (0 unexpected) in 11.606 (11.616) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-11 03:21:50.375.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.011 (0.012) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-11 03:21:50.453.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.076 (0.078) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-11 03:21:50.486.
	 Executed 22 tests, with 0 failures (0 unexpected) in 11.751 (12.036) seconds
Test Suite 'All tests' passed at 2026-11-11 03:21:50.487.
	 Executed 22 tests, with 0 failures (0 unexpected) in 11.751 (12.039) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 477s |
| integration_test/firebase_ios_test.dart | pass | group 1, 477s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 477s |
| integration_test/map_ios_test.dart | fail | group 1, 477s |
| integration_test/address_search_ios_test.dart | pass | group 1, 477s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 477s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 477s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 477s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 194s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
