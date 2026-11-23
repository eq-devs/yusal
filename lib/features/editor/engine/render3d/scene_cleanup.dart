import 'package:yusal/features/editor/engine/render3d/scene_model.dart';

/// Hidden-surface removal done once, when the scene is built.
///
/// Walls come from the core as a grid of boxes split at every opening's
/// sides, sill and head, so most box faces lie flat against a neighbour
/// and can never be seen. Drawn anyway they cost time on every frame,
/// make the BSP tree split the real faces, and leak as light hairlines
/// through the anti-aliased seams of the faces in front of them.
///
/// 1. A face lying against solid boxes that show whenever it shows, and
///    covering it completely, is dropped.
/// 2. Faces left on the same plane with the same look that share a whole
///    edge are merged into one rectangle (a wall reads as a few faces
///    again instead of a dozen strips).
List<Face3> cleanFaces(List<Face3> faces, List<SolidBox> solids) {
  final kept = <Face3>[];
  final rects = <_Rect>[];
  for (final f in faces) {
    final r = _Rect.of(f);
    if (r == null) {
      kept.add(f);
      continue;
    }
    if (_covered(r, f, solids)) continue;
    rects.add(r);
  }
  return [...kept, ..._merge(rects)];
}

/// An axis-aligned rectangular face: [axis] is its normal's axis, [c] the
/// plane, [u0]–[u1] and [v0]–[v1] its extent along the other two axes.
class _Rect {
  _Rect(this.face, this.axis, this.c, this.u0, this.u1, this.v0, this.v1);
  final Face3 face;
  final int axis;
  final double c;
  double u0;
  double u1;
  double v0;
  double v1;

  static double get(Vec3 p, int a) => a == 0 ? p.x : (a == 1 ? p.y : p.z);
  static int uAxis(int a) => a == 0 ? 1 : 0;
  static int vAxis(int a) => a == 2 ? 1 : 2;

  static _Rect? of(Face3 f) {
    if (f.points.length != 4 || f.textile != null) return null;
    final n = f.normal;
    final axis = n.x.abs() > 0.9999
        ? 0
        : n.y.abs() > 0.9999
            ? 1
            : n.z.abs() > 0.9999
                ? 2
                : -1;
    if (axis < 0) return null;
    final ua = uAxis(axis);
    final va = vAxis(axis);
    final us = <double>{};
    final vs = <double>{};
    final c = get(f.points.first, axis);
    for (final p in f.points) {
      if ((get(p, axis) - c).abs() > 1e-6) return null;
      us.add(get(p, ua));
      vs.add(get(p, va));
    }
    if (us.length != 2 || vs.length != 2) return null;
    final ul = us.toList()..sort();
    final vl = vs.toList()..sort();
    return _Rect(f, axis, c, ul[0], ul[1], vl[0], vl[1]);
  }

  /// The face over the current extent, keeping the original winding.
  Face3 build() {
    final f = face;
    final ua = uAxis(axis);
    final va = vAxis(axis);
    final ou0 = f.points.map((p) => get(p, ua)).reduce((a, b) => a < b ? a : b);
    final ov0 = f.points.map((p) => get(p, va)).reduce((a, b) => a < b ? a : b);
    final pts = <Vec3>[];
    for (final p in f.points) {
      final u = get(p, ua) == ou0 ? u0 : u1;
      final v = get(p, va) == ov0 ? v0 : v1;
      final xyz = [0.0, 0.0, 0.0];
      xyz[axis] = c;
      xyz[ua] = u;
      xyz[va] = v;
      pts.add(Vec3(xyz[0], xyz[1], xyz[2]));
    }
    return f.withPoints(pts);
  }
}

const _eps = 1e-4;

