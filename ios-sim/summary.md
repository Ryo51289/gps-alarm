## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=true (restored spm-plugins-macOS-26.6-17F113-e3d21701ac37c2c57245a20857411a18e387e5f3b4967a996b8ca747189046ae)
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'AddressSearchErrorCodeTests' passed at 2026-11-10 07:11:17.774.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.007 (0.008) seconds
Test Suite 'DeviceStatusStubTests' passed at 2026-11-10 07:11:17.830.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.020 (0.056) seconds
Test Suite 'RunnerTests' passed at 2026-11-10 07:11:17.845.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.014) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-10 07:11:18.365.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.089 (0.520) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-10 07:11:22.463.
	 Executed 6 tests, with 0 failures (0 unexpected) in 4.093 (4.097) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-10 07:11:22.471.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.007 (0.008) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-10 07:11:22.541.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.067 (0.069) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-10 07:11:22.541.
	 Executed 22 tests, with 0 failures (0 unexpected) in 4.282 (4.775) seconds
Test Suite 'All tests' passed at 2026-11-10 07:11:22.541.
	 Executed 22 tests, with 0 failures (0 unexpected) in 4.282 (4.780) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 308s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 308s |
| integration_test/map_ios_test.dart | pass | group 1, 308s |
| integration_test/address_search_ios_test.dart | pass | group 1, 308s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 308s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 308s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 308s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 129s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
