## ios-sim

- status: failure
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: failure
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-07 09:38:34.380.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.016 (0.018) seconds
Test Suite 'RunnerTests' passed at 2026-11-07 09:38:34.382.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-07 09:38:34.428.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.010 (0.046) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-07 09:38:38.667.
	 Executed 6 tests, with 0 failures (0 unexpected) in 4.235 (4.238) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-07 09:38:38.676.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.008 (0.009) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-07 09:38:38.725.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.047 (0.049) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-07 09:38:38.769.
	 Executed 21 tests, with 0 failures (0 unexpected) in 4.318 (4.408) seconds
Test Suite 'All tests' passed at 2026-11-07 09:38:38.769.
	 Executed 21 tests, with 0 failures (0 unexpected) in 4.318 (4.409) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 471s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 471s |
| integration_test/map_ios_test.dart | fail | group 1, 471s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 471s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 471s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 471s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 233s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
