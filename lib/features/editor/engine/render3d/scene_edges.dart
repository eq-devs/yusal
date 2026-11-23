import 'dart:math' as math;
import 'dart:typed_data';

import 'package:yusal/features/editor/engine/render3d/scene_model.dart';

/// A face as the edge finder sees it: its outline, which way it faces and
/// how far toward the eye it is drawn (see [SceneEdge.lift]).
class EdgeFace {
  EdgeFace(this.points, this.normal, [this.lift = 0, this.thin = false]);
  final List<Vec3> points;
  final Vec3 normal;
  final int lift;

  /// A sheet seen from both sides, with nothing solid behind it.
  final bool thin;
}

/// A line worth drawing on a shaded model: where the surface turns a
/// corner or stops, as the edge display of a CAD viewport draws it.
class SceneEdge {
  SceneEdge(this.a, this.b, this.lift, [this.n1, this.n2]);
  final Vec3 a;
  final Vec3 b;

  /// The largest [EdgeFace.lift] of the faces that meet here, so the line
  /// stays in front of the face it outlines.
  final int lift;

  /// Set on an edge where the surface only bends a little (the facets of
  /// a round thing): the two faces' normals. Such an edge is drawn only
  /// while one of them faces the eye and the other does not, which is
  /// where the round thing's outline falls.
  final Vec3? n1;
  final Vec3? n2;

  bool get soft => n1 != null;
}

/// Two faces that meet at less than this (in degrees, between their
/// normals) are one bent surface, and the edge between them is not drawn.
const creaseDegrees = 28.0;

class _Span {
  _Span(this.t0, this.t1, this.face);
  final double t0;
  final double t1;
  final int face;
}

class _Line {
  _Line(this.origin, this.direction);
  final Vec3 origin;
  final Vec3 direction;
  final spans = <_Span>[];
}

// Keys are whole numbers of these, set off from the round values that
// plan coordinates fall on, so two ends of one line do not round apart.
const _grid = 1000.0;
const _offset = 0.137;
int _q(double v) => (v * _grid + _offset).round();

