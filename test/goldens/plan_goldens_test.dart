// Pictures of the plan and the 3D view, compared pixel for pixel with the
// ones checked in. After a deliberate change of the drawing, look at the
// new pictures and write them again with
//   flutter test test/goldens --update-goldens
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

Widget _framed(CustomPainter painter) => Center(
    child: RepaintBoundary(
        child: SizedBox(
            width: 800,
            height: 600,
            child: CustomPaint(painter: painter, size: const Size(800, 600)))));

void main() {
  testWidgets('the Kazakh template plan', (t) async {
    var n = 0;
    final doc = createKazakhTemplate('2026-11-26T00:00:00Z', () => 'g${n++}');
    final floor = deriveHouse(doc).floors.first;
    await t.pumpWidget(_framed(FloorPlanPainter(floor.base,
        {for (final r in doc.floors.first.rooms) r.id: r.name}, const {},
        openings: floor.openings,
        stairs: floor.stairs,
        furniture: doc.extras.furniture
            .where((f) => f.floorId == doc.floors.first.id)
            .toList())));
    await expectLater(find.byType(RepaintBoundary).first,
        matchesGoldenFile('plan_kz_template.png'));
  });

  testWidgets('an L-shaped house with a hip roof', (t) async {
    var n = 0;
    final ctx = CommandContext(
        newId: () => 'g${n++}', now: () => '2026-11-26T00:00:00Z');
    var s = extractDesignState(createHouse(
        name: 'L',
        width: 12000,
        depth: 10000,
        columns: 1,
        rows: 1,
        initialRoom: true,
        timestamp: ctx.now(),
        newId: ctx.newId));
    for (final (kind, args) in [
      ('CutOutline', {'corner': 'tr', 'width': 5000, 'depth': 4000}),
      (
        'SetRoof',
        {
          'roof': {'type': 'hip', 'pitchDeg': 30, 'overhang': 500}
        }
      ),
    ]) {
      s = (executeCommand(s, DesignCommand(kind, args), ctx) as Applied)
          .newState;
    }
    final doc = composeDocument(
        Meta(name: 'L', createdAt: ctx.now(), updatedAt: ctx.now()), s);
    final model =
        buildScene(doc, deriveHouse(doc), const SceneOptions(), (r) => r.name);
    const yaw = 2.4;
    const pitch = 0.7;
    final c = model.center;
    final dir = Vec3(math.cos(pitch) * math.sin(yaw), math.sin(pitch),
        math.cos(pitch) * math.cos(yaw));
    final eye = c + dir * 26;
    await t.pumpWidget(_framed(ScenePainter(
        model: model,
        camera: Camera(eye, (c - eye).unit, 50 * math.pi / 180),
        settings: const SceneSettings(),
        northAngleDeg: 0,
        walk: false,
        labels: false)));
    await expectLater(find.byType(RepaintBoundary).first,
        matchesGoldenFile('house_l_hip_roof.png'));
  });
}
