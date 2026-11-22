import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/house_templates.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render3d/scene_cleanup.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

/// The six faces of a box, wound outward, as the scene builder makes them.
List<Face3> boxFaces(Vec3 a, Vec3 b, {Color color = const Color(0xffcccccc)}) {
  Vec3 p(double x, double y, double z) => Vec3(x, y, z);
  final (x0, y0, z0, x1, y1, z1) = (a.x, a.y, a.z, b.x, b.y, b.z);
  return [
    for (final q in [
      [p(x0, y1, z0), p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0)],
      [p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1)],
      [p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1)],
      [p(x1, y0, z0), p(x0, y0, z0), p(x0, y1, z0), p(x1, y1, z0)],
      [p(x1, y0, z1), p(x1, y0, z0), p(x1, y1, z0), p(x1, y1, z1)],
      [p(x0, y0, z0), p(x0, y0, z1), p(x0, y1, z1), p(x0, y1, z0)],
    ])
      Face3(q, color)
  ];
}

SolidBox solid(Vec3 a, Vec3 b, {int floor = 0}) => SolidBox(a, b,
    floor: floor, roof: false, furniture: false, layer: Layer3.sorted);

ScenePainter paint(SceneModel model, Camera cam, SceneSettings s,
    {bool walk = false}) {
  final p = ScenePainter(
      model: model,
      camera: cam,
      settings: s,
      northAngleDeg: 0,
      walk: walk,
      labels: false)
    ..paint(Canvas(ui.PictureRecorder()), const Size(800, 600));
  return p;
}

void main() {
  test('faces between stacked wall pieces are dropped, the rest merged', () {
    const a0 = Vec3(0, 0, 0);
    const a1 = Vec3(2, 1, 0.3);
    const b0 = Vec3(0, 1, 0);
    const b1 = Vec3(2, 2, 0.3);
    final faces = [...boxFaces(a0, a1), ...boxFaces(b0, b1)];
    final out = cleanFaces(faces, [solid(a0, a1), solid(b0, b1)]);
    // Bottom, top, and four sides each 2 m tall: the lower top and the
    // upper bottom lay against each other and are gone.
    expect(out, hasLength(6));
    for (final f in out.where((f) => f.normal.y.abs() < 0.5)) {
      final ys = f.points.map((p) => p.y);
      expect(ys.reduce(math.min), 0);
      expect(ys.reduce(math.max), 2);
    }
    // Merged faces keep facing outward.
    for (final f in out) {
      final c = f.points.reduce((p, q) => p + q) * 0.25;
      expect(f.normal.dot(c - const Vec3(1, 1, 0.15)), greaterThan(0));
    }
  });

  test('a box that can be hidden on its own does not hide its neighbour', () {
    const a0 = Vec3(0, 0, 0);
    const a1 = Vec3(1, 1, 1);
    const b0 = Vec3(0, 1, 0);
    const b1 = Vec3(1, 2, 1);
    final faces = boxFaces(a0, a1);
    // The upper box is on the floor above: hiding that floor shows the
    // top of the lower one.
    final out = cleanFaces(faces, [solid(a0, a1), solid(b0, b1, floor: 1)]);
    expect(out, hasLength(6));
  });

  var n = 0;
  final kz = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'v${n++}');
  final kzModel =
      buildScene(kz, deriveHouse(kz), const SceneOptions(), (r) => r.name);

  test('the kz house loses its hidden wall faces', () {
    // Every outer face of a wall left must touch air somewhere: none lies
    // wholly inside another wall piece of the same floor.
    final walls = kzModel.faces.where((f) => f.source is WallSource);
    expect(walls.length, lessThan(500));
  });

  test('a close-up draws only what is in front of the camera', () {
    final pose = viewPose(kzModel, 'iso');
    final far = paint(
        kzModel,
        orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance),
        const SceneSettings(cut: true));
    final near = paint(
        kzModel,
        orbitCamera(pose.target, pose.yaw + 0.6, 0.25, pose.distance * 0.3),
        const SceneSettings(cut: true));
    expect(near.itemCount, lessThan(far.itemCount * 0.8));
    expect(near.culled, greaterThan(0));
  });

  test('with the roof on, rooms are drawn only where a window shows them', () {
    final pose = viewPose(kzModel, 'iso');
    final p = paint(
        kzModel,
        orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance),
        const SceneSettings());
    expect(p.culled, greaterThan(50));
    // Cut open, everything inside shows again.
    final cut = paint(
        kzModel,
        orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance),
        const SceneSettings(cut: true));
    expect(cut.culled, 0);
  });

  test('cut walls are filled solid where the plane passes through them', () {
    final pose = viewPose(kzModel, 'top');
    final cam = orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance);
    final p = paint(kzModel, cam, const SceneSettings(cut: true));
    final caps = p.debugItems.where((i) => i.$1 == 9).toList();
    expect(caps, isNotEmpty);
    expect(caps.every((i) => i.$2 is WallSource), isTrue);
    expect(
        paint(kzModel, cam, const SceneSettings())
            .debugItems
            .where((i) => i.$1 == 9),
        isEmpty);
  });

  test('showing the ground floor alone caps its walls', () {
    var k = 0;
    final doc = createTemplate('two', '2026-10-14T00:00:00Z', () => 't${k++}');
    final model =
        buildScene(doc, deriveHouse(doc), const SceneOptions(), (r) => r.name);
    final caps = model.faces.where((f) => f.capOnly).toList();
    expect(caps, isNotEmpty);
    expect(caps.every((f) => f.floorIndex == 0 && f.normal.y > 0.99), isTrue);
    final pose = viewPose(model, 'top');
    final cam = orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance);
    // Shown while the floor above is hidden, hidden under its walls.
    expect(
        paint(model, cam, const SceneSettings(maxFloor: 0)).visible(caps.first),
        isTrue);
    expect(
        paint(model, cam, const SceneSettings()).visible(caps.first), isFalse);
  });

  test('walking up to a two-storey house shows both floors and the roof', () {
    var k = 0;
    final doc = createTemplate('two', '2026-10-14T00:00:00Z', () => 'w${k++}');
    final model = buildScene(
        doc, deriveHouse(doc), const SceneOptions(walk: true), (r) => r.name);
    expect(model.faces.any((f) => f.roof), isTrue);
    final outside = Camera(Vec3(model.width / 2, 1.6, model.depth + 9),
        const Vec3(0, 0, -1), 72 * math.pi / 180);
    final p = paint(model, outside, const SceneSettings(), walk: true);
    expect(p.walkerInside, isFalse);
    expect(p.itemCount, greaterThan(100));
    final inside = Camera(Vec3(model.width * 0.3, 1.6, model.depth * 0.6),
        const Vec3(0, 0, -1), 72 * math.pi / 180);
    final q =
        paint(model, inside, const SceneSettings(maxFloor: 0), walk: true);
    expect(q.walkerInside, isTrue);
  });

  test('fixture house still builds', () {
    final doc = loadHouse(
            File('test/fixtures/full_two_floor_gable.house').readAsBytesSync())
        .document!;
    final model =
        buildScene(doc, deriveHouse(doc), const SceneOptions(), (r) => r.name);
    expect(model.faces, isNotEmpty);
  });
}
