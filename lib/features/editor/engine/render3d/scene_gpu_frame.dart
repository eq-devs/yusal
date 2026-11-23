import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yusal/features/editor/engine/core/geometry/source_ref.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';
import 'package:yusal/features/editor/engine/render3d/textures.dart';

/// Floats to a vertex: position, colour (alpha multiplied in), texture
/// coordinate.
const gpuVertexFloats = 9;

/// Triangles that share a texture, to be drawn in one call.
class GpuBatch {
  GpuBatch(this.vertices, this.count, {this.image, this.tiled = false});

  /// [count] vertices of [gpuVertexFloats] each, three to a triangle.
  final Float32List vertices;
  final int count;

  /// The textile these triangles show; null for plain faces.
  final ui.Image? image;
  final bool tiled;
}

/// One frame of the 3D view as the GPU draws it: the faces as triangles in
/// the house's own coordinates, already lit, and the camera as a matrix.
class GpuFrame {
  GpuFrame(this.mvp, this.opaque, this.translucent, this.faces,
      [this.picks = const [], this.edges]);

  /// The form's edges as thin strips, drawn over the solid faces and
  /// behind nothing that is nearer; null when the style draws none.
  final GpuBatch? edges;

  /// Column-major, from house coordinates to clip space with depth 0 to 1.
  final Float32List mvp;

  /// Drawn first, in any order, writing depth.
  final List<GpuBatch> opaque;

  /// Drawn after, farthest first, over what is there.
  final List<GpuBatch> translucent;

  /// How many faces the frame draws; for the meter and tests.
  final int faces;

  /// The outline of every drawn face that belongs to something, with what
  /// it belongs to: what a tap is tried against.
  final List<(List<Vec3>, SourceRef?)> picks;
}

/// How much nearer the eye than the surface under it a face is drawn, in
/// metres, so that a floor finish or a rug laid on a slab does not flicker
/// against it. The canvas painter gets the same from the order it draws in.
const _lift = 0.02;
const _roofLift = 1.2;

/// Metres toward the eye for each [ScenePainter.liftRank].
const _lifts = [0.0, _lift, _lift * 2, _roofLift];

class _Writer {
  Float32List data = Float32List(gpuVertexFloats * 1024);
  int count = 0;

  void add(Vec3 p, double r, double g, double b, double a, double u, double v) {
    final at = count * gpuVertexFloats;
    if (at + gpuVertexFloats > data.length) {
      data = Float32List(data.length * 2)..setAll(0, data);
    }
    data[at] = p.x;
    data[at + 1] = p.y;
    data[at + 2] = p.z;
    data[at + 3] = r * a;
    data[at + 4] = g * a;
    data[at + 5] = b * a;
    data[at + 6] = a;
    data[at + 7] = u;
    data[at + 8] = v;
    count++;
  }

  GpuBatch batch({ui.Image? image, bool tiled = false}) =>
      GpuBatch(Float32List.sublistView(data, 0, count * gpuVertexFloats), count,
          image: image, tiled: tiled);
}

/// Whether the GPU draws this view. It draws the house seen from outside;
/// walking through it and the see-through ground of the foundation view
/// stay with the canvas painter.
bool gpuDraws(ScenePainter p) => !p.walk && !p.settings.foundation;

