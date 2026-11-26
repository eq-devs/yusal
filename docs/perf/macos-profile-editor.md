# Editor frames, macOS profile build, before and after

`flutter drive --profile -d macos --driver=test_driver/perf_driver.dart
--target=integration_test/editor_perf_test.dart`, Kazakh template, on the
same Mac on 2026-11-26, baseline `0f78537` (a worktree) and the branch.
The Mac was under load (load average 6 to 13 from other work), so runs
differ by up to half a millisecond; two runs of the branch are shown.
Milliseconds per frame.

| Scenario | Measure | Baseline | Branch run 1 | Branch run 2 |
| --- | --- | --- | --- | --- |
| Whole editor rebuild | UI p50 | 1.62 | 1.16 | 1.34 |
| | UI p90 | 1.76 | 1.38 | 1.55 |
| Pinch zoom | UI p50 | 0.93 | 0.80 | 0.81 |
| | UI p90 | 1.43 | 1.00 | 1.22 |
| | raster p90 | 2.48 | 1.75 | 2.07 |
| Pan | raster p50 | 2.07 | 1.38 | 2.14 |

What holds across runs: a rebuild of the editor costs about 0.3 to 0.5 ms
less on the UI thread (the plan no longer repaints when only the overlay
or the chrome changed), and zooming about 0.1 ms less at the median. Pan
raster is within the noise. No phone was attached, so nothing here is a
device measurement.
