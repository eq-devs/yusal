// The floor finish runs on under doors, so no bare slab shows in a doorway.
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';

import 'perf/engine_bench.dart';

void main() {
  test('every doorway has floor under it, from the rooms beside it', () {
    final doc = composeDocument(benchMeta, typicalPlan());
    final derived = deriveHouse(doc);
    final scene = buildScene(doc, derived, const SceneOptions(), (r) => r.name);
    bool finish(Face3 f) =>
        f.source is RoomSource &&
        f.normal.y.abs() > 0.99 &&
        f.points.length == 4;
    var doors = 0;
    for (var i = 0; i < doc.floors.length; i++) {
      final g = derived.floors[i];
      final rects =
          g.base.roomGeometry.fold<int>(0, (n, r) => n + r.clearRects.length);
      var expected = 0;
      for (final p in g.openings.where((p) => p.status == 'ok')) {
        if (p.opening is WindowOpening || p.opening.sill != 0) continue;
        final (a, b) = roomsBeside(p, g.base);
        expected += a != null && b != null
            ? 2
            : (a ?? b) != null
                ? 1
                : 0;
        doors++;
      }
      final found =
          scene.faces.where((f) => f.floorIndex == i && finish(f)).length;
      expect(found, rects + expected, reason: 'floor $i');
    }
    expect(doors, greaterThan(0));
  });
}