/// The frame [p] would paint on a canvas of [size], for the GPU. The faces
/// shown, their cut at the section height and their colours are the canvas
/// painter's own; what differs is that depth is left to the GPU, so nothing
/// is sorted or split here.
GpuFrame buildGpuFrame(ScenePainter p, ui.Size size) {
  final camera = p.camera;
  final settings = p.settings;
  final model = p.model;
  final light = p.sun;
  final cutY = settings.cut ? settings.cutHeight : double.infinity;
  final shell = p.roofOn && !cutY.isFinite;
  final plain = _Writer();
  final textured = <(Textile, int), _Writer>{};
  final see = <(double, _Writer)>[];
  final picks = <(List<Vec3>, SourceRef?)>[];
  var faces = 0;

  void fan(_Writer w, List<Vec3> pts, ui.Color c, double alpha,
      [List<ui.Offset>? uv]) {
    for (var k = 1; k < pts.length - 1; k++) {
      for (final i in [0, k, k + 1]) {
        w.add(pts[i], c.r, c.g, c.b, alpha, uv == null ? 0.5 : uv[i].dx,
            uv == null ? 0.5 : uv[i].dy);
      }
    }
  }

  for (final f in model.faces) {
    if (!p.visible(f)) continue;
    if (f.layer == Layer3.buried || f.layer == Layer3.ceiling) continue;
    var pts = f.points;
    var clipped = false;
    if (cutY.isFinite) {
      if (f.floorIndex < 0) continue;
      if (pts.every((q) => q.y > cutY)) continue;
      if (pts.any((q) => q.y > cutY)) {
        pts = ScenePainter.clip(pts, (q) => cutY - q.y);
        clipped = true;
        if (pts.length < 3) continue;
      }
    }
    final toEye = camera.eye - pts.first;
    var n = f.normal;
    final facing = n.dot(toEye);
    if (facing.abs() < 0.012 * toEye.length) continue;
    if (facing <= 0) {
      if (!f.doubleSided && f.alpha >= 1 && !cutY.isFinite) continue;
      n = n * -1;
    }
    var centre = const Vec3(0, 0, 0);
    for (final q in f.points) {
      centre = centre + q;
    }
    centre = centre * (1 / f.points.length);
    final distance = (centre - camera.eye).length;
    var rank = ScenePainter.liftRank(f, shell);
    if (rank == 3 && facing <= 0) rank = 0;
    if (rank > 0) {
      // Brought toward the eye along the line of sight: it lands on the
      // same pixels, only nearer. A roof slope caps the wall tops that run
      // into it along its edges, so it needs more room than a finish.
      final by = _lifts[rank];
      pts = [
        for (final q in pts) q + (camera.eye - q).unit * by,
      ];
    }
    final alpha = p.faceAlpha(f);
    faces++;
    if (f.source != null) picks.add((pts, f.source));
    if (f.textile != null &&
        f.uv != null &&
        !clipped &&
        alpha >= 1 &&
        settings.style.materials) {
      final tint = p.shade(
          Face3(f.points, const ui.Color(0xffffffff),
              source: f.source, normal: f.normal),
          n,
          distance,
          light);
      // Texture coordinates run 0 to 1 across the pattern, and past 1
      // where it repeats.
      fan(textured[(f.textile!, f.textileVariant)] ??= _Writer(), pts, tint, 1,
          f.uv);
      continue;
    }
    final color = p.shade(f, n, distance, light);
    if (alpha >= 1) {
      fan(plain, pts, color, 1);
    } else {
      final w = _Writer();
      fan(w, pts, color, alpha);
      see.add((distance, w));
    }
  }
  // The cut faces of walls, filled solid as in a drawn section.
  if (cutY.isFinite && camera.eye.y > cutY + 0.01) {
    for (final b in model.sections) {
      if (b.floor > settings.maxFloor ||
          b.lo.y >= cutY - 1e-3 ||
          b.hi.y <= cutY + 1e-3) {
        continue;
      }
      final y = cutY + _sectionLift;
      faces++;
      if (b.source != null) {
        picks.add((
          [
            Vec3(b.lo.x, y, b.lo.z),
            Vec3(b.lo.x, y, b.hi.z),
            Vec3(b.hi.x, y, b.hi.z),
            Vec3(b.hi.x, y, b.lo.z),
          ],
          b.source
        ));
      }
      fan(
          plain,
          [
            Vec3(b.lo.x, y, b.lo.z),
            Vec3(b.lo.x, y, b.hi.z),
            Vec3(b.hi.x, y, b.hi.z),
            Vec3(b.hi.x, y, b.lo.z),
          ],
          b.source != null && b.source == p.selected
              ? ScenePainter.sectionSelected
              : ScenePainter.sectionFill,
          1);
    }
  }
  GpuBatch? edges;
  if (p.drawsEdges) {
    final w = _Writer();
    final ink = p.edgeColor;
    final focal = size.height / 2 / math.tan(camera.fov / 2);
    final half = p.edgeWidth / 2 / focal;
    final eye = camera.eye;
    final forward = camera.forward;
    for (final e in p.edges(cutY.isFinite ? cutY + _sectionLift : 0)) {
      var a = e.a;
      var b = e.b;
      if (e.soft) {
        // The outline of a round thing: one face toward the eye, one away.
        final toEye = eye - a;
        if ((e.n1!.dot(toEye) > 0) == (e.n2!.dot(toEye) > 0)) continue;
      }
      var da = (a - eye).dot(forward);
      var db = (b - eye).dot(forward);
      if (da < gpuNear && db < gpuNear) continue;
      if (da < gpuNear) {
        a = Vec3.lerp(a, b, (gpuNear - da) / (db - da));
        da = gpuNear;
      } else if (db < gpuNear) {
        b = Vec3.lerp(b, a, (gpuNear - db) / (da - db));
        db = gpuNear;
      }
      // Nearer than its faces by a little more than they are lifted, and
      // by more the farther off it is, where depth is coarser.
      final lift = _lifts[e.lift];
      final toA = eye - a;
      final toB = eye - b;
      final la = toA.length;
      final lb = toB.length;
      final nearA = 0.012 + 0.0016 * la;
      final nearB = 0.012 + 0.0016 * lb;
      // An edge that runs on into a wall would show through its face as
      // a dot, by as much as it is brought forward: the ends give that
      // much up, which at this distance is under a pixel.
      final run = b - a;
      final length = run.length;
      if (length <= (nearA + nearB) * 1.5) continue;
      a = a + run * (nearA / length) + toA * ((lift + nearA) / la);
      b = b - run * (nearB / length) + toB * ((lift + nearB) / lb);
      var side = (b - a).cross(eye - (a + b) * 0.5);
      final sl = side.length;
      if (sl < 1e-9) continue;
      side = side * (1 / sl);
      final sa = side * (half * da);
      final sb = side * (half * db);
      final q = [a - sa, a + sa, b + sb, b - sb];
      for (final i in const [0, 1, 2, 0, 2, 3]) {
        w.add(q[i], ink.r, ink.g, ink.b, ink.a, 0.5, 0.5);
      }
    }
    if (w.count > 0) edges = w.batch();
  }
  see.sort((a, b) => b.$1.compareTo(a.$1));
  return GpuFrame(
      gpuCameraMatrix(camera, size),
      [
        plain.batch(),
        for (final e in textured.entries)
          e.value.batch(
              image: textileImage(e.key.$1, e.key.$2),
              tiled: e.key.$1 == Textile.kurak || e.key.$1 == Textile.alasha)
      ],
      [for (final (_, w) in see) w.batch()],
      faces,
      picks,
      edges);
}

/// How far above the cut its solid fill is drawn, to cover the open tops
/// of the walls it closes.
const _sectionLift = 0.05;

/// Nearest and farthest the GPU draws, in metres from the eye.
const gpuNear = 0.05;
const gpuFar = 600.0;

/// [camera] on a canvas of [size] as one matrix: a point of the house lands
/// where [ScenePainter.project] puts it, with its distance kept as depth.
Float32List gpuCameraMatrix(Camera camera, ui.Size size) {
  final focal = size.height / 2 / math.tan(camera.fov / 2);
  final sx = focal / (size.width / 2);
  final sy = focal / (size.height / 2);
  const k = gpuFar / (gpuFar - gpuNear);
  final r = camera.right;
  final u = camera.up;
  final f = camera.forward;
  final e = camera.eye;
  final m = Float32List(16);
  void row(int i, Vec3 v, double scale, double extra) {
    m[i] = v.x * scale;
    m[4 + i] = v.y * scale;
    m[8 + i] = v.z * scale;
    m[12 + i] = -v.dot(e) * scale + extra;
  }

  row(0, r, sx, 0);
  row(1, u, sy, 0);
  row(2, f, k, -gpuNear * k);
  row(3, f, 1, 0);
  return m;
}
