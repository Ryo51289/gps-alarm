## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=true (restored spm-plugins-macOS-26.6-17F113-474ea06b28e33f2ee42cfad3cd1322fcce3da77110b324cf9c8829b55e6feccf)
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-06 02:14:17.967.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.018 (0.022) seconds
Test Suite 'RunnerTests' passed at 2026-11-06 02:14:18.080.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-06 02:14:18.187.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.013 (0.107) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-06 02:14:22.145.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.953 (3.957) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-06 02:14:22.196.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.049 (0.051) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-06 02:14:22.219.
	 Executed 19 tests, with 0 failures (0 unexpected) in 4.034 (4.274) seconds
Test Suite 'All tests' passed at 2026-11-06 02:14:22.219.
	 Executed 19 tests, with 0 failures (0 unexpected) in 4.034 (4.277) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 310s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 310s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 310s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 310s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 310s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 136s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
