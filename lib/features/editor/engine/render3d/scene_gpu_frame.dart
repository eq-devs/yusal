import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yusal/features/editor/engine/core/geometry/source_ref.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';
import 'package:yusal/features/editor/engine/render3d/textures.dart';

/// Floats to a vertex: position, colour (alpha multiplied in), texture
/// coordinate, the face's normal toward the eye, the share of its light it
/// loses in shadow, and where it truly is when it is drawn nearer the eye.
const gpuVertexFloats = 16;

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
      [this.picks = const [], this.edges, this.effects, this.eye]);

  /// What shadows and darkened corners are worked out from; null when the
  /// frame has neither.
  final GpuEffects? effects;

  /// Where the eye is, in the house's coordinates.
  final Vec3? eye;

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

/// Everything solid in the view as bare triangles, and the sun's view of
/// it: what the GPU draws twice more, once from the sun for shadows and
/// once from the eye for the corners.
class GpuEffects {
  GpuEffects(
      this.solids,
      this.count,
      this.light,
      this.lightKey,
      this.sun,
      this.corners,
      this.bias,
      this.camera,
      this.cameraRow,
      this.far,
      this.forward,
      this.right,
      this.up,
      this.sx,
      this.sy);

  /// [count] points of three floats, three to a triangle. The same list
  /// from frame to frame while the house and what is shown of it stay.
  final Float32List solids;
  final int count;

  /// Column-major, from the house to the sun's view.
  final Float32List light;

  /// Changes when the shadows have to be drawn again.
  final String lightKey;

  /// How strong the sun's shadows are, 0 for none, and the corners.
  final double sun;
  final double corners;

  /// How much nearer the sun a point is taken to be, of the whole depth.
  final double bias;

  /// The eye's own matrix and what gives a point's distance from it as a
  /// share of [far].
  final Float32List camera;
  final Float32List cameraRow;
  final double far;
  final Vec3 forward;
  final Vec3 right;
  final Vec3 up;
  final double sx;
  final double sy;
}

/// How far a corner darkens what is near it, in metres.
const gpuCornerReach = 0.55;

/// The side of the square picture the sun's view is drawn on.
const gpuShadowMapSize = 2048;

class _Solids {
  _Solids(this.key, this.data, this.count);
  final String key;
  final Float32List data;
  final int count;
  final lights = <String, (Float32List, double)>{};
}

final _solids = Expando<_Solids>('gpu solids');

/// The sun's view of [points]: a box around them, looked at along [sun].
(Float32List, double) _lightMatrix(Float32List points, int count, Vec3 sun) {
  final l = sun.unit;
  final r = const Vec3(0, 1, 0).cross(l).unit;
  final u = l.cross(r);
  var x0 = double.infinity;
  var x1 = -double.infinity;
  var y0 = double.infinity;
  var y1 = -double.infinity;
  var z0 = double.infinity;
  var z1 = -double.infinity;
  for (var i = 0; i < count * 3; i += 3) {
    final p = Vec3(points[i], points[i + 1], points[i + 2]);
    final x = r.dot(p);
    final y = u.dot(p);
    final z = l.dot(p);
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
    if (z < z0) z0 = z;
    if (z > z1) z1 = z;
  }
  if (count == 0) {
    x0 = y0 = z0 = 0;
    x1 = y1 = z1 = 1;
  }
  final hx = math.max((x1 - x0) / 2, 0.5) * 1.02;
  final hy = math.max((y1 - y0) / 2, 0.5) * 1.02;
  final cx = (x0 + x1) / 2;
  final cy = (y0 + y1) / 2;
  final depth = math.max(z1 - z0, 1.0) + 1;
  final m = Float32List(16);
  void row(int i, Vec3 v, double scale, double extra) {
    m[i] = v.x * scale;
    m[4 + i] = v.y * scale;
    m[8 + i] = v.z * scale;
    m[12 + i] = extra;
  }

  row(0, r, 1 / hx, -cx / hx);
  row(1, u, 1 / hy, -cy / hy);
  // Nearest the sun is 0.
  row(2, l, -1 / depth, (z1 + 0.5) / depth);
  m[15] = 1;
  return (m, depth);
}

/// How much nearer the eye than the surface under it a face is drawn, in
/// metres, so that a floor finish or a rug laid on a slab does not flicker
/// against it. The canvas painter gets the same from the order it draws in.
const _lift = 0.02;
const _roofLift = 1.2;
const _roofThickness = 0.16;

/// Metres toward the eye for each [ScenePainter.liftRank].
const _lifts = [0.0, _lift, _lift * 2, _roofLift];

class _Writer {
  Float32List data = Float32List(gpuVertexFloats * 1024);
  int count = 0;