bool _covered(_Rect r, Face3 f, List<SolidBox> solids) {
  // Only boxes that always show with the face may hide it.
  final out = r.face.normal.dot(
          Vec3(r.axis == 0 ? 1 : 0, r.axis == 1 ? 1 : 0, r.axis == 2 ? 1 : 0)) >
      0;
  final ua = _Rect.uAxis(r.axis);
  final va = _Rect.vAxis(r.axis);
  final cover = <(double, double, double, double)>[];
  for (final s in solids) {
    if (s.floor != f.floorIndex ||
        s.roof != f.roof ||
        s.furniture != f.furniture ||
        s.layer != f.layer) {
      continue;
    }
    final touch = out ? _Rect.get(s.lo, r.axis) : _Rect.get(s.hi, r.axis);
    if ((touch - r.c).abs() > _eps) continue;
    final su0 = _Rect.get(s.lo, ua);
    final su1 = _Rect.get(s.hi, ua);
    final sv0 = _Rect.get(s.lo, va);
    final sv1 = _Rect.get(s.hi, va);
    if (su1 <= r.u0 + _eps || su0 >= r.u1 - _eps) continue;
    if (sv1 <= r.v0 + _eps || sv0 >= r.v1 - _eps) continue;
    cover.add((su0, su1, sv0, sv1));
  }
  if (cover.isEmpty) return false;
  // Covered when every cell of the grid the boxes' edges make is.
  final us = {r.u0, r.u1};
  final vs = {r.v0, r.v1};
  for (final b in cover) {
    if (b.$1 > r.u0 && b.$1 < r.u1) us.add(b.$1);
    if (b.$2 > r.u0 && b.$2 < r.u1) us.add(b.$2);
    if (b.$3 > r.v0 && b.$3 < r.v1) vs.add(b.$3);
    if (b.$4 > r.v0 && b.$4 < r.v1) vs.add(b.$4);
  }
  final ul = us.toList()..sort();
  final vl = vs.toList()..sort();
  for (var i = 0; i < ul.length - 1; i++) {
    for (var j = 0; j < vl.length - 1; j++) {
      if (ul[i + 1] - ul[i] < _eps || vl[j + 1] - vl[j] < _eps) continue;
      final u = (ul[i] + ul[i + 1]) / 2;
      final v = (vl[j] + vl[j + 1]) / 2;
      if (!cover.any((b) =>
          u >= b.$1 - _eps &&
          u <= b.$2 + _eps &&
          v >= b.$3 - _eps &&
          v <= b.$4 + _eps)) {
        return false;
      }
    }
  }
  return true;
}

/// Join rectangles on one plane with the same look that share an edge.
List<Face3> _merge(List<_Rect> rects) {
  final groups = <Object, List<_Rect>>{};
  for (final r in rects) {
    final f = r.face;
    final key = (
      r.axis,
      (r.c / _eps).round(),
      f.normal.dot(const Vec3(1, 1, 1)) > 0,
      f.color,
      f.alpha,
      f.layer,
      f.source,
      f.doubleSided,
      f.glow,
      f.roof,
      f.furniture,
      f.floorIndex,
      f.castsShadow,
      f.interior,
      f.covering,
      f.capOnly,
      f.enclosed,
    );
    (groups[key] ??= []).add(r);
  }
  bool near(double a, double b) => (a - b).abs() < _eps;
  final out = <Face3>[];
  for (final g in groups.values) {
    var changed = true;
    while (changed && g.length > 1) {
      changed = false;
      for (var i = 0; i < g.length && !changed; i++) {
        for (var j = i + 1; j < g.length; j++) {
          final a = g[i];
          final b = g[j];
          if (near(a.v0, b.v0) &&
              near(a.v1, b.v1) &&
              (near(a.u1, b.u0) || near(b.u1, a.u0))) {
            a.u0 = a.u0 < b.u0 ? a.u0 : b.u0;
            a.u1 = a.u1 > b.u1 ? a.u1 : b.u1;
          } else if (near(a.u0, b.u0) &&
              near(a.u1, b.u1) &&
              (near(a.v1, b.v0) || near(b.v1, a.v0))) {
            a.v0 = a.v0 < b.v0 ? a.v0 : b.v0;
            a.v1 = a.v1 > b.v1 ? a.v1 : b.v1;
          } else {
            continue;
          }
          g.removeAt(j);
          changed = true;
          break;
        }
      }
    }
    for (final r in g) {
      out.add(r.build());
    }
  }
  return out;
}
