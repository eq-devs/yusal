# Measuring the design engine

The engine reports what its own work costs, under fixed names. The numbers
are the baseline every later change to the engine is compared with.

## What is measured

| Name | What it is |
| --- | --- |
| `command.<Kind>` | one `executeCommand` call of that kind |
| `derive.floorBase` | the plan geometry of one floor, when it is not cached |
| `derive.house` | the geometry of the whole house, when it is not cached |
| `scene3d.build` | turning the derived house into the faces of the 3D scene |
| `scene3d.clean` | the part of `scene3d.build` that drops hidden faces and joins the ones that lie flush |
| `scene3d.bsp` | ordering those faces for drawing |
| `paint.plan2d` | one paint of the 2D plan |
| `paint.scene3d` | one paint of the 3D view |
| `scene3d.faces`, `.vertices`, `.bspFragments`, `.drawn`, `.culled` | the size of the scene, and how much of it the last frame drew |

The code is `lib/features/editor/engine/core/perf/engine_perf.dart`. In an
ordinary build measuring is off and `timed(name, work)` only calls `work`.

## On a device

```bash
flutter run --profile --dart-define=YUSAL_PERF=true
```

The editor then shows a meter in the bottom left corner. Each row is the
mean and the longest time in milliseconds and how many times it ran; the
first row is the frame's build and raster time over the last 120 frames,
and how many of them took longer than 16.7 ms. A tap copies the full report
as JSON; a long press starts the numbers again. The same names appear on
the DevTools timeline.

To record a baseline: open a project, long press the meter, drag a wall
for a few seconds, turn the 3D view, then tap the meter and keep the JSON
with the device's name and the date.

## On a computer

```bash
# The engine alone, compiled: closest to a release build.
dart compile exe test/perf/engine_bench.dart -o build/engine_bench
build/engine_bench build/engine.json

# The same plans with the 2D plan and the 3D scene added (unoptimised code).
YUSAL_BENCH_RUNS=100 YUSAL_BENCH_OUT=build/baseline.json \
  flutter test test/perf/baseline_test.dart
```

Both measure a typical plan (12 × 10 m, two floors, 16 rooms) and a large
one (30 × 24 m, two floors, 72 rooms). Read the two runs against earlier
runs on the same machine, not against a phone.