  void add(Vec3 p, double r, double g, double b, double a, double u, double v,
      [Vec3? n, double k = 0, Vec3? world]) {
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
    if (n != null) {
      data[at + 9] = n.x;
      data[at + 10] = n.y;
      data[at + 11] = n.z;
      data[at + 12] = k;
    } else {
      // A grown list is fresh, a reused one is not.
      data[at + 9] = data[at + 10] = data[at + 11] = data[at + 12] = 0;
    }
    final w = world ?? p;
    data[at + 13] = w.x;
    data[at + 14] = w.y;
    data[at + 15] = w.z;
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
  // See-through faces, drawn farthest first. They all go into one buffer
  // and one draw call: triangles blend in the order they are sent.
  final see = <(double, List<Vec3>, ui.Color, double)>[];
  final picks = <(List<Vec3>, SourceRef?)>[];
  var faces = 0;

  void fan(_Writer w, List<Vec3> pts, ui.Color c, double alpha,
      [List<ui.Offset>? uv, Vec3? n, double share = 0, List<Vec3>? at]) {
    for (var k = 1; k < pts.length - 1; k++) {
      for (final i in [0, k, k + 1]) {
        w.add(pts[i], c.r, c.g, c.b, alpha, uv == null ? 0.5 : uv[i].dx,
            uv == null ? 0.5 : uv[i].dy, n, share, at?[i]);
      }
    }
  }

  // Shadows and corners, where the renderer can and the style has light.
  final shaded = SceneGpu.effects &&
      (p.gpu?.shades ?? false) &&
      settings.style != SceneStyle.lines;
  final solidsKey = '${p.roofOn} ${settings.furniture} ${settings.maxFloor} '
      '$cutY';
  var solids = shaded ? _solids[model] : null;
  // Gathered afresh when what is shown of the house has changed.
  final gather = shaded && solids?.key != solidsKey ? <double>[] : null;
  void solid(List<Vec3> pts) {
    for (var k = 1; k < pts.length - 1; k++) {
      for (final i in [0, k, k + 1]) {
        gather!
          ..add(pts[i].x)
          ..add(pts[i].y)
          ..add(pts[i].z);
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
    final alpha = p.faceAlpha(f);
    if (gather != null && alpha >= 1) solid(pts);
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
    // Where the face is for light and shadow. The roof is two sheets, and
    // the one drawn is the lower: it takes the light of the upper.
    final unlifted =
        rank == 3 ? [for (final q in pts) q + n * _roofThickness] : pts;
    if (rank > 0) {
      final by = _lifts[rank];
      // Brought toward the eye along the line of sight: it lands on the
      // same pixels, only nearer. A roof slope caps the wall tops that run
      // into it along its edges, so it needs more room than a finish.
      pts = [
        for (final q in pts) q + (camera.eye - q).unit * by,
      ];
    }
    final share = shaded ? p.shadowShare(f, n, light) : 0.0;
    faces++;
    // Faces that belong to nothing (roof, slabs) still hide what is behind
    // them from a tap; glass only when it is a window that can be picked.
    if (f.source != null || f.alpha >= 1) picks.add((pts, f.source));
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
          f.uv, n, share, unlifted);
      continue;
    }
    final color = p.shade(f, n, distance, light);
    if (alpha >= 1) {
      fan(plain, pts, color, 1, null, n, share, unlifted);
    } else {
      see.add((distance, pts, color, alpha));
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
      if (gather != null) {
        solid([
          Vec3(b.lo.x, cutY, b.lo.z),
          Vec3(b.lo.x, cutY, b.hi.z),
          Vec3(b.hi.x, cutY, b.hi.z),
          Vec3(b.hi.x, cutY, b.lo.z),
        ]);
      }
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
  final glass = _Writer();
  for (final (_, pts, color, alpha) in see) {
    fan(glass, pts, color, alpha);
  }
  final mvp = gpuCameraMatrix(camera, size);
  GpuEffects? effects;
  if (shaded) {
    if (gather != null) {
      solids = _solids[model] =
          _Solids(solidsKey, Float32List.fromList(gather), gather.length ~/ 3);
    }
    final night = settings.night;
    final lightKey = '${light.x.toStringAsFixed(4)} '
        '${light.y.toStringAsFixed(4)} ${light.z.toStringAsFixed(4)}';
    final (matrix, depth) = solids!.lights[lightKey] ??=
        _lightMatrix(solids.data, solids.count, light);
    if (solids.lights.length > 8) {
      solids.lights
        ..clear()
        ..[lightKey] = (matrix, depth);
    }
    final focal = size.height / 2 / math.tan(camera.fov / 2);
    final f = camera.forward;
    effects = GpuEffects(
        solids.data,
        solids.count,
        matrix,
        '$solidsKey $lightKey',
        night ? 0 : 1,
        night ? 0.45 : 0.6,
        0.04 / depth,
        mvp,
        Float32List.fromList([
          f.x / gpuFar,
          f.y / gpuFar,
          f.z / gpuFar,
          -f.dot(camera.eye) / gpuFar
        ]),
        gpuFar,
        f,
        camera.right,
        camera.up,
        focal / (size.width / 2),
        focal / (size.height / 2));
  }
  return GpuFrame(
      mvp,
      [
        plain.batch(),
        for (final e in textured.entries)
          e.value.batch(
              image: textileImage(e.key.$1, e.key.$2),
              tiled: e.key.$1 == Textile.kurak || e.key.$1 == Textile.alasha)
      ],
      [if (glass.count > 0) glass.batch()],
      faces,
      picks,
      edges,
      effects,
      camera.eye);
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