/// The edges of [faces] that show the form: an edge with one face on it,
/// and an edge where two faces meet at more than [creaseDegrees]. Edges
/// that only split one flat surface into pieces are left out, however the
/// pieces overlap along the edge.
List<SceneEdge> featureEdges(List<EdgeFace> faces) {
  final lines = <(int, int, int, int, int, int), _Line>{};
  for (var i = 0; i < faces.length; i++) {
    final pts = faces[i].points;
    for (var k = 0; k < pts.length; k++) {
      final a = pts[k];
      final b = pts[(k + 1) % pts.length];
      var d = b - a;
      final len = d.length;
      if (len < 1e-4) continue;
      d = d * (1 / len);
      // One direction for both ways along the line.
      final flip = d.x.abs() > 1e-6
          ? d.x < 0
          : d.y.abs() > 1e-6
              ? d.y < 0
              : d.z < 0;
      if (flip) d = d * -1;
      final foot = a - d * a.dot(d);
      final key = (
        (d.x * 2000).round(),
        (d.y * 2000).round(),
        (d.z * 2000).round(),
        _q(foot.x),
        _q(foot.y),
        _q(foot.z)
      );
      final line = lines[key] ??= _Line(foot, d);
      final ta = a.dot(d);
      final tb = b.dot(d);
      line.spans.add(_Span(math.min(ta, tb), math.max(ta, tb), i));
    }
  }
  // Faces by the plane they lie in: wall pieces overlap where walls
  // join, and an edge of one that runs across another piece of the same
  // surface is no edge of the surface.
  final planes = <(int, int, int, int), List<int>>{};
  final planeOf = List<(int, int, int, int)?>.filled(faces.length, null);
  for (var i = 0; i < faces.length; i++) {
    final f = faces[i];
    if (f.points.length < 3) continue;
    final n = f.normal;
    final key = (
      (n.x * 2000).round(),
      (n.y * 2000).round(),
      (n.z * 2000).round(),
      _q(n.dot(f.points.first))
    );
    planeOf[i] = key;
    (planes[key] ??= []).add(i);
  }
  final boxes = Float64List(faces.length * 6);
  for (var i = 0; i < faces.length; i++) {
    var x0 = double.infinity;
    var y0 = double.infinity;
    var z0 = double.infinity;
    var x1 = -double.infinity;
    var y1 = -double.infinity;
    var z1 = -double.infinity;
    for (final p in faces[i].points) {
      if (p.x < x0) x0 = p.x;
      if (p.y < y0) y0 = p.y;
      if (p.z < z0) z0 = p.z;
      if (p.x > x1) x1 = p.x;
      if (p.y > y1) y1 = p.y;
      if (p.z > z1) z1 = p.z;
    }
    boxes
      ..[i * 6] = x0
      ..[i * 6 + 1] = y0
      ..[i * 6 + 2] = z0
      ..[i * 6 + 3] = x1
      ..[i * 6 + 4] = y1
      ..[i * 6 + 5] = z1;
  }
  final planeList = [
    for (final e in planes.entries)
      (
        faces[e.value.first].normal,
        faces[e.value.first].normal.dot(faces[e.value.first].points.first),
        e.key,
        e.value
      )
  ];
  final live = <int>[];

  /// Leaves in [live] the faces of [on] that really end at [at]: not one
  /// that carries on as another piece of the same flat surface there, and
  /// not one that runs into a surface from behind (the end of a partition
  /// buried in the outer wall it joins).
  void sift(List<int> on, Vec3 at, Vec3 along) {
    live
      ..clear()
      ..addAll(on);
    // Two pieces of one flat surface that meet along this edge, one on
    // each side of it, make the surface whole here: whatever else ends on
    // the edge from behind it is buried (a floor slab reaching the outer
    // face of the walls above and below it).
    for (var i = 0; i < on.length && on.length > 2; i++) {
      final f = on[i];
      final key = planeOf[f];
      if (key == null || faces[f].thin) continue;
      final n = faces[f].normal;
      final across = n.cross(along);
      double side(int face) {
        var far = 0.0;
        for (final v in faces[face].points) {
          final s = (v - at).dot(across);
          if (s.abs() > far.abs()) far = s;
        }
        return far;
      }

      final mine = side(f);
      var whole = false;
      for (var j = i + 1; j < on.length; j++) {
        if (planeOf[on[j]] == key && side(on[j]) * mine < 0) whole = true;
      }
      if (!whole) continue;
      final d = n.dot(at);
      live.removeWhere((h) {
        if (planeOf[h] == key) return false;
        for (final v in faces[h].points) {
          if (n.dot(v) - d > 1e-4) return false;
        }
        return true;
      });
    }
    for (final (n, d, key, members) in planeList) {
      if ((n.dot(at) - d).abs() > 6e-4) continue;
      for (final g in members) {
        if (live.isEmpty) return;
        if (on.contains(g)) continue;
        final b = g * 6;
        const pad = 1e-3;
        if (at.x < boxes[b] - pad ||
            at.y < boxes[b + 1] - pad ||
            at.z < boxes[b + 2] - pad ||
            at.x > boxes[b + 3] + pad ||
            at.y > boxes[b + 4] + pad ||
            at.z > boxes[b + 5] + pad) {
          continue;
        }
        if (!_inside(faces[g], at)) continue;
        live.removeWhere((f) {
          if (planeOf[f] == key) return true;
          if (faces[g].thin) return false;
          for (final v in faces[f].points) {
            if (n.dot(v) - d > 1e-4) return false;
          }
          return true;
        });
      }
    }
  }

  final cosCrease = math.cos(creaseDegrees * math.pi / 180);
  final out = <SceneEdge>[];
  final cuts = <double>[];
  final on = <int>[];
  final ends = <int>[];
  for (final line in lines.values) {
    final spans = line.spans;
    Vec3 at(double t) => line.origin + line.direction * t;
    cuts.clear();
    for (final s in spans) {
      cuts
        ..add(s.t0)
        ..add(s.t1);
    }
    cuts.sort();
    // What the stretch before the current one was, to join equal ones.
    var runKind = 0; // 0 none, 1 hard, 2 soft
    var runStart = 0.0;
    var runEnd = 0.0;
    var runLift = 0;
    Vec3? runN1;
    Vec3? runN2;
    void close() {
      if (runKind == 1) {
        out.add(SceneEdge(at(runStart), at(runEnd), runLift));
      } else if (runKind == 2) {
        out.add(SceneEdge(at(runStart), at(runEnd), runLift, runN1, runN2));
      }
      runKind = 0;
    }

    for (var c = 0; c + 1 < cuts.length; c++) {
      final t0 = cuts[c];
      final t1 = cuts[c + 1];
      if (t1 - t0 < 5e-4) continue;
      final mid = (t0 + t1) / 2;
      on.clear();
      for (final s in spans) {
        if (s.t0 < mid && s.t1 > mid) on.add(s.face);
      }
      var kind = 0;
      var lift = 0;
      Vec3? n1;
      Vec3? n2;
      if (on.isNotEmpty) sift(on, at(mid), line.direction);
      if (on.isNotEmpty && live.isNotEmpty) {
        on
          ..clear()
          ..addAll(live);
        for (final f in on) {
          lift = math.max(lift, faces[f].lift);
        }
        // Pieces of one flat surface on both sides of the line make it
        // whole there and end nothing; on one side only, however many
        // lap, they are one surface ending.
        final point = at(mid);
        ends.clear();
        for (final f in on) {
          final key = planeOf[f];
          if (ends.any((e) => planeOf[e] == key)) continue;
          final across = faces[f].normal.cross(line.direction);
          var left = false;
          var right = false;
          for (final g in on) {
            if (planeOf[g] != key) continue;
            var far = 0.0;
            for (final v in faces[g].points) {
              final s = (v - point).dot(across);
              if (s.abs() > far.abs()) far = s;
            }
            if (far < 0) left = true;
            if (far > 0) right = true;
          }
          if (!(left && right)) ends.add(f);
        }
        on
          ..clear()
          ..addAll(ends);
        if (on.isEmpty) {
          kind = 0;
        } else if (on.length == 1) {
          kind = 1;
        } else {
          var least = 1.0;
          for (var i = 0; i < on.length; i++) {
            for (var j = i + 1; j < on.length; j++) {
              final dot = faces[on[i]].normal.dot(faces[on[j]].normal);
              if (dot < least) {
                least = dot;
                n1 = faces[on[i]].normal;
                n2 = faces[on[j]].normal;
              }
            }
          }
          if (least < cosCrease) {
            kind = 1;
            n1 = n2 = null;
          } else if (least < 0.9995 && on.length == 2) {
            kind = 2;
          }
        }
      }
      final joins = kind == runKind &&
          kind != 0 &&
          lift == runLift &&
          (t0 - runEnd).abs() < 1e-3 &&
          (kind == 1 || (identical(n1, runN1) && identical(n2, runN2)));
      if (joins) {
        runEnd = t1;
        continue;
      }
      close();
      if (kind != 0) {
        runKind = kind;
        runStart = t0;
        runEnd = t1;
        runLift = lift;
        runN1 = n1;
        runN2 = n2;
      }
    }
    close();
  }
  return out;
}

