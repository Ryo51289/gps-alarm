## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-07 04:32:32.521.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.011 (0.014) seconds
Test Suite 'RunnerTests' passed at 2026-11-07 04:32:32.522.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-07 04:32:33.434.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.909 (0.911) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-07 04:32:37.851.
	 Executed 6 tests, with 0 failures (0 unexpected) in 4.413 (4.416) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-07 04:32:37.861.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.009 (0.010) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-07 04:32:37.922.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.059 (0.061) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-07 04:32:37.923.
	 Executed 21 tests, with 0 failures (0 unexpected) in 5.403 (5.416) seconds
Test Suite 'All tests' passed at 2026-11-07 04:32:37.923.
	 Executed 21 tests, with 0 failures (0 unexpected) in 5.403 (5.417) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 344s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 344s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 344s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 344s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 344s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 150s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
