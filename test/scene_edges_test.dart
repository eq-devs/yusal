// The edges the 3D view draws on a model: where its surface turns a
// corner or stops, and nowhere else.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/render3d/scene_edges.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

import 'perf/engine_bench.dart';

/// The six faces of a box, normals outward.
List<EdgeFace> box(Vec3 lo, Vec3 hi) {
  Vec3 p(int x, int y, int z) =>
      Vec3(x == 0 ? lo.x : hi.x, y == 0 ? lo.y : hi.y, z == 0 ? lo.z : hi.z);
  return [
    EdgeFace(
        [p(0, 0, 0), p(0, 0, 1), p(0, 1, 1), p(0, 1, 0)], const Vec3(-1, 0, 0)),
    EdgeFace(
        [p(1, 0, 0), p(1, 1, 0), p(1, 1, 1), p(1, 0, 1)], const Vec3(1, 0, 0)),
    EdgeFace(
        [p(0, 0, 0), p(1, 0, 0), p(1, 0, 1), p(0, 0, 1)], const Vec3(0, -1, 0)),
    EdgeFace(
        [p(0, 1, 0), p(0, 1, 1), p(1, 1, 1), p(1, 1, 0)], const Vec3(0, 1, 0)),
    EdgeFace(
        [p(0, 0, 0), p(0, 1, 0), p(1, 1, 0), p(1, 0, 0)], const Vec3(0, 0, -1)),
    EdgeFace(
        [p(0, 0, 1), p(1, 0, 1), p(1, 1, 1), p(0, 1, 1)], const Vec3(0, 0, 1)),
  ];
}

double total(Iterable<SceneEdge> edges) =>
    edges.fold(0.0, (sum, e) => sum + (e.b - e.a).length);

