# CI iOS — ci/ios-swift-t238c1b

commit 7072f2b3ac6a5aca8db3d8f45b65623dd1d4d859 · run https://github.com/Ryo51289/gps-alarm/actions/runs/43394109766 · 2026-11-13T08:41:24Z

| job | result | start (UTC) | end (UTC) | minutes |
|---|---|---|---|---|
| plan | success | 2026-11-13T08:33:18Z | 2026-11-13T08:33:20Z | 1 |
| swift-macos | success | 2026-11-13T08:33:31Z | 2026-11-13T08:41:08Z | 8 |
| ios-sim | skipped | — | — | — |
| ios-device | skipped | — | — | — |

## plan

- status: success (event push, ref ci/ios-swift-t238c1b)
- swift=true
- sim=false
- ipa=false
- diag=false
- telemetry=false

## swift-macos (NapStopCore, T13)

- status: success
- Xcode: Xcode 26.6; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

```
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.004) seconds
✔ Test run with 571 tests in 85 suites passed after 148.373 seconds.
```

# killsweep (NapStopCore, Swift)

## bus_hn_slow/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 52 | 0 | 0.0 | 0 | 0.0 | 271 | 68.2 | 60.3 | 60 |
| policy (pooled) | 52 | 0 | 0.0 | 0 | 0.0 | 247 | 53.5 | 44.4 | 47 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 52 | -131 | 823 | 1278 | 1426 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 52 | -106 | 825 | 1453 | 1559 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

## coach_gb_phuly_overshoot/distance_1000_killsweep (statsOnly)

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 39 | 11 | 28.2 | 619 | 464.8 | -619 | 49.1 | 44.5 | 32 |
| policy (pooled) | 1404 | 469 | 33.4 | 728 | 474.8 | -728 | 40.6 | 35.9 | 28 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 39 | -670 | -55 | 49 | 49 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, all:

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 360 | 2065 | 3044 | 5609 | far |
| 420 | 2005 | 3044 | 4077 | far |
| 480 | 1945 | 3044 | 3289 | far |
| 300 | 2125 | 3010 | 6528 | far |
| 240 | 2185 | 2976 | 6770 | far |
| 180 | 2245 | 2942 | 3491 | far |
| 120 | 2305 | 2902 | 3525 | far |
| 540 | 1885 | 2859 | 2827 | far |
| 60 | 2365 | 2842 | 3550 | far |
| 600 | 1825 | 2635 | 2481 | far |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 1404 | -700 | -58 | 28 | 53 |
| 1–2 h | 0 | null | null | null | null |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, policy (pooled):

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 540 | 1885 | 3153 | 5750 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |
| 480 | 1945 | 3130 | 7154 | far |

## coach_md_tb/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 119 | 0 | 0.0 | 0 | 0.0 | 100 | 54.1 | 50.6 | 68 |
| policy (pooled) | 119 | 0 | 0.0 | 0 | 0.0 | 97 | 45.6 | 42.6 | 52 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | 36 | 670 | 1203 | 1296 |
| 1–2 h | 60 | 1389 | 1930 | 2369 | 2435 |
| 2–4 h | 1 | 2382 | 2382 | 2382 | 2382 |
| > 4 h | 0 | null | null | null | null |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | 33 | 672 | 1207 | 1300 |
| 1–2 h | 60 | 1392 | 1845 | 2306 | 2337 |
| 2–4 h | 1 | 2382 | 2382 | 2382 | 2382 |
| > 4 h | 0 | null | null | null | null |