/// Where the hard edges of a scene run, for asking whether a stretch of a
/// face's outline lies on one: what the canvas painter strokes as it
/// paints each face.
class EdgeIndex {
  EdgeIndex(List<SceneEdge> edges) {
    for (final e in edges) {
      if (e.soft) continue;
      final k = _key(e.a, e.b);
      if (k == null) continue;
      (_runs[k.$1] ??= []).add((k.$2, k.$3));
    }
  }

  final _runs = <(int, int, int, int, int, int), List<(double, double)>>{};

  bool get isEmpty => _runs.isEmpty;

  static ((int, int, int, int, int, int), double, double)? _key(
      Vec3 a, Vec3 b) {
    var d = b - a;
    final len = d.length;
    if (len < 1e-4) return null;
    d = d * (1 / len);
    final flip = d.x.abs() > 1e-6
        ? d.x < 0
        : d.y.abs() > 1e-6
            ? d.y < 0
            : d.z < 0;
    if (flip) d = d * -1;
    final foot = a - d * a.dot(d);
    final ta = a.dot(d);
    final tb = b.dot(d);
    return (
      (
        (d.x * 2000).round(),
        (d.y * 2000).round(),
        (d.z * 2000).round(),
        _q(foot.x),
        _q(foot.y),
        _q(foot.z)
      ),
      math.min(ta, tb),
      math.max(ta, tb)
    );
  }

  /// The parts of the stretch from [a] to [b] that lie on a hard edge, as
  /// fractions of the way from [a] to [b].
  List<(double, double)> along(Vec3 a, Vec3 b) {
    final k = _key(a, b);
    if (k == null) return const [];
    final runs = _runs[k.$1];
    if (runs == null) return const [];
    final (_, t0, t1) = k;
    final d = b - a;
    final len = d.length;
    final forward = (b - a).dot(_dir(k.$1)) >= 0;
    final out = <(double, double)>[];
    for (final (r0, r1) in runs) {
      final lo = math.max(t0, r0);
      final hi = math.min(t1, r1);
      if (hi - lo < 1e-3) continue;
      final f0 = (lo - t0) / len;
      final f1 = (hi - t0) / len;
      out.add(forward ? (f0, f1) : (1 - f1, 1 - f0));
    }
    return out;
  }

  static Vec3 _dir((int, int, int, int, int, int) k) =>
      Vec3(k.$1 / 2000, k.$2 / 2000, k.$3 / 2000);
}

/// Whether [p], a point in the plane of [f], lies inside it and clear of
/// its outline.
bool _inside(EdgeFace f, Vec3 p) {
  final n = f.normal;
  final ax = n.x.abs();
  final ay = n.y.abs();
  final az = n.z.abs();
  // Looked at along the axis the face is most square to.
  double u(Vec3 v) => ax >= ay && ax >= az ? v.y : v.x;
  double w(Vec3 v) => az > ax && az >= ay ? v.y : v.z;
  final pu = u(p);
  final pw = w(p);
  final pts = f.points;
  var inside = false;
  const margin = 6e-4;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final au = u(pts[i]);
    final aw = w(pts[i]);
    final bu = u(pts[j]);
    final bw = w(pts[j]);
    // On or beside the outline is not inside.
    final du = bu - au;
    final dw = bw - aw;
    final len2 = du * du + dw * dw;
    if (len2 > 0) {
      final t = (((pu - au) * du + (pw - aw) * dw) / len2).clamp(0.0, 1.0);
      final cu = au + du * t - pu;
      final cw = aw + dw * t - pw;
      if (cu * cu + cw * cw < margin * margin) return false;
    }
    if ((aw > pw) != (bw > pw) && pu < (bu - au) * (pw - aw) / (bw - aw) + au) {
      inside = !inside;
    }
  }
  return inside;
}