void main() {
  test('a box has its twelve edges', () {
    final edges = featureEdges(box(const Vec3(0, 0, 0), const Vec3(2, 3, 4)));
    expect(edges, hasLength(12));
    expect(edges.every((e) => !e.soft), isTrue);
    expect(total(edges), closeTo(4 * (2 + 3 + 4), 1e-9));
  });

  test('a flat face cut into pieces shows no line between the pieces', () {
    // One wall face as three pieces: two side by side, a third above both
    // whose lower edge spans the two.
    const n = Vec3(0, 0, 1);
    final edges = featureEdges([
      EdgeFace(
          const [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 1, 0), Vec3(0, 1, 0)],
          n),
      EdgeFace(
          const [Vec3(2, 0, 0), Vec3(5, 0, 0), Vec3(5, 1, 0), Vec3(2, 1, 0)],
          n),
      EdgeFace(
          const [Vec3(0, 1, 0), Vec3(5, 1, 0), Vec3(5, 3, 0), Vec3(0, 3, 0)],
          n),
    ]);
    // Only the outline of the whole: 5 by 3.
    expect(total(edges), closeTo(2 * (5 + 3), 1e-9));
    expect(edges, hasLength(4));
  });

  test('pieces of one surface that overlap show no line where they lap', () {
    // Wall pieces run on past each other where walls join.
    const n = Vec3(0, 0, 1);
    final edges = featureEdges([
      EdgeFace(const [
        Vec3(0, 0, 0),
        Vec3(2.2, 0, 0),
        Vec3(2.2, 3, 0),
        Vec3(0, 3, 0)
      ], n),
      EdgeFace(
          const [Vec3(2, 0, 0), Vec3(6, 0, 0), Vec3(6, 3, 0), Vec3(2, 3, 0)],
          n),
    ]);
    expect(total(edges), closeTo(2 * (6 + 3), 1e-9));
  });

  test('a partition that ends inside the outer wall draws nothing on it', () {
    // The outer face of a wall at z = 0 (seen from z > 0... its normal),
    // and the two sides of a partition behind it that reach that face.
    final faces = [
      EdgeFace(
          const [Vec3(0, 0, 0), Vec3(6, 0, 0), Vec3(6, 3, 0), Vec3(0, 3, 0)],
          const Vec3(0, 0, 1)),
      EdgeFace(
          const [Vec3(3, 0, 0), Vec3(3, 3, 0), Vec3(3, 3, -4), Vec3(3, 0, -4)],
          const Vec3(-1, 0, 0)),
      EdgeFace(const [
        Vec3(3.12, 0, 0),
        Vec3(3.12, 0, -4),
        Vec3(3.12, 3, -4),
        Vec3(3.12, 3, 0)
      ], const Vec3(1, 0, 0)),
    ];
    final edges = featureEdges(faces);
    bool onFace(SceneEdge e) =>
        e.a.z.abs() < 1e-9 && e.b.z.abs() < 1e-9 && e.a.x > 1 && e.a.x < 5;
    expect(edges.where(onFace), isEmpty);
  });

  test('a box standing on a floor keeps the line round its foot', () {
    final faces = [
      EdgeFace(const [
        Vec3(-5, 0, -5),
        Vec3(-5, 0, 5),
        Vec3(5, 0, 5),
        Vec3(5, 0, -5)
      ], const Vec3(0, 1, 0)),
      ...box(const Vec3(0, 0, 0), const Vec3(1, 1, 1)),
    ];
    final edges = featureEdges(faces);
    final foot = edges.where(
        (e) => e.a.y.abs() < 1e-9 && e.b.y.abs() < 1e-9 && e.a.x.abs() < 2);
    expect(total(foot), closeTo(4, 1e-9));
  });

  test('a slab between two storeys draws no line across the wall', () {
    const n = Vec3(0, 0, 1);
    final edges = featureEdges([
      EdgeFace(
          const [Vec3(0, 0, 0), Vec3(6, 0, 0), Vec3(6, 3, 0), Vec3(0, 3, 0)],
          n),
      EdgeFace(
          const [Vec3(0, 3, 0), Vec3(6, 3, 0), Vec3(6, 6, 0), Vec3(0, 6, 0)],
          n),
      // The slab's top, reaching the wall's outer face from inside.
      EdgeFace(
          const [Vec3(0, 3, 0), Vec3(0, 3, -4), Vec3(6, 3, -4), Vec3(6, 3, 0)],
          const Vec3(0, 1, 0)),
    ]);
    expect(
        edges.where((e) =>
            (e.a.y - 3).abs() < 1e-9 &&
            (e.b.y - 3).abs() < 1e-9 &&
            e.a.z.abs() < 1e-9 &&
            e.b.z.abs() < 1e-9),
        isEmpty);
  });

  test('the facets of a round column are soft, its ends hard', () {
    const sides = 24;
    final faces = <EdgeFace>[];
    Vec3 at(int i, double y) {
      final a = 2 * math.pi * i / sides;
      return Vec3(math.cos(a), y, math.sin(a));
    }

    for (var i = 0; i < sides; i++) {
      final a = 2 * math.pi * (i + 0.5) / sides;
      faces.add(EdgeFace([at(i, 0), at(i, 2), at(i + 1, 2), at(i + 1, 0)],
          Vec3(math.cos(a), 0, math.sin(a))));
    }
    final edges = featureEdges(faces);
    expect(edges.where((e) => e.soft), hasLength(sides));
    expect(edges.where((e) => !e.soft), hasLength(sides * 2));
  });

  test('the index finds the stretch of an outline that lies on an edge', () {
    final index =
        EdgeIndex(featureEdges(box(const Vec3(0, 0, 0), const Vec3(2, 3, 4))));
    // A piece of the box's bottom front edge, and a line across a face.
    final on = index.along(const Vec3(0.5, 0, 4), const Vec3(1.5, 0, 4));
    expect(on, hasLength(1));
    expect(on.single.$1, closeTo(0, 1e-9));
    expect(on.single.$2, closeTo(1, 1e-9));
    // Longer than the edge: only the part on it, as fractions.
    final part = index.along(const Vec3(-2, 0, 4), const Vec3(2, 0, 4));
    expect(part.single.$1, closeTo(0.5, 1e-9));
    expect(part.single.$2, closeTo(1, 1e-9));
    expect(index.along(const Vec3(0, 1, 4), const Vec3(2, 2, 4)), isEmpty);
  });

  group('on a house', () {
    final doc = composeDocument(benchMeta, typicalPlan());
    final model =
        buildScene(doc, deriveHouse(doc), const SceneOptions(), (r) => r.name);
    ScenePainter painter(SceneSettings settings) => ScenePainter(
        model: model,
        camera: Camera(const Vec3(30, 20, 30),
            (model.center - const Vec3(30, 20, 30)).unit, 0.9),
        settings: settings,
        northAngleDeg: 0,
        walk: false,
        labels: false);

    test('the outer walls carry no line but their outline and openings', () {
      final edges = painter(const SceneSettings()).edges(0);
      // A vertical line on an outer face that is neither a corner of the
      // house nor the side of an opening would be a wall piece showing.
      final openings = <double>{};
      for (final f in doc.floors) {
        for (final o
            in deriveHouse(doc).floors[doc.floors.indexOf(f)].openings) {
          openings.add(o.opening.width / 1000);
        }
      }
      for (final e in edges) {
        final vertical = (e.a.x - e.b.x).abs() < 1e-6 &&
            (e.a.z - e.b.z).abs() < 1e-6 &&
            (e.a.y - e.b.y).abs() > 2.6;
        if (!vertical) continue;
        final onFront =
            (e.a.z - model.depth).abs() < 1e-6 || e.a.z.abs() < 1e-6;
        if (!onFront) continue;
        // Full-height lines on the long faces: only at the two corners.
        expect(e.a.x < 1e-6 || (e.a.x - model.width).abs() < 1e-6, isTrue,
            reason: 'a line up the wall at x = ${e.a.x}');
      }
      expect(openings, isNotEmpty);
    });

    test('edges are kept between frames and redone when the view changes', () {
      final a = painter(const SceneSettings()).edges(0);
      final b = painter(const SceneSettings(hour: 15)).edges(0);
      expect(identical(a, b), isTrue);
      final noRoof = painter(const SceneSettings(roof: false)).edges(0);
      expect(identical(a, noRoof), isFalse);
      expect(noRoof.length, isNot(a.length));
    });

    test('walking and the foundation view draw no edges', () {
      expect(
          painter(const SceneSettings(foundation: true)).drawsEdges, isFalse);
      expect(painter(const SceneSettings(style: SceneStyle.plain)).drawsEdges,
          isFalse);
      expect(painter(const SceneSettings()).drawsEdges, isTrue);
    });

    test('a line drawing is paper with nothing lit', () {
      final p =
          painter(const SceneSettings(style: SceneStyle.lines, dark: true));
      expect(p.settings.night, isFalse);
      final wall = model.faces.firstWhere((f) => f.alpha >= 1);
      expect(p.shade(wall, wall.normal, 10, p.sun), ScenePainter.paper);
      final glass = model.faces.firstWhere((f) => f.alpha < 1);
      expect(p.faceAlpha(glass), lessThan(0.2));
    });

    test('a white model keeps its light and loses its colours', () {
      final p = painter(const SceneSettings(style: SceneStyle.white));
      final colours = <int>{};
      for (final f in model.faces.where((f) => f.alpha >= 1)) {
        colours.add(p.shade(f, const Vec3(0, 1, 0), 10, p.sun).toARGB32());
      }
      // One material under one light from one side: one colour.
      expect(colours, hasLength(1));
    });
  });
}