## train_hn_dh/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 561 | 0 | 0.0 | 0 | 0.0 | 40 | 69.0 | 68.7 | 165 |
| policy (pooled) | 561 | 0 | 0.0 | 0 | 0.0 | 40 | 30.4 | 30.1 | 52 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | -50 | 223 | 501 | 596 |
| 1–2 h | 60 | 173 | 591 | 786 | 848 |
| 2–4 h | 120 | 1029 | 2089 | 4272 | 4935 |
| > 4 h | 323 | 3681 | 4878 | 7657 | 22720 |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | -50 | 217 | 493 | 590 |
| 1–2 h | 60 | 15 | 497 | 771 | 820 |
| 2–4 h | 120 | 1035 | 2037 | 4382 | 4974 |
| > 4 h | 323 | 3657 | 4778 | 7394 | 22720 |

## train_hn_dh/time_15_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 547 | 0 | 0.0 | 0 | 0.0 | 708 | 70.1 | 69.5 | 165 |
| policy (pooled) | 547 | 0 | 0.0 | 0 | 0.0 | 644 | 31.0 | 30.4 | 52 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 44 | -64 | 96 | 345 | 408 |
| 1–2 h | 60 | -30 | 371 | 577 | 641 |
| 2–4 h | 120 | 821 | 1880 | 4068 | 4733 |
| > 4 h | 323 | 3673 | 4795 | 7654 | 21910 |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 44 | -65 | 100 | 316 | 376 |
| 1–2 h | 60 | -194 | 288 | 562 | 611 |
| 2–4 h | 120 | 826 | 1829 | 4178 | 4772 |
| > 4 h | 323 | 3649 | 4727 | 7390 | 21910 |

## train_hn_dh_stopgap/distance_1000_killsweep

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 543 | 0 | 0.0 | 0 | 0.0 | 1398 | 69.1 | 68.9 | 165 |
| policy (pooled) | 19523 | 0 | 0.0 | 0 | 0.0 | 1413 | 30.2 | 29.9 | 53 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 14 | 2604 | 2604 | 2668 | 2668 |
| 1–2 h | 60 | 1593 | 2818 | 3178 | 3268 |
| 2–4 h | 120 | 2174 | 3231 | 3925 | 4349 |
| > 4 h | 349 | 5215 | 6310 | 9123 | 24260 |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 479 | 2621 | 2651 | 2690 | 2730 |
| 1–2 h | 2160 | 1780 | 2883 | 3243 | 3360 |
| 2–4 h | 4320 | 2177 | 3239 | 3936 | 4368 |
| > 4 h | 12564 | 5205 | 6254 | 8840 | 24260 |

## train_longstop/distance_1000_killsweep (statsOnly)

| Mode | k | late | late % | late max s | late mean s | min margin s | FAC/h | FAC far/h | max FAC in 3600 s |
|---|---|---|---|---|---|---|---|---|---|
| all | 75 | 6 | 8.0 | 114 | 90.0 | -114 | 53.0 | 50.6 | 62 |
| policy (pooled) | 2700 | 358 | 13.3 | 300 | 127.5 | -300 | 37.4 | 35.2 | 45 |

Earliness `earlyFrom − fb` (s), all:

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 58 | -71 | 107 | 924 | 996 |
| 1–2 h | 17 | -204 | 484 | 934 | 965 |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, all:

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 180 | 4460 | 4754 | 5869 | far |
| 240 | 4400 | 4754 | 8443 | far |
| 300 | 4340 | 4754 | 6731 | far |
| 360 | 4280 | 4754 | 5904 | far |
| 120 | 4520 | 4712 | 5943 | far |
| 60 | 4580 | 4652 | 5963 | far |

Earliness `earlyFrom − fb` (s), policy (pooled):

| arrival − k | n | p10 | p50 | p90 | max |
|---|---|---|---|---|---|
| < 1 h | 2088 | -71 | 121 | 918 | 969 |
| 1–2 h | 612 | -312 | -157 | 739 | 894 |
| 2–4 h | 0 | null | null | null | null |
| > 4 h | 0 | null | null | null | null |

10 latest k, policy (pooled):

| k | arrival − k | fb | T at death | zone |
|---|---|---|---|---|
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |
| 480 | 4160 | 4940 | 12428 | far |

