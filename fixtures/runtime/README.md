# fixtures/runtime

Runtime-level parity tables shared by the Android (`:core-runtime`) and iOS (`NapStopCore/TripRuntime`) trip runtimes
(spec `docs/specs/T17.md`, ITR30p). **Generated, do not edit by hand.**

| File | Written by | Read by |
|---|---|---|
| `first-alarms.json` | `app/android/core-runtime/src/test/kotlin/app/napstop/core/trip/runtime/RuntimeFirstAlarmExportTest.kt` | `app/ios/Core/Tests/TripRuntimeTests/Trace/RuntimeTraceTests.swift` (ITR30p) |

## `first-alarms.json`

JSON array, one object per L30 case (the six base traces of `fixtures/traces`, cases with `status == "final"` and none of
`kill`, `relaunch`, `osDismiss`, `params`, `battery`, `actions`, `killSweep`), in trace then case order:

| Key | Type | Meaning |
|---|---|---|
| `trace` | string | trace id (`<trace>.expect.json`) |
| `case` | string | case id inside the trace |
| `reason` | string or null | `AlarmReason` name of the first `Alarm` event the runtime published; null = no alarm |
| `atMsRel` | integer or null | trip-clock `atMs` of that event minus the GPX start (ms from the trace start) |

Key order inside an object is not significant. The Swift side must give the same `reason` and `|atMsRel| ≤ 1 000 ms`
apart (the Kotlin `TraceRun` advances the clock in steps of ≤ 1 s).

Regenerate after an intended behaviour change: delete the file, run
`cd app/android && ./gradlew :core-runtime:test --tests 'app.napstop.core.trip.runtime.RuntimeFirstAlarmExportTest' --rerun`
twice (the first run writes the file and fails once).
