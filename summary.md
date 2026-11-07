# CI iOS — ci/ios-sim-t233b

commit 5cee70a25f0d1a37022d1bc7cef686af7b33443a · run https://github.com/Ryo51289/gps-alarm/actions/runs/42356576703 · 2026-11-07T08:53:46Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-07T08:41:59Z | 2026-11-07T08:42:00Z | 1 |
| swift-macos | skipped | — | — | — |
| ios-sim | success | 2026-11-07T08:42:06Z | 2026-11-07T08:53:20Z | 12 |
| ios-device | skipped | — | — | — |

## plan

- status: success (event push, ref ci/ios-sim-t233b)
- swift=false
- sim=true
- ipa=false
- diag=false

## ios-sim

- status: success
- Flutter: Flutter 3.47.8 • channel stable • https://github.com/flutter/flutter.git; Xcode: Xcode 26.6
- SwiftPM cache: hit=true (restored spm-plugins-macOS-26.6-17F113-e3d21701ac37c2c57245a20857411a18e387e5f3b4967a996b8ca747189046ae)
- Simulator: iPhone Air, iOS 26.5
- build: success; XCTest: success; integration: success
- simctl help location/privacy and grants: simctl-prepare.txt

### XCTest

```
Test Suite 'DeviceStatusStubTests' passed at 2026-11-07 08:48:47.900.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.012 (0.016) seconds
Test Suite 'RunnerTests' passed at 2026-11-07 08:48:47.901.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'T171PermissionTests' passed at 2026-11-07 08:48:47.917.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.004 (0.016) seconds
Test Suite 'T172AlarmHostApiTests' passed at 2026-11-07 08:48:51.404.
	 Executed 6 tests, with 0 failures (0 unexpected) in 3.483 (3.486) seconds
Test Suite 'T173NotificationRequestTests' passed at 2026-11-07 08:48:51.408.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
Test Suite 'T17MsgMapperTests' passed at 2026-11-07 08:48:51.438.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.028 (0.029) seconds
Test Suite 'RunnerTests.xctest' passed at 2026-11-07 08:48:51.438.
	 Executed 21 tests, with 0 failures (0 unexpected) in 3.532 (3.555) seconds
Test Suite 'All tests' passed at 2026-11-07 08:48:51.438.
	 Executed 21 tests, with 0 failures (0 unexpected) in 3.532 (3.556) seconds
** TEST SUCCEEDED **
```

### Integration tests

| file | result | time |
|---|---|---|
| integration_test/ios_smoke_test.dart | pass | group 1, 173s |
| integration_test/t18_1_ios_simulation_test.dart | pass | group 1, 173s |
| integration_test/map_ios_test.dart | pass | group 1, 173s |
| integration_test/t17_ios_runtime_test.dart | pass | group 1, 173s |
| integration_test/t17_2_ios_alarm_test.dart | pass | group 1, 173s |
| integration_test/t28_3_ios_ui_test.dart | pass | group 1, 173s |
| integration_test/t17_1_ios_permissions_test.dart | pass | group 2, 90s |

```
NAPSTOP_DIAG permissions: location=whileInUse precise=granted services=true notifications=notDetermined alarmKit=notDetermined
NAPSTOP_DIAG startTrip probe: accepted
```
