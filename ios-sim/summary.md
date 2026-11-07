## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-07 10:18:32.764.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.027 (0.030) seconds
Test Suite 'RunnerTests' passed at 2026-11-07 10:18:32.766.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-07 10:18:32.897.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.050 (0.131) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-07 10:18:37.220.
	 Executed 6 tests, with 0 failures (0 unexpected) in 4.318 (4.322) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-07 10:18:37.235.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.014 (0.015) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-07 10:18:37.299.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.062 (0.064) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-07 10:18:37.299.
	 Executed 21 tests, with 0 failures (0 unexpected) in 4.472 (4.566) seconds
Test Suite 'All tests' passed at 2026-11-07 10:18:37.299.
	 Executed 21 tests, with 0 failures (0 unexpected) in 4.472 (4.567) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 334s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 334s |
| integration_test/map_ios_test.dart | pass | group 1, 334s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 334s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 334s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 334s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 101s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
