// The engine baseline, with the 3D scene added to what engine_bench.dart
// measures. Runs quickly by default as a check that the benchmark still
// works; for numbers worth keeping, ask for more runs and a report file:
//
//   YUSAL_BENCH_RUNS=100 YUSAL_BENCH_OUT=build/baseline.json \
//     flutter test test/perf/baseline_test.dart
//
// `flutter test` runs unoptimised code, so read these against each other,
// not as what a phone does. The meter (--dart-define=YUSAL_PERF=true) shows
// the same names on a device.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/engine/render3d/bsp.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

import 'engine_bench.dart';

/// The 2D plan and the 3D scene of [s]: sizes, then milliseconds per call.
/// Painting is timed into a picture recorder, so it is the work done in
/// Dart (projection, ordering, building draw calls), not the rasteriser's.
Map<String, Map<String, num>> measureRender(UndoableDesignState s,
    {required int runs, required int warmUp}) {
  const size = Size(780, 520);
  final doc = composeDocument(benchMeta, s);
  final derived = deriveHouse(doc);
  double ms(void Function() body) => double.parse(
      meanMs((_) => body(), runs: runs, warmUp: warmUp).toStringAsFixed(3));
  SceneModel build() =>
      buildScene(doc, derived, const SceneOptions(), (r) => r.name);
  final model = build();
  final pose = viewPose(model, 'iso', aspect: size.width / size.height);
  final camera = orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance);
  ScenePainter scene({bool fast = false}) => ScenePainter(
      model: model,
      camera: camera,
      settings: const SceneSettings(),
      northAngleDeg: doc.footprint.northAngleDeg,
      walk: false,
      labels: true,
      fast: fast);
  void paint(CustomPainter painter) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
  }

  final floor = derived.floors.first;
  final plan = FloorPlanPainter(floor.base, const {}, const {},
      openings: floor.openings);
  final still = scene();
  paint(still);
  return {
    'size3d': {
      'faces': model.faces.length,
      'vertices': model.faces.fold<int>(0, (n, f) => n + f.points.length),
      'lines': model.lines.length,
      'bspFragments': model.bsp.fragmentCount,
      'drawnItems': still.itemCount,
      'culled': still.culled,
    },
    'ms3d': {
      'buildScene': ms(build),
      'bspBuild': ms(() => BspTree.build(model.faces)),
      'paintScene': ms(() => paint(still)),
      'paintSceneFast': ms(() => paint(scene(fast: true))),
    },
    'ms2d': {
      'paintPlan': ms(() => paint(plan)),
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final runs = int.tryParse(env['YUSAL_BENCH_RUNS'] ?? '') ?? 3;
  final warmUp = runs >= 20 ? 20 : 1;

  test('the baseline benchmark measures a typical and a large plan', () {
    final report = <String, Map<String, Object>>{};
    for (final (name, plan) in [
      ('typical', typicalPlan()),
      ('large', largePlan())
    ]) {
      report[name] = {
        ...measurePlan(plan, runs: runs, warmUp: warmUp),
        ...measureRender(plan, runs: runs, warmUp: warmUp),
      };
    }
    // ignore: avoid_print
    print(benchTable(report));
    final out = env['YUSAL_BENCH_OUT'];
    if (out != null) {
      File(out)
        ..createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }

    final typical = report['typical']!;
    final large = report['large']!;
    expect((typical['size']! as Map)['floors'], 2);
    expect((large['size']! as Map)['rooms'], 72);
    for (final plan in [typical, large]) {
      expect((plan['size3d']! as Map)['faces'], greaterThan(0));
      expect((plan['size3d']! as Map)['drawnItems'], greaterThan(0));
      for (final group in ['ms', 'ms3d', 'ms2d']) {
        for (final row in (plan[group]! as Map).entries) {
          expect(row.value, greaterThan(0), reason: '${row.key}');
        }
      }
    }
  });
}
