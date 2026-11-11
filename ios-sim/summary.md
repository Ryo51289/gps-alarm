## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'AddressSearchErrorCodeTests' passed at 2026-11-11 04:58:42.461.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'DeviceStatusStubTests' passed at 2026-11-11 04:58:43.776.
	 Executed 4 tests, with 0 failures (0 unexpected) in 1.313 (1.315) seconds
Test Suite 'RunnerTests' passed at 2026-11-11 04:58:43.837.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.060) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-11 04:58:43.847.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.009 (0.010) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-11 04:58:51.002.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.749 (3.752) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-11 04:58:51.483.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.480 (0.481) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-11 04:58:51.567.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.064 (0.083) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-11 04:58:51.567.
	 Executed 22 tests, with 0 failures (0 unexpected) in 5.619 (9.110) seconds
Test Suite 'All tests' passed at 2026-11-11 04:58:51.567.
	 Executed 22 tests, with 0 failures (0 unexpected) in 5.619 (9.111) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 329s |
| integration_test/firebase_ios_test.dart | pass | group 1, 329s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 329s |
| integration_test/map_ios_test.dart | pass | group 1, 329s |
| integration_test/address_search_ios_test.dart | pass | group 1, 329s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 329s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 329s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 329s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 78s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
