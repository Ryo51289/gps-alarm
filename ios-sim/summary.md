## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=false 
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'AddressSearchErrorCodeTests' passed at 2026-11-11 07:02:24.853.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.009 (0.015) seconds
Test Suite 'DeviceStatusStubTests' passed at 2026-11-11 07:02:24.899.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.024 (0.046) seconds
Test Suite 'RunnerTests' passed at 2026-11-11 07:02:25.044.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.144) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-11 07:02:29.376.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.010 (4.332) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-11 07:02:33.879.
	 Executed 6 tests, with 0 failures (0 unexpected) in 4.498 (4.502) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-11 07:02:33.891.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.011 (0.012) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-11 07:02:33.949.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.055 (0.058) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-11 07:02:33.949.
	 Executed 22 tests, with 0 failures (0 unexpected) in 4.609 (9.112) seconds
Test Suite 'All tests' passed at 2026-11-11 07:02:33.949.
	 Executed 22 tests, with 0 failures (0 unexpected) in 4.609 (9.115) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 446s |
| integration_test/firebase_ios_test.dart | pass | group 1, 446s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 446s |
| integration_test/map_ios_test.dart | pass | group 1, 446s |
| integration_test/address_search_ios_test.dart | pass | group 1, 446s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 446s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 446s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 446s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 112s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
