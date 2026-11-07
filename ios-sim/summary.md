## ios-sim

- status: failure
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: failure
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-07 05:58:08.265.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.024 (0.029) seconds
Test Suite 'RunnerTests' passed at 2026-11-07 05:58:08.267.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-07 05:58:08.300.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.030 (0.033) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-07 05:58:11.870.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.525 (3.570) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-07 05:58:11.876.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.005 (0.006) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-07 05:58:11.917.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.038 (0.041) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-07 05:58:11.932.
	 Executed 21 tests, with 0 failures (0 unexpected) in 3.623 (3.696) seconds
Test Suite 'All tests' passed at 2026-11-07 05:58:11.932.
	 Executed 21 tests, with 0 failures (0 unexpected) in 3.623 (3.698) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 247s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 247s |
| integration_test/map_ios_test.dart | fail | group 1, 247s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 247s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 247s |
| integration_test/t28_3_ios_ui_test.dart | fail | group 1, 247s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 49s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
