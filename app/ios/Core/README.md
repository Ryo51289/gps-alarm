# NapStopCore — Trip Engine (Swift)

Swift port of the NapStop Trip Engine (spec: `docs/specs/T13.md`; behaviour: `docs/specs/T10.md` + `docs/specs/T12.md` §5).
Module `Trip` is a pure reducer written with the Swift standard library only (no Foundation), Swift 6 language mode,
value types only. The Kotlin engine (`app/android/core-trip`, T12) is the reference; both must produce byte-identical
P05 transcripts (`fixtures/p05/manifest.json`).

```
Package.swift                   NapStopCore, product `Trip`, test target `TripTests`
Sources/Trip/                   engine (T10 §2–§7): TripEngine, planners, MiniJson, SnapshotCodec, Redaction
Tests/TripTests/Support/        paths, bits, SplitMix64, SHA-256 (FIPS 180-4), synthetic geometry, EngineDriver, KWorld (Kotlin test world)
Tests/TripTests/Fixture/        GPX scanner, expect.json model (must-understand), anchors, ISO time
Tests/TripTests/Harness/        CaseRunner (T12 §8.3), OsSim (§8.4), Checks (I4 T10.5 + urgent shifts), GapProbe (U116/U117),
                                RestoreEquivalence (I8), KillSweep, Transcript (§9)
Tests/TripTests/Unit/           U01–U118 + T12 extra cases + S01–S14; Kotlin tester ports TesterT131 (T121), TesterT132 (T122),
                                TesterT132Overshoot (T122 O1–O4) writing the same <report>/unit/*.txt as Kotlin
Tests/TripTests/Trace/          TraceSuite (TR01–TR35, TR37, P01–P04, P06–P08), NegativeSweepTests (TR36, TR37-neg), DozeModelTests (TR39),
                                P05ManifestTests (P05, S15, S16), FixtureMainRuns (T10.5 urgent shifts, GPS-gap chord), IdCoverageTests
scripts/test-wsl.sh             run the tests in WSL
scripts/p05-diff.sh             Kotlin ↔ Swift transcript diff (Git Bash)
```

## Running

WSL (Ubuntu, Swift 6.4.1 at `~/opt/swift-6.4.1/usr/bin`), from Git Bash at the repo root:

```bash
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -e bash /mnt/d/work/gps-alarm/app/ios/Core/scripts/test-wsl.sh              # all, release
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -e bash /mnt/d/work/gps-alarm/app/ios/Core/scripts/test-wsl.sh --filter TraceSuite
```

The script runs `swift test -c release --enable-testable-imports --scratch-path ~/.cache/napstop/core-build`, so no
`.build` is written into the repository (drvfs is slow and locks files). Environment:

| Variable | Meaning |
|---|---|
| `NAPSTOP_SWIFT_BIN` | toolchain `bin` directory (default `~/opt/swift-6.4.1/usr/bin`) |
| `NAPSTOP_SCRATCH` | build directory (default `~/.cache/napstop/core-build`) |
| `NAPSTOP_CONFIG` | `release` (default) or `debug` |
| `NAPSTOP_FIXTURES_DIR` | `fixtures/traces` (default: found from `#filePath`) |
| `NAPSTOP_REPORT_DIR` | reports (`killsweep/summary.md`, `killsweep.json`, `trace/summary.md`, `p05-mismatch/`); default `$NAPSTOP_SCRATCH/napstop-report` in the script, `<package>/.build/napstop-report` otherwise |
| `NAPSTOP_P05_DUMP` | write all 295 transcripts (`<run, "/"→"__">.jsonl`) to this directory; never `fixtures/p05` |
| `NAPSTOP_P05_DIAG=1` | with the dump, also write `<run>.diag.jsonl` (Doubles as raw-bit hex, T12 §9.5) |

macOS (Xcode 26+, i.e. Swift ≥ 6.2 — needed for the exit test of U01): `cd app/ios/Core && swift test -c release --enable-testable-imports`.
CI-style build: `swift build -c release --build-tests -Xswiftc -enable-testing -Xswiftc -warnings-as-errors`, then
`swift test -c release -Xswiftc -enable-testing -Xswiftc -warnings-as-errors` (same flags, so the test step reuses the build).

Warnings check: `swift build --build-tests -Xswiftc -warnings-as-errors` (`--enable-testable-imports` is a `swift test` flag only).

## Determinism rules (T13 §5)

- Only `+ − * /`, `.squareRoot()`, `.rounded(.down)`, comparisons and `TMath.*`. No libm, no FMA (`addingProduct`/`fma`),
  no stdlib `min`/`max`, no `Dictionary`/`Set`/random/clock. Checked by `SourceScanTests` (U44).
- Double → integer only through `TMath.floorMs`/`roundHalfUp` and the Kotlin-compatible saturating conversions
  (`kotlinToLong`/`kotlinToInt`: NaN → 0, saturate; Kotlin `Int` is 32 bit).
- Input domain (contract with T17 and the harness): every `…Ms` in `[0, 2^53)`, parameters within T10 §5. Inside this
  domain no `Int64` operation overflows; outside it Swift traps where Kotlin would wrap (not part of P05).
- JSON: own strict RFC 8259 parser (`MiniJson`), numbers keep their lexeme, duplicate keys keep the last value at the first
  position, nesting deeper than 64 is a syntax error.

## P05

`P05ManifestTests` generates the 295 transcripts, compares the run set, line counts and SHA-256 with
`fixtures/p05/manifest.json` (written by Kotlin, T12) and the 3 samples byte for byte. Mismatching runs are written to
`<reportDir>/p05-mismatch/`. To hunt a difference: `app/ios/Core/scripts/p05-diff.sh [run …]` (Git Bash).
